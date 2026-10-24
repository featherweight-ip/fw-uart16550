// Smoke: 8N1 at divisor 2. Eight characters into the DUT, read back from
// RBR with DR set and clear as expected; eight characters written to THR,
// received by the VIP; THRE and TEMT set at the end.
class fw_uart16550_smoke_test extends fw_uart16550_base_test;
    `uvm_component_utils(fw_uart16550_smoke_test)

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task body();
        bit [7:0] d[] = '{8'h55, 8'haa, 8'h00, 8'hff, 8'h01, 8'h80, 8'h3c, 8'hc3};
        init();
        expect_reg("LSR after init", LSR, 8'h60);

        // VIP -> DUT
        tx_send(d);
        tx_idle(2);
        expect_reg("LSR with data", LSR, 8'h61);
        foreach (d[i]) expect_reg($sformatf("RBR %0d", i), RBR, d[i]);
        expect_reg("LSR after reading", LSR, 8'h60);

        // DUT -> VIP
        foreach (d[i]) reg_write(THR, d[i]);
        expect_rx("THR", d);
        clocks(2 * char_clocks());
        expect_reg("LSR at the end", LSR, 8'h60);
        check(env.m_mon_tx.n_chars == d.size(),
              $sformatf("monitor on stx saw %0d characters", env.m_mon_tx.n_chars));
    endtask
endclass
