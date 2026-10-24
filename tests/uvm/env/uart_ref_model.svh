// The U2B0 reference (OpenCores uart16550 through the 32-bit WISHBONE shim),
// behind transactors: tests/uvm/tb/oc_uart16550_ref_arm.sv. The top seats
// the register-port transactor interface and the pads interface, and drives
// irq_changed() from int_o.
class uart_ref_model extends uart_model_base;
    virtual wb_initiator_xtor_if #(32, 32) vwb;
    virtual uart_ref_pads_if               vpads;

    protected wb_initiator_xtor_bridge #(32, 32) m_wb;

    function new(string name = "ref");
        super.new(name);
    endfunction

    virtual function wb_proto_if #(32, 32) rf_if();
        if (m_wb == null) begin
            if (vwb == null) `uvm_fatal("REFMODEL", "vwb not seated")
            m_wb = new(vwb);
        end
        return m_wb;
    endfunction

    virtual task set_modem(bit [3:0] cts_dsr_ri_dcd);
        {vpads.cts, vpads.dsr, vpads.ri, vpads.dcd} = cts_dsr_ri_dcd;
    endtask

    virtual function bit [1:0] modem_out();
        return {vpads.rts, vpads.dtr};
    endfunction
endclass
