// Throughput (every view; docs/results.md, "Simulation performance"). 8N1
// at divisor 1, +blocks=N blocks (default 16) of 16 characters: into the
// DUT and read back from RBR, then written to THR and received by the VIP.
// Long enough that simulation, not UVM start-up, sets its wall time.
class fw_uart16550_stream_test extends fw_uart16550_base_test;
    `uvm_component_utils(fw_uart16550_stream_test)

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task body();
        fwvip_uart_cfg_item c = fwvip_uart_cfg_item::type_id::create("c");
        int unsigned blocks = 16;
        bit [7:0] d[] = new[16];
        void'($value$plusargs("blocks=%d", blocks));
        init(c.set(1));
        for (int unsigned b = 0; b < blocks; b++) begin
            foreach (d[i]) d[i] = 8'(b * 16 + i * 7);
            tx_send(d);
            tx_idle(2);
            foreach (d[i]) expect_reg($sformatf("block %0d RBR %0d", b, i), RBR, d[i]);
            foreach (d[i]) reg_write(THR, d[i]);
            expect_rx($sformatf("block %0d", b), d);
        end
        clocks(2 * char_clocks());
        check(env.m_mon_tx.n_chars == blocks * 16,
              $sformatf("monitor on stx saw %0d characters", env.m_mon_tx.n_chars));
    endtask
endclass
