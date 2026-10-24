// The receiver: U4, U12. srx is driven by the test, clock by clock.
//
//   U4   one sample per bit: a one-clock pulse inside a data bit (divisor 1:
//        a tick every clock, 16 clocks a bit) flips that bit at exactly one
//        position in the bit and nowhere else. A majority vote would need
//        two of three samples. Also: the shortest low pulse on an idle line
//        that starts a character
//   U12  break: after one character time low, one character with data 0
//        and BI alone (no FE, no PE). A framing-error character followed at
//        once by a line held low long enough to be a break is lost; held
//        low for less than that, it is pushed with FE
class fw_uart16550_ref_rx_test extends fw_uart16550_ref_base_test;
    `uvm_component_utils(fw_uart16550_ref_rx_test)

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task body();
        fwvip_uart_cfg_item c = fwvip_uart_cfg_item::type_id::create("c");
        // The srx monitor sees what the test drives, glitches and breaks
        // included.
        env.m_mon_rx.check_enable = 0;
        u4(c);
        u12(c);
    endtask

    task u4(fwvip_uart_cfg_item c);
        int unsigned e0 = errors, n_flip = 0, at = 0, min_start = 0;
        string       ps = "";
        init(c.set(1));                               // 8N1/1
        srx_take(1'b1);
        for (int unsigned p = 0; p < 16; p++) begin
            bit [7:0] d;
            srx_hold(1'b1, 40);
            // Start bit, then data bit 0 low with a one-clock high pulse at
            // clock p of the bit, the other data bits low, stop.
            srx_hold(1'b0, 16);
            srx_hold(1'b0, p);
            srx_hold(1'b1, 1);
            srx_hold(1'b0, 15 - p);
            srx_hold(1'b0, 7 * 16);
            srx_hold(1'b1, 16);
            srx_hold(1'b1, 8);
            check(probe.cur.rf_count == 1, $sformatf("U4 p=%0d: count %0d", p, probe.cur.rf_count));
            reg_read(RBR, d);
            check(d[7:1] == 0, $sformatf("U4 p=%0d: received 0x%02h", p, d));
            if (d[0]) begin
                n_flip++;
                at = p;
                ps = {ps, $sformatf(" %0d", p)};
            end
        end
        note("U4", $sformatf("a one-clock pulse in a bit is sampled at clock(s)%s of 16 (from the bit's edge as driven)", ps));
        check(n_flip == 1, $sformatf("U4: %0d pulse positions flip the bit, expected exactly 1", n_flip));

        // The shortest low pulse on an idle line that starts a character.
        for (int unsigned len = 1; len <= 16 && min_start == 0; len++) begin
            srx_hold(1'b1, 40);
            srx_hold(1'b0, len);
            srx_hold(1'b1, 12 * 16);
            if (probe.cur.rf_count != 0) begin
                bit [7:0] d;
                min_start = len;
                reg_read(RBR, d);
            end
        end
        note("U4", $sformatf("shortest low pulse that starts a character: %0d clocks (of 16)", min_start));
        check(min_start > 1 && min_start <= at + 2, $sformatf("U4: a %0d-clock pulse starts a character", min_start));
        srx_give();
        if (errors == e0) confirmed("U4", $sformatf("one sample per bit, at clock %0d of 16 after the driven edge; no majority vote", at));
    endtask

    task u12(fwvip_uart_cfg_item c);
        int unsigned e0 = errors;
        bit [7:0]    lsr;
        init(c.set(2));                               // 8N1/2: 32 clocks a bit, 320 a character

        // (a) A character, then a break from the tx agent.
        tx_send('{8'h41});
        tx_break(2);
        tx_idle(2);
        check(probe.cur.rf_count == 2, $sformatf("U12a: count %0d after a character and a break", probe.cur.rf_count));
        expect_reg("U12a RBR: the character", RBR, 8'h41);
        reg_read(LSR, lsr);
        check(lsr[4] && !lsr[3] && !lsr[2], $sformatf("U12a: LSR 0x%02h with the break at the head: want BI, no FE, no PE", lsr));
        expect_reg("U12a RBR: the break character", RBR, 8'h00);

        // (b) A framing-error character, then low for two character times.
        srx_take(1'b1);
        srx_hold(1'b1, 64);
        srx_frame(8'h81, 1'b0);                       // stop bit space: FE
        srx_hold(1'b0, 2 * c.char_clocks());
        srx_hold(1'b1, 2 * c.char_clocks());
        check(probe.cur.rf_count == 1, $sformatf("U12b: count %0d, expected only the break character", probe.cur.rf_count));
        reg_read(LSR, lsr);
        check(lsr[4] && !lsr[3], $sformatf("U12b: LSR 0x%02h: want BI, no FE", lsr));
        expect_reg("U12b RBR: the break character", RBR, 8'h00);

        // (c) The same character, low for four more bits only: pushed with FE.
        srx_frame(8'h81, 1'b0);
        srx_hold(1'b0, 4 * c.bit_clocks());
        srx_hold(1'b1, 2 * c.char_clocks());
        check(probe.cur.rf_count == 1, $sformatf("U12c: count %0d", probe.cur.rf_count));
        reg_read(LSR, lsr);
        check(lsr[3] && !lsr[4], $sformatf("U12c: LSR 0x%02h: want FE, no BI", lsr));
        expect_reg("U12c RBR: the FE character", RBR, 8'h81);
        srx_give();
        if (errors == e0)
            confirmed("U12", "break: one zero character with BI alone after a character time low; an FE character just before a break is lost");
    endtask
endclass
