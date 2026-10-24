// The design under test, as the bench sees it, whatever the view (the U2B0
// reference, and later fw-uart16550 at TLM, behind transactors, or as RTL).
// As fw-i2c's i2c_model_base: the env, the operation model (step 5) and the
// tests depend on this surface only. The serial pins are not here: the env's
// fwvip-uart agents are bound to the view's transactors by the top.
//
//   rf_if()       the register port: one access() per WISHBONE cycle
//   set_modem()   the modem input pads {cts, dsr, ri, dcd}
//   modem_out()   the modem output pads {rts, dtr}
//   irq seam      irq_changed() from the view's producer; the bench waits
//                 only on wait_irq_change()
virtual class uart_model_base;
    string name;

    bit   m_irq_level;
    event m_irq_ev;

    function new(string name);
        this.name = name;
    endfunction

    pure virtual function wb_proto_if #(32, 32) rf_if();

    // Start whatever runs in the background. Called by the env first.
    virtual task start(); endtask

    pure virtual task set_modem(bit [3:0] cts_dsr_ri_dcd);
    pure virtual function bit [1:0] modem_out();

    // ---- interrupt seam ----

    // The interrupt pin changed: called by the HDL top on int_o.
    virtual function void irq_changed(bit level);
        if (level === m_irq_level) return;
        m_irq_level = level;
        -> m_irq_ev;
    endfunction
    task wait_irq_change(); @m_irq_ev; endtask           // until int_o changes
    virtual function bit irq_level(); return m_irq_level; endfunction   // int_o now
endclass
