// ----------------------------------------------------------------------------
// oc_uart16550_wb32 -- 32-bit WISHBONE shim around the OpenCores uart16550
// core (U2B0: freecores/uart16550 2b0ad80, from featherweight-ip/oc-uart16550).
//
// Compile with +define+DATA_BUS_WIDTH_8: the core is used in its 8-bit bus
// configuration (3-bit address, one register per byte address, no debug
// registers). The fw-XXX convention for WISHBONE IP is a 32-bit data bus
// with one register per 32-bit word, even when only the low byte is valid,
// so this shim:
//
// - maps register n to byte address 4*n: the core sees wb_adr_i[4:2], and
//   wb_adr_i[1:0] are ignored (the same layout as Linux 8250_of with
//   reg-shift = 2, reg-io-width = 4);
// - returns {24'b0, register} on reads and takes the register value from
//   wb_dat_i[7:0] on writes;
// - ignores wb_sel_i (it is passed through, and the 8-bit core leaves it
//   unconnected internally). Unlike oc_i2c_wb32, a write without byte lane 0 is
//   not turned into a read: RBR, IIR, LSR and MSR reads have side effects,
//   so a converted write could pop the RX FIFO or clear status. A driver
//   with reg-io-width = 4 always selects all lanes;
// - passes wb_rst_i (the core's asynchronous, active-high reset), the
//   core's own WISHBONE timing (registered inputs, ack two cycles later),
//   int_o, the serial pads and the modem pads straight through, and drives
//   wb_err_o low.
//
// No logic is added: everything is wiring and zero extension
// (scripts/synth-baseline.sh checks that the shim costs 0 LUT4).
// ----------------------------------------------------------------------------
module oc_uart16550_wb32 (
        input  wire        wb_clk_i,
        input  wire        wb_rst_i,

        input  wire [4:0]  wb_adr_i,     // byte address; [1:0] ignored
        input  wire [31:0] wb_dat_i,
        output wire [31:0] wb_dat_o,
        input  wire [3:0]  wb_sel_i,     // ignored (see above)
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

`ifndef DATA_BUS_WIDTH_8
    // The shim needs the core's 8-bit bus: fail elaboration otherwise.
    oc_uart16550_wb32_requires_DATA_BUS_WIDTH_8 u_config_error ();
`endif

    wire [7:0] dat8_o;

    uart_top u_core (
        .wb_clk_i  (wb_clk_i),
        .wb_rst_i  (wb_rst_i),
        .wb_adr_i  (wb_adr_i[4:2]),
        .wb_dat_i  (wb_dat_i[7:0]),
        .wb_dat_o  (dat8_o),
        .wb_we_i   (wb_we_i),
        .wb_stb_i  (wb_stb_i),
        .wb_cyc_i  (wb_cyc_i),
        .wb_sel_i  (wb_sel_i),       // unused by the 8-bit core
        .wb_ack_o  (wb_ack_o),
        .int_o     (int_o),
        .srx_pad_i (srx_pad_i),
        .stx_pad_o (stx_pad_o),
        .rts_pad_o (rts_pad_o),
        .cts_pad_i (cts_pad_i),
        .dtr_pad_o (dtr_pad_o),
        .dsr_pad_i (dsr_pad_i),
        .ri_pad_i  (ri_pad_i),
        .dcd_pad_i (dcd_pad_i)
    );

    assign wb_dat_o = {24'b0, dat8_o};
    assign wb_err_o = 1'b0;

endmodule
