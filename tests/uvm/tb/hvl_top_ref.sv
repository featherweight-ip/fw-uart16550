// HVL top for the `ref` view: the tests run on U2B0 itself. Seats the arm's
// register-port transactor and pads in a uart_ref_model, feeds int_o to the
// model's irq seam, binds the fwvip-uart agents to the arm's serial
// transactors, publishes fwvip-core's clock and reset providers, and runs
// the test. Also publishes a uart_ref_probe for the reference confirmation
// tests: the core's internals each clock.
`include "uvm_macros.svh"
`include "fwvip_uart_macros.svh"

module hvl_top_ref;
    import uvm_pkg::*;
    import fwvip_core_uvm_pkg::*;
    import fwvip_uart_pkg::*;
    import fw_uart16550_env_pkg::*;
    import fw_uart16550_tests_pkg::*;

    hdl_top_ref hdl_top_ref();

    uart_ref_model model = new("ref");
    uart_ref_probe probe = new();

    initial begin
        model.vwb   = hdl_top_ref.u_arm.u_wb.u_if;
        model.vpads = hdl_top_ref.u_arm.pads;
        probe.vpads = hdl_top_ref.u_arm.pads;
        uvm_config_db #(uart_model_base)::set(null, "*", "model", model);
        uvm_config_db #(uart_ref_probe)::set(null, "*", "ref_probe", probe);
        `fwvip_uart_tx_register(hdl_top_ref.u_arm.u_tx.u_if, "uvm_test_top.env.m_tx*")
        `fwvip_uart_rx_register(hdl_top_ref.u_arm.u_rx.u_if, "uvm_test_top.env.m_rx*")
        `fwvip_uart_mon_register(hdl_top_ref.u_arm.u_mon_tx.u_if, "uvm_test_top.env.m_mon_tx*", 1'b1)
        `fwvip_uart_mon_register(hdl_top_ref.u_arm.u_mon_rx.u_if, "uvm_test_top.env.m_mon_rx*", 1'b0)
        fwvip_clock_config_p #(virtual fwvip_clock_xtor_if)::set(
            null, "uvm_test_top.env*", "clock", hdl_top_ref.u_clk_if);
        fwvip_reset_config_p #(virtual fwvip_reset_xtor_if #(1))::set(
            null, "uvm_test_top.env*", "reset", hdl_top_ref.u_rst_if);
        run_test();
    end

    always @(hdl_top_ref.u_arm.int_o) model.irq_changed(hdl_top_ref.u_arm.int_o);

    always @(posedge hdl_top_ref.clock) begin
        uart_ref_sample_s s;
        s.we         = hdl_top_ref.u_dut.u_core.regs.wb_we_i;
        s.re         = hdl_top_ref.u_dut.u_core.regs.wb_re_i;
        s.addr       = hdl_top_ref.u_dut.u_core.regs.wb_addr_i;
        s.enable     = hdl_top_ref.u_dut.u_core.regs.enable;
        s.rf_count   = hdl_top_ref.u_dut.u_core.regs.rf_count;
        s.tf_count   = hdl_top_ref.u_dut.u_core.regs.tf_count;
        s.rf_push    = hdl_top_ref.u_dut.u_core.regs.rf_push_pulse;
        s.rf_pop     = hdl_top_ref.u_dut.u_core.regs.rf_pop;
        s.tf_push    = hdl_top_ref.u_dut.u_core.regs.tf_push;
        s.tf_pop     = hdl_top_ref.u_dut.u_core.regs.transmitter.tf_pop;
        s.rf_error_bit = hdl_top_ref.u_dut.u_core.regs.rf_error_bit;
        s.lsr        = hdl_top_ref.u_dut.u_core.regs.lsr;
        s.iir        = hdl_top_ref.u_dut.u_core.regs.iir;
        s.block_cnt  = hdl_top_ref.u_dut.u_core.regs.block_cnt;
        s.rda_int    = hdl_top_ref.u_dut.u_core.regs.rda_int;
        s.rls_pnd    = hdl_top_ref.u_dut.u_core.regs.rls_int_pnd;
        s.rda_pnd    = hdl_top_ref.u_dut.u_core.regs.rda_int_pnd;
        s.thre_pnd   = hdl_top_ref.u_dut.u_core.regs.thre_int_pnd;
        s.ms_pnd     = hdl_top_ref.u_dut.u_core.regs.ms_int_pnd;
        s.ti_pnd     = hdl_top_ref.u_dut.u_core.regs.ti_int_pnd;
        s.int_o      = hdl_top_ref.u_dut.u_core.regs.int_o;
        s.rstate     = hdl_top_ref.u_dut.u_core.regs.rstate;
        s.rcounter16 = hdl_top_ref.u_dut.u_core.regs.receiver.rcounter16;
        s.tstate     = hdl_top_ref.u_dut.u_core.regs.tstate;
        s.serial_in  = hdl_top_ref.u_dut.u_core.regs.serial_in;
        s.dlc        = hdl_top_ref.u_dut.u_core.regs.dlc;
        probe.tick(s);
    end

    initial begin
        #200ms;
        $fatal(1, "[hvl_top_ref] TIMEOUT");
    end
endmodule
