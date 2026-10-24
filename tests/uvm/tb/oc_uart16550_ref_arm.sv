// The U2B0 reference arm: the OpenCores uart16550 core through the 32-bit
// WISHBONE shim (src/ref/oc_uart16550_wb32.sv), and around it:
//   u_wb      fw-proto-wb initiator transactor: the register port
//   u_b2b     a WISHBONE driver that makes two accesses with 0 or more idle
//             clocks between them (U13); owns the bus while it runs
//   u_tx      fw-proto-uart tx transactor, driving srx
//   u_rx      fw-proto-uart rx transactor, on stx
//   u_mon_tx  monitor on stx (the DUT transmits)
//   u_mon_rx  monitor on srx (the DUT receives)
//   pads      the modem input pads, an srx override, and the pins the
//             bench watches (uart_ref_pads_if)
// Instanced by hdl_top_ref, and later by the equivalence tops. uart_ref_model
// drives it through the transactors' u_if and `pads`.
//
// Values the HVL side writes through a virtual interface reach the core
// through a clocked copy (one clock late): a continuous assign from such a
// variable does not reliably re-trigger in Verilator (fw-proto-uart note).

// The bench's pins on the arm, for the HVL side.
interface uart_ref_pads_if (input logic clock);
    // Written by the bench.
    logic        cts = 1'b0, dsr = 1'b0, ri = 1'b0, dcd = 1'b0;
    logic        srx_ovr_en = 1'b0;    // srx from srx_ovr, not the tx transactor
    logic        srx_ovr    = 1'b1;
    // The back-to-back driver's request (U13): set the fields, then toggle go.
    logic        b2b_go = 1'b0;
    logic [4:0]  b2b_adr0, b2b_adr1;
    logic [7:0]  b2b_dat0, b2b_dat1;
    logic        b2b_we0, b2b_we1;
    logic [3:0]  b2b_gap;
    // Watched by the bench.
    logic        int_o, stx, srx, rts, dtr;
    logic        b2b_busy;
    logic [7:0]  b2b_rd0, b2b_rd1;

    task automatic wait_clocks(int unsigned n);
        repeat (n) @(posedge clock);
    endtask

    // Two accesses with `gap` idle clocks between the first ack and the
    // second strobe. Returns the read data of each.
    task automatic b2b(input bit we0, input bit [4:0] adr0, input bit [7:0] dat0,
                       input bit we1, input bit [4:0] adr1, input bit [7:0] dat1,
                       input bit [3:0] gap, output bit [7:0] rd0, output bit [7:0] rd1);
        b2b_we0 = we0; b2b_adr0 = adr0; b2b_dat0 = dat0;
        b2b_we1 = we1; b2b_adr1 = adr1; b2b_dat1 = dat1;
        b2b_gap = gap;
        b2b_go  = !b2b_go;
        repeat (3) @(posedge clock);
        while (b2b_busy) @(posedge clock);
        rd0 = b2b_rd0;
        rd1 = b2b_rd1;
    endtask
endinterface

// Two WISHBONE classic accesses, the second `gap` clocks after the first's
// ack (gap 0: the strobe stays up and the address changes in the clock the
// ack is seen). Starts on a change of `go`.
module wb_b2b_driver (
        input  wire        clock,
        input  wire        reset,
        input  wire        go,
        input  wire [4:0]  adr0, adr1,
        input  wire [7:0]  dat0, dat1,
        input  wire        we0, we1,
        input  wire [3:0]  gap,
        output reg         busy,
        output reg  [7:0]  rd0, rd1,
        // the bus
        output reg         cyc, stb, we,
        output reg  [4:0]  adr,
        output reg  [31:0] dat_w,
        input  wire [31:0] dat_r,
        input  wire        ack
    );
    reg       go_q;
    reg [1:0] state;    // 0 idle, 1 first, 2 gap, 3 second
    reg [3:0] cnt;

    always @(posedge clock) begin
        if (reset) begin
            go_q  <= go;
            busy  <= 1'b0;
            state <= 2'd0;
            cyc   <= 1'b0;
            stb   <= 1'b0;
            we    <= 1'b0;
            adr   <= 5'd0;
            dat_w <= 32'd0;
            rd0   <= 8'd0;
            rd1   <= 8'd0;
            cnt   <= 4'd0;
        end else begin
            go_q <= go;
            case (state)
            2'd0: if (go != go_q) begin
                busy  <= 1'b1;
                cyc   <= 1'b1;
                stb   <= 1'b1;
                we    <= we0;
                adr   <= adr0;
                dat_w <= {24'd0, dat0};
                state <= 2'd1;
            end
            2'd1: if (ack) begin
                rd0 <= dat_r[7:0];
                if (gap == 0) begin
                    we    <= we1;
                    adr   <= adr1;
                    dat_w <= {24'd0, dat1};
                    state <= 2'd3;
                end else begin
                    cyc   <= 1'b0;
                    stb   <= 1'b0;
                    cnt   <= gap - 1;
                    state <= 2'd2;
                end
            end
            2'd2: if (cnt == 0) begin
                cyc   <= 1'b1;
                stb   <= 1'b1;
                we    <= we1;
                adr   <= adr1;
                dat_w <= {24'd0, dat1};
                state <= 2'd3;
            end else
                cnt <= cnt - 1;
            2'd3: if (ack) begin
                rd1   <= dat_r[7:0];
                cyc   <= 1'b0;
                stb   <= 1'b0;
                busy  <= 1'b0;
                state <= 2'd0;
            end
            endcase
        end
    end
endmodule

module oc_uart16550_ref_arm (
        input  wire clock,
        input  wire reset
    );
    uart_ref_pads_if pads (.clock(clock));

    // ---- register port: the initiator transactor, or the b2b driver
    wire [31:0] x_adr, x_dat_w, dat_r;
    wire [3:0]  x_sel;
    wire        x_cyc, x_stb, x_we, x_ack, ack, err;

    wb_initiator_xtor #(.ADDR_WIDTH(32), .DATA_WIDTH(32)) u_wb (
        .clock(clock), .reset(reset),
        .adr(x_adr), .dat_w(x_dat_w), .dat_r(dat_r), .cyc(x_cyc), .err(err),
        .sel(x_sel), .stb(x_stb), .ack(x_ack), .we(x_we));

    // Clocked copies of the bench's writes.
    reg       b2b_go_q;
    reg [3:0] modem_q;       // {cts, dsr, ri, dcd}
    reg       srx_ovr_en_q, srx_ovr_q;
    always @(posedge clock) begin
        b2b_go_q     <= pads.b2b_go;
        modem_q      <= {pads.cts, pads.dsr, pads.ri, pads.dcd};
        srx_ovr_en_q <= pads.srx_ovr_en;
        srx_ovr_q    <= pads.srx_ovr;
    end

    wire        d_cyc, d_stb, d_we, d_busy;
    wire [4:0]  d_adr;
    wire [31:0] d_dat_w;
    wb_b2b_driver u_b2b (
        .clock(clock), .reset(reset), .go(b2b_go_q),
        .adr0(pads.b2b_adr0), .adr1(pads.b2b_adr1),
        .dat0(pads.b2b_dat0), .dat1(pads.b2b_dat1),
        .we0(pads.b2b_we0), .we1(pads.b2b_we1), .gap(pads.b2b_gap),
        .busy(d_busy), .rd0(pads.b2b_rd0), .rd1(pads.b2b_rd1),
        .cyc(d_cyc), .stb(d_stb), .we(d_we), .adr(d_adr), .dat_w(d_dat_w),
        .dat_r(dat_r), .ack(ack));
    assign pads.b2b_busy = d_busy;

    wire        cyc   = d_busy ? d_cyc   : x_cyc;
    wire        stb   = d_busy ? d_stb   : x_stb;
    wire        we    = d_busy ? d_we    : x_we;
    wire [4:0]  adr   = d_busy ? d_adr   : x_adr[4:0];
    wire [31:0] dat_w = d_busy ? d_dat_w : x_dat_w;
    assign      x_ack = ack && !d_busy;

    // ---- serial pins
    wire tx_line, stx, srx, rts, dtr, int_o;
    assign srx = srx_ovr_en_q ? srx_ovr_q : tx_line;

    oc_uart16550_wb32 u_dut (
        .wb_clk_i(clock), .wb_rst_i(reset),
        .wb_adr_i(adr), .wb_dat_i(dat_w), .wb_dat_o(dat_r),
        .wb_sel_i(4'hF), .wb_we_i(we), .wb_stb_i(stb), .wb_cyc_i(cyc),
        .wb_ack_o(ack), .wb_err_o(err), .int_o(int_o),
        .srx_pad_i(srx), .stx_pad_o(stx),
        .rts_pad_o(rts), .cts_pad_i(modem_q[3]),
        .dtr_pad_o(dtr), .dsr_pad_i(modem_q[2]),
        .ri_pad_i(modem_q[1]), .dcd_pad_i(modem_q[0]));

    assign pads.int_o = int_o;
    assign pads.stx   = stx;
    assign pads.srx   = srx;
    assign pads.rts   = rts;
    assign pads.dtr   = dtr;

    uart_tx_xtor      u_tx     (.clock(clock), .reset(reset), .txd(tx_line));
    uart_rx_xtor      u_rx     (.clock(clock), .reset(reset), .rxd(stx));
    uart_monitor_xtor u_mon_tx (.clock(clock), .reset(reset), .line(stx));
    uart_monitor_xtor u_mon_rx (.clock(clock), .reset(reset), .line(srx));
endmodule
