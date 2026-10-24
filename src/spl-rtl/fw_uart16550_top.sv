// fw-uart16550 behind pins, elaborated through fw_root: the form that both
// simulates (the `wb` view) and lowers to RTL (`lowered`, the same module
// name and pins; the `rtl` view). The pins are those of the U2B0 shim
// oc_uart16550_wb32, so the same bench applies.
//
//   u_wb    fw-proto-wb target transactor: the register port
//   u_baud  the kit baud tick core, one for both directions (K2)
//   u_tx    the kit transmit core
//   u_rx    the kit receive core, behind u_sync (srx, two flops)
//   u_if    fw_uart16550_xtor_if: the class side of all of the above, the
//           modem pads, MCR's outputs and the interrupt
//
// Loopback (MCR.LOOP): the transmitter drives the receiver, stx_pad_o is
// mark, and RTS and DTR still drive their pads (U8).
//
// Lowering reads this file as the design: fw_root's reset-release
// elaboration is interpreted, every thread it starts becomes a process, and
// the modules without a class-bound interface (the kit cores and the
// synchronizer) stay as instances.
module fw_uart16550_top (
        input  wire        wb_clk_i,
        input  wire        wb_rst_i,

        input  wire [4:0]  wb_adr_i,     // byte address; [1:0] ignored
        input  wire [31:0] wb_dat_i,
        output wire [31:0] wb_dat_o,
        input  wire [3:0]  wb_sel_i,     // ignored, as the shim
        input  wire        wb_we_i,
        input  wire        wb_stb_i,
        input  wire        wb_cyc_i,
        output wire        wb_ack_o,
        output wire        wb_err_o,
        output wire        int_o,

        input  wire        srx_pad_i,
        output wire        stx_pad_o,
        output wire        rts_pad_o,
        input  wire        cts_pad_i,
        output wire        dtr_pad_o,
        input  wire        dsr_pad_i,
        input  wire        ri_pad_i,
        input  wire        dcd_pad_i
    );
    import fw_hdl_pkg::*;
    import fw_proto_wb_pkg::*;
    import fw_proto_uart_pkg::*;
    import fw_uart16550_spl_pkg::*;
    import fw_uart16550_spl_rtl_pkg::*;

    wb_target_xtor #(.ADDR_WIDTH(32), .DATA_WIDTH(32)) u_wb (
        .clock(wb_clk_i), .reset(wb_rst_i),
        .adr({27'b0, wb_adr_i}), .dat_w(wb_dat_i), .dat_r(wb_dat_o), .cyc(wb_cyc_i),
        .err(wb_err_o), .sel(wb_sel_i), .stb(wb_stb_i), .ack(wb_ack_o), .we(wb_we_i));

    wire [7:0]  req_dat;
    wire        req_valid, req_ready, busy, brk;
    wire [11:0] rsp_dat;
    wire        rsp_valid, rsp_ready;
    wire [15:0] cfg_divisor;
    wire [3:0]  cfg_word_bits;
    wire        cfg_parity_en, cfg_parity_even, cfg_parity_stick;
    wire [1:0]  cfg_stop_bits;
    wire        tick;
    wire [4:0]  mcr;                // {LOOP, OUT2, OUT1, RTS, DTR}
    wire        txd, srx_s, rxd;

    fw_uart16550_xtor_if u_if (
        .clock(wb_clk_i), .reset(wb_rst_i),
        .req_dat(req_dat), .req_valid(req_valid), .req_ready(req_ready), .busy(busy), .brk(brk),
        .rsp_dat(rsp_dat), .rsp_valid(rsp_valid), .rsp_ready(rsp_ready),
        .cfg_divisor(cfg_divisor), .cfg_word_bits(cfg_word_bits),
        .cfg_parity_en(cfg_parity_en), .cfg_parity_even(cfg_parity_even),
        .cfg_parity_stick(cfg_parity_stick), .cfg_stop_bits(cfg_stop_bits),
        .tick(tick), .mcr(mcr), .irq(int_o),
        .modem({dcd_pad_i, ri_pad_i, dsr_pad_i, cts_pad_i}));

    uart_baud_xtor_core #(.DIV_WIDTH(16)) u_baud (
        .clock(wb_clk_i), .reset(wb_rst_i), .cfg_divisor(cfg_divisor), .tick(tick));

    uart_tx_xtor_core #(.MAX_DATA_BITS(8), .OVERSAMPLE(16)) u_tx (
        .clock(wb_clk_i), .reset(wb_rst_i), .tick(tick),
        .txd(txd), .brk(brk), .busy(busy),
        .cfg_word_bits(cfg_word_bits), .cfg_parity_en(cfg_parity_en),
        .cfg_parity_even(cfg_parity_even), .cfg_parity_stick(cfg_parity_stick),
        .cfg_stop_bits(cfg_stop_bits),
        .req_dat(req_dat), .req_valid(req_valid), .req_ready(req_ready));

    fw_uart16550_sync u_sync (.clock(wb_clk_i), .reset(wb_rst_i), .d(srx_pad_i), .q(srx_s));

    assign rxd       = mcr[4] ? txd : srx_s;
    assign stx_pad_o = mcr[4] ? 1'b1 : txd;
    assign rts_pad_o = mcr[1];
    assign dtr_pad_o = mcr[0];

    uart_rx_xtor_core #(.MAX_DATA_BITS(8), .OVERSAMPLE(16)) u_rx (
        .clock(wb_clk_i), .reset(wb_rst_i), .tick(tick),
        .rxd(rxd),
        .cfg_word_bits(cfg_word_bits), .cfg_parity_en(cfg_parity_en),
        .cfg_parity_even(cfg_parity_even), .cfg_parity_stick(cfg_parity_stick),
        .rsp_dat(rsp_dat), .rsp_valid(rsp_valid), .rsp_ready(rsp_ready));

    // The root: fw_uart16550_pin_top with its interface handle set before
    // build(), and the register-port and receive threads started as
    // runnables.
    class fw_uart16550_top_bind extends fw_component_root #(fw_uart16550_pin_top);
        function new(string name); super.new(name); endfunction

        virtual function void build();
            vif = u_if;
            super.build();
        endfunction

        virtual function void connect();
            wb_target_xtor_bridge #(32, 32) wb;
            fw_uart16550_wb_runner          wb_run;
            fw_uart16550_rx_runner          rx_run;
            super.connect();
            wb     = new(u_wb.u_if, dut.host);
            wb_run = new(wb);
            rx_run = new(u_if, dut.rx_sink);
            add_runnable(wb_run);
            add_runnable(rx_run);
        endfunction
    endclass

    fw_root #(.Tbind(fw_uart16550_top_bind)) u_root (.clock(wb_clk_i), .reset(wb_rst_i));
endmodule
