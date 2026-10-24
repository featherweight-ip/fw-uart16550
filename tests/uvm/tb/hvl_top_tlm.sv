// HVL top for the `tlm` view: the common tests on the fw-uart16550 class
// model, called through its method ports (fw_uart16550_tlm_view_pkg).
`include "uvm_macros.svh"

module hvl_top_tlm;
    import uvm_pkg::*;
    import fwvip_core_uvm_pkg::*;
    import fw_uart16550_env_pkg::*;
    import fw_uart16550_tests_pkg::*;
    import fw_uart16550_tlm_view_pkg::*;

    hdl_top_tlm hdl_top_tlm();

    uart_tlm_model model = new("tlm");

    initial begin
        model.vclk = hdl_top_tlm.u_clk;
        uvm_config_db #(uart_model_base)::set(null, "*", "model", model);
        model.register_vip("uvm_test_top.env");
        fwvip_clock_config_p #(virtual fwvip_clock_xtor_if)::set(
            null, "uvm_test_top.env*", "clock", hdl_top_tlm.u_clk_if);
        fwvip_reset_config_p #(virtual fwvip_reset_xtor_if #(1))::set(
            null, "uvm_test_top.env*", "reset", hdl_top_tlm.u_rst_if);
        run_test();
    end

    initial begin
        #200ms;
        $fatal(1, "[hvl_top_tlm] TIMEOUT");
    end
endmodule
