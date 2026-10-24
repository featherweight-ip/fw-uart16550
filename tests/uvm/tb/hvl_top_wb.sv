// HVL top for the `wb` and `rtl` views: the common tests on fw-uart16550
// behind pins. As hvl_top_ref, without the reference probe.
`include "uvm_macros.svh"
`include "fwvip_uart_macros.svh"

module hvl_top_wb;
    import uvm_pkg::*;
    import fwvip_core_uvm_pkg::*;
    import fwvip_uart_pkg::*;
    import fw_uart16550_env_pkg::*;
    import fw_uart16550_tests_pkg::*;

    hdl_top_wb hdl_top_wb();

    uart_ref_model model = new("wb");

    initial begin
        model.vwb   = hdl_top_wb.u_arm.u_wb.u_if;
        model.vpads = hdl_top_wb.u_arm.pads;
        uvm_config_db #(uart_model_base)::set(null, "*", "model", model);
        `fwvip_uart_tx_register(hdl_top_wb.u_arm.u_tx.u_if, "uvm_test_top.env.m_tx*")
        `fwvip_uart_rx_register(hdl_top_wb.u_arm.u_rx.u_if, "uvm_test_top.env.m_rx*")
        `fwvip_uart_mon_register(hdl_top_wb.u_arm.u_mon_tx.u_if, "uvm_test_top.env.m_mon_tx*", 1'b1)
        `fwvip_uart_mon_register(hdl_top_wb.u_arm.u_mon_rx.u_if, "uvm_test_top.env.m_mon_rx*", 1'b0)
        fwvip_clock_config_p #(virtual fwvip_clock_xtor_if)::set(
            null, "uvm_test_top.env*", "clock", hdl_top_wb.u_clk_if);
        fwvip_reset_config_p #(virtual fwvip_reset_xtor_if #(1))::set(
            null, "uvm_test_top.env*", "reset", hdl_top_wb.u_rst_if);
        run_test();
    end

    always @(hdl_top_wb.u_arm.int_o) model.irq_changed(hdl_top_wb.u_arm.int_o);

    initial begin
        #200ms;
        $fatal(1, "[hvl_top_wb] TIMEOUT");
    end
endmodule
