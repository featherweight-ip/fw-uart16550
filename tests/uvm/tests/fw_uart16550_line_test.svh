// Line formats and loopback (every view). Each framing (5 to 8 bits; no,
// odd, even and stick parity; 1 and 2 stop bits) at divisors 1 to 3: two
// characters each way. Then loopback: the transmitter feeds the receiver,
// stx_pad_o holds mark, and MSR[7:4] reads MCR's outputs.
class fw_uart16550_line_test extends fw_uart16550_base_test;
    `uvm_component_utils(fw_uart16550_line_test)

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task one(bit [15:0] div, bit [3:0] wb, bit pen, bit eps, bit sp, bit [1:0] stb);
        fwvip_uart_cfg_item c = fwvip_uart_cfg_item::type_id::create("c");
        bit [7:0] d[] = '{8'hA5, 8'h3C};
        string    what = $sformatf("div %0d %0d%s%0d", div, wb,
                                   !pen ? "N" : sp ? (eps ? "S0" : "S1") : (eps ? "E" : "O"),
                                   stb + 1);
        init(c.set(div, wb, pen, eps, sp, stb));
        tx_send(d);
        tx_idle(2);
        foreach (d[i]) expect_reg({what, $sformatf(" RBR %0d", i)}, RBR, d[i] & line().mask());
        expect_reg({what, " LSR"}, LSR, 8'h60);
        foreach (d[i]) reg_write(THR, d[i]);
        expect_rx(what, d);
        clocks(2 * char_clocks());
    endtask

    task body();
        bit [7:0] d[] = '{8'h11, 8'h22, 8'h33};
        int unsigned n_mon;

        for (int div = 1; div <= 3; div++)
            for (int wb = 5; wb <= 8; wb++)
                for (int par = 0; par < 5; par++)        // N, O, E, S1, S0
                    for (int stb = 0; stb < 2; stb++) begin
                        if (div != 2 && (par > 2 || wb == 6 || wb == 7)) continue;
                        one(16'(div), 4'(wb), par != 0, par == 2 || par == 4, par >= 3, 2'(stb));
                    end

        // Loopback.
        init();
        n_mon = env.m_mon_tx.n_chars;
        reg_write(MCR, 8'h1F);
        foreach (d[i]) reg_write(THR, d[i]);
        clocks(5 * char_clocks());
        foreach (d[i]) expect_reg($sformatf("loopback RBR %0d", i), RBR, d[i]);
        check(env.m_mon_tx.n_chars == n_mon,
              $sformatf("loopback: %0d characters on stx", env.m_mon_tx.n_chars - n_mon));
        expect_reg("loopback MSR[7:4] = {OUT2, OUT1, DTR, RTS}", MSR, 8'hF0, 8'hF0);
        reg_write(MCR, 8'h15);                     // OUT1, DTR
        expect_reg("loopback MSR[7:4], OUT1 and DTR", MSR, 8'h60, 8'hF0);
        reg_write(MCR, 8'h00);
        expect_reg("MSR[7:4] after loopback", MSR, 8'h00, 8'hF0);
        // Out of loopback the line works again.
        reg_write(THR, 8'h5A);
        expect_rx("after loopback", '{8'h5A});
    endtask
endclass
