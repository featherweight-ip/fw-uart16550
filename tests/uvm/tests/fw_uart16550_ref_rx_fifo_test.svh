// The RX FIFO: U5, U14, U18, U19, U16, U17.
//
//   U5, U14  16 characters waiting, then one more (with a parity error):
//            OE is set and the count stays 16, but the new byte overwrites
//            the head's data byte; the head keeps its own (clean) flags
//   U18      two parity errors in a row: after LSR is read and the first
//            is popped, LSR.PE is not set for the second
//   U19      LSR[7] is cleared by that read and not set again while the
//            second errored character is in the FIFO
//   U16      an RBR read of an empty FIFO whose pop lands in the clock of a
//            push: the character is lost and LSR.DR stays 1 (swept over
//            the read's timing; the clock is found from the probe)
//   U17      a pop in the clock of a push leaves the popped entry's error
//            flags in the FIFO's error bit (swept the same way)
class fw_uart16550_ref_rx_fifo_test extends fw_uart16550_ref_base_test;
    `uvm_component_utils(fw_uart16550_ref_rx_fifo_test)

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task body();
        fwvip_uart_cfg_item c = fwvip_uart_cfg_item::type_id::create("c");
        fork track(); join_none
        env.m_mon_rx.allow_status(FWVIP_UART_PE);
        u5_u14(c);
        u18_u19(c);
        u16(c);
        u17(c);
    endtask

    task u5_u14(fwvip_uart_cfg_item c);
        bit [7:0] d[16];
        int unsigned e0 = errors;
        init(c.set(2, 8, 1, 1));                      // 8E1/2
        foreach (d[i]) d[i] = 8'(8'h20 + i);
        tx_send(d);
        tx_idle(2);
        check(probe.cur.rf_count == 16, $sformatf("U5: count %0d after 16 characters", probe.cur.rf_count));
        tx_err(8'hEE, .bad_parity(1));
        tx_idle(2);
        check(probe.cur.rf_count == 16, $sformatf("U5: count %0d after the 17th", probe.cur.rf_count));
        // DR, OE, THRE, TEMT, LSR[7] (from the overrun); no PE: the head is clean.
        expect_reg("U5 LSR after the overrun", LSR, 8'hE3);
        expect_reg("U14 RBR 0: the 17th byte over the head", RBR, 8'hEE);
        expect_reg("U14 LSR: the 17th's PE is lost", LSR, 8'h61);
        for (int i = 1; i < 16; i++) expect_reg($sformatf("U5 RBR %0d", i), RBR, d[i]);
        expect_reg("U5 LSR empty", LSR, 8'h60);
        if (errors == e0) begin
            confirmed("U5", "overrun: OE set, count stays 16, the incoming character's flags are dropped");
            confirmed("U14", "overrun: the incoming byte overwrites the head character's data byte");
        end
    endtask

    task u18_u19(fwvip_uart_cfg_item c);
        int unsigned e0 = errors;
        init(c.set(2, 8, 1, 1));                      // 8E1/2
        tx_err(8'h51, .bad_parity(1));
        tx_err(8'h52, .bad_parity(1));
        tx_send('{8'h53});
        tx_idle(2);
        expect_reg("U18 LSR: first PE", LSR, 8'hE5);   // DR PE THRE TEMT [7]
        expect_reg("U18 RBR first", RBR, 8'h51);
        expect_reg("U18/U19 LSR with the second PE character at the head", LSR, 8'h61);
        expect_reg("U18 RBR second", RBR, 8'h52);
        expect_reg("U19 LSR with the clean character at the head", LSR, 8'h61);
        expect_reg("RBR third", RBR, 8'h53);
        // All errored characters gone: a new one sets LSR[7] again.
        tx_err(8'h54, .bad_parity(1));
        tx_idle(2);
        expect_reg("U19 LSR: a new error after the FIFO emptied", LSR, 8'hE5);
        expect_reg("RBR fourth", RBR, 8'h54);
        if (errors == e0) begin
            confirmed("U18", "LSR.PE is edge-set: the second of two PE characters in a row is not reported");
            confirmed("U19", "LSR[7] is cleared by the read while an errored character remains, and not set again for it");
        end
    endtask

    // One trial: a character arrives; `k` clocks after the receiver enters
    // its stop-bit state, the test reads RBR. Returns whether the read's pop
    // landed in the push clock.
    task trial(bit [7:0] first_err, bit [7:0] data, int unsigned k, output bit hit);
        longint unsigned c0;
        bit [7:0]        d;
        reg_write(FCR, 8'h06);
        clocks(4);
        if (first_err != 0) begin
            tx_err(first_err, .bad_parity(1));
            tx_idle(1);
        end
        c0 = n_rx_coinc;
        tx_send('{data});
        wait_rstate(SR_REC_STOP);
        clocks(k);
        reg_read(RBR, d);
        tx_idle(2);
        hit = (n_rx_coinc != c0);
    endtask

    task u16(fwvip_uart_cfg_item c);
        int unsigned n_hit = 0, e0 = errors;
        string       ks = "";
        init(c.set(1));                               // 8N1/1: a tick every clock
        for (int unsigned k = 0; k < 48; k++) begin
            bit       hit;
            bit [7:0] lsr;
            trial(8'h00, 8'h3C, k, hit);
            reg_read(LSR, lsr);
            if (hit) begin
                n_hit++;
                ks = {ks, $sformatf(" %0d", k)};
                check(probe.cur.rf_count == 0, $sformatf("U16 k=%0d: count %0d after the lost push", k, probe.cur.rf_count));
                check(lsr[0] == 1'b1, $sformatf("U16 k=%0d: DR = 0 with the character lost", k));
                begin
                    bit [7:0] d;
                    reg_read(RBR, d);                 // another empty read
                    expect_reg($sformatf("U16 k=%0d: DR still stuck", k), LSR, 8'h61);
                end
            end else
                // Read before the push (character waits, DR) or after it
                // (character read, FIFO empty, no DR).
                check((probe.cur.rf_count == 1 && lsr[0]) || (probe.cur.rf_count == 0 && !lsr[0]),
                      $sformatf("U16 k=%0d (no coincidence): count %0d, DR %0d", k, probe.cur.rf_count, lsr[0]));
        end
        note("U16", $sformatf("pop in the push clock at k =%s", ks));
        check(n_hit != 0, "U16: no read landed its pop in a push clock; widen the sweep");
        if (errors == e0 && n_hit != 0)
            confirmed("U16", "an empty RBR read whose pop meets a push loses the character; DR stays 1");
    endtask

    task u17(fwvip_uart_cfg_item c);
        int unsigned n_hit = 0, e0 = errors;
        string       ks = "";
        init(c.set(1, 8, 1, 1));                      // 8E1/1
        for (int unsigned k = 0; k < 48; k++) begin
            bit hit;
            trial(8'h71, 8'h72, k, hit);              // PE character, then a clean one
            if (probe.cur.rf_count != 1) continue;    // the read did not pop the PE character first
            if (hit) begin
                n_hit++;
                ks = {ks, $sformatf(" %0d", k)};
                check(probe.cur.rf_error_bit == 1'b1,
                      $sformatf("U17 k=%0d: error bit clear with only a clean character in the FIFO", k));
            end else
                check(probe.cur.rf_error_bit == 1'b0,
                      $sformatf("U17 k=%0d (pop alone): error bit still set", k));
        end
        note("U17", $sformatf("pop in the push clock at k =%s", ks));
        check(n_hit != 0, "U17: no read landed its pop in a push clock; widen the sweep");
        if (errors == e0 && n_hit != 0)
            confirmed("U17", "a pop in a push clock leaves the popped entry's error flags in the FIFO's error bit");
    endtask
endclass
