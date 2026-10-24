// HDL top for the `wb` and `rtl` views: fw-uart16550 (fw_uart16550_top, the
// class model behind pins, or its lowered netlist) in the bench arm,
// with clock and reset, and fwvip-core's clock and reset transactor
// interfaces for the UART VIP.
module hdl_top_wb;
    logic clock = 1'b0;
    logic reset = 1'b1;
    always #5ns clock = ~clock;          // 100 MHz
    initial begin
        repeat (4) @(posedge clock);
        reset = 1'b0;
    end

    fwvip_clock_xtor_if               u_clk_if (.clock(clock), .reset(reset));
    fwvip_reset_xtor_if #(.ACTIVE(1)) u_rst_if (.clock(clock), .reset(reset));

    wire [4:0]  adr;
    wire [31:0] dat_w, dat_r;
    wire        we, stb, cyc, ack, err, int_o, srx, stx, rts, dtr;
    wire [3:0]  modem;      // {cts, dsr, ri, dcd}

    uart16550_arm u_arm (
        .clock(clock), .reset(reset),
        .dut_adr(adr), .dut_dat_w(dat_w), .dut_dat_r(dat_r), .dut_we(we),
        .dut_stb(stb), .dut_cyc(cyc), .dut_ack(ack), .dut_err(err), .dut_int(int_o),
        .dut_srx(srx), .dut_stx(stx), .dut_rts(rts), .dut_dtr(dtr), .dut_modem(modem));

    fw_uart16550_top u_dut (
        .wb_clk_i(clock), .wb_rst_i(reset),
        .wb_adr_i(adr), .wb_dat_i(dat_w), .wb_dat_o(dat_r),
        .wb_sel_i(4'hF), .wb_we_i(we), .wb_stb_i(stb), .wb_cyc_i(cyc),
        .wb_ack_o(ack), .wb_err_o(err), .int_o(int_o),
        .srx_pad_i(srx), .stx_pad_o(stx),
        .rts_pad_o(rts), .cts_pad_i(modem[3]),
        .dtr_pad_o(dtr), .dsr_pad_i(modem[2]),
        .ri_pad_i(modem[1]), .dcd_pad_i(modem[0]));
endmodule
