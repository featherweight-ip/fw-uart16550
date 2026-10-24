// The transmitter: U6, U11, U15, U26.
//
//   U6, U11  a THR write with THRE = 1 holds THRE (and TEMT) off for
//            16 x (character bits - one stop bit) ticks, whatever else
//            happens: measured from the push to THRE for six framings
//   U15      a write to a full TX FIFO (16 waiting) replaces the next byte
//            to send; the count stays 16
//   U26      a TX FIFO reset after the transmitter has decided to send
//            (s_pop_byte) and before it loads the byte: it sends the stale
//            byte at entry 0. A THR write whose push meets that pop is
//            lost (swept over the write's timing; found from the probe)
class fw_uart16550_ref_tx_test extends fw_uart16550_ref_base_test;
    `uvm_component_utils(fw_uart16550_ref_tx_test)

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task body();
        fwvip_uart_cfg_item c = fwvip_uart_cfg_item::type_id::create("c");
        fork track(); join_none
        u6(c);
        u15(c);
        u26(c);
    endtask

    // Ticks from a THR push to THRE.
    task thre_ticks(output int unsigned n);
        longint unsigned c0 = probe.n_clk;
        int unsigned     w = 0;
        reg_write(THR, 8'h5A);
        while (!(last_thre_rise_clk > last_tf_push_clk && last_tf_push_clk > c0) && w < 100000) begin
            @(probe.clk_ev);
            w++;
        end
        check(w < 100000, "THRE did not rise after the THR write");
        n = int'(last_thre_rise_ticks - last_tf_push_ticks);
    endtask

    task u6(fwvip_uart_cfg_item c);
        // {divisor, word bits, parity, stop}
        int unsigned f[6][4] = '{'{1, 8, 0, 0}, '{1, 5, 0, 0}, '{1, 5, 0, 1},
                                 '{2, 7, 1, 0}, '{1, 8, 1, 1}, '{3, 6, 1, 1}};
        int unsigned e0 = errors;
        foreach (f[i]) begin
            int unsigned n, exp;
            fwvip_uart_char t;
            init(c.set(16'(f[i][0]), 4'(f[i][1]), f[i][2][0], 1'b1, 1'b0, 2'(f[i][3])));
            // 16 x (character - one stop bit): the RTL's block_value + 1.
            // THRE sets in the clock after the count reaches 0, which is a
            // tick too at divisor 1, so the ticks counted are block_value or
            // block_value + 1 by the divisor.
            exp = 16 * (2 * c.frame_bits() + c.stop_halves() - 2) / 2;
            thre_ticks(n);
            note("U6", $sformatf("%s: THRE %0d ticks after the push (character %0d ticks)",
                                 c.convert2string(), n, 16 * (2 * c.frame_bits() + c.stop_halves()) / 2));
            check(n + 1 >= exp && n <= exp, $sformatf("U6 %s: THRE after %0d ticks, expected %0d", c.convert2string(), n, exp));
            rx_get(t);
            check(t != null && t.data == (8'h5A & c.mask()), $sformatf("U6 %s: character not sent", c.convert2string()));
            clocks(2 * c.char_clocks());
        end
        if (errors == e0) begin
            confirmed("U6", "THRE held off 16 x (character - one stop bit) ticks after a THR write with THRE = 1");
            confirmed("U11", "the ref view's THRE timing after a single write is the U6 hold-off and nothing else");
        end
    endtask

    task u15(fwvip_uart_cfg_item c);
        bit [7:0] w[18];
        int unsigned e0 = errors;
        init(c.set(16));                              // 17 writes well inside one character
        foreach (w[i]) w[i] = 8'(8'hC0 + i);
        for (int i = 0; i < 17; i++) reg_write(THR, w[i]);
        clocks(2);                                    // the probe lags the push by a clock
        check(probe.cur.tf_count == 16, $sformatf("U15: TX count %0d with w0 in the shift register", probe.cur.tf_count));
        reg_write(THR, w[17]);
        clocks(2);
        check(probe.cur.tf_count == 16, $sformatf("U15: TX count %0d after the 18th write", probe.cur.tf_count));
        // Sent: w0, then w17 in place of w1, then w2..w16.
        begin
            bit [7:0] exp[$];
            exp.push_back(w[0]);
            exp.push_back(w[17]);
            for (int i = 2; i < 17; i++) exp.push_back(w[i]);
            expect_rx("U15", exp);
        end
        if (errors == e0) confirmed("U15", "a THR write to a full TX FIFO overwrites the next byte to send");
    endtask

    task u26(fwvip_uart_cfg_item c);
        fwvip_uart_char t;
        int unsigned    e0 = errors;
        // Part 1: the stale byte. Send Z (entry 0), let it go; write A
        // (entry 1); reset the TX FIFO after the transmitter has decided.
        init(c.set(32));                              // a tick every 32 clocks
        reg_write(THR, 8'h3E);                        // Z
        rx_get(t);
        check(t != null && t.data == 8'h3E, "U26: first byte not sent");
        clocks(4 * c.bit_clocks());
        reg_write(THR, 8'hA7);                        // A, at entry 1
        wait_tstate(S_POP_BYTE);
        reg_write(FCR, 8'h04);                        // TX FIFO reset
        rx_get(t);
        note("U26", $sformatf("TX FIFO reset in s_pop_byte: sent 0x%02h", (t == null) ? 8'hXX : t.data));
        check(t != null && t.data == 8'h3E, "U26: the stale byte at entry 0 (0x3E) was not the one sent");
        clocks(4 * c.bit_clocks());

        // Part 2: a THR write whose push meets that pop is never sent.
        begin
            int unsigned n_hit = 0;
            string       ks = "";
            for (int unsigned k = 0; k < 32; k++) begin
                longint unsigned c0;
                reg_write(FCR, 8'h06);
                reg_write(THR, 8'hA7);
                wait_tstate(S_POP_BYTE);
                reg_write(FCR, 8'h04);
                c0 = n_tx_coinc;
                clocks(k);
                reg_write(THR, 8'hB8);
                rx_get(t);                            // the stale byte
                rx_get(t, 3 * c.char_clocks());       // B, unless lost
                if (n_tx_coinc != c0) begin
                    n_hit++;
                    ks = {ks, $sformatf(" %0d", k)};
                    check(t == null, $sformatf("U26 k=%0d: the byte written in the pop clock was sent", k));
                    check(probe.cur.tf_count == 0, $sformatf("U26 k=%0d: TX count %0d", k, probe.cur.tf_count));
                end
                env.m_rx.clear();
                clocks(2 * c.char_clocks());
            end
            note("U26", $sformatf("THR push in the pop clock at k =%s", ks));
            check(n_hit != 0, "U26: no THR push met the pop; widen the sweep");
            if (errors == e0 && n_hit != 0)
                confirmed("U26", "TX FIFO reset in s_pop_byte sends the stale entry-0 byte; a push in the pop clock is lost");
        end
    endtask
endclass
