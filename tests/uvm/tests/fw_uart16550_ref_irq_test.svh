// The RDA interrupt: U21, U20, U7.
//
//   U21  the RDA pending flag (and int_o) stays set when the count falls
//        below the trigger level other than by an RBR read at the level:
//        (a) an RX FIFO reset, (b) a raised trigger level. IIR, which
//        looks at the level, reads 0xC1 meanwhile
//   U20  an RBR read at the trigger level whose strobe or pop clock meets
//        a push: the pending flag is cleared and not set again, so int_o
//        falls while IIR reads 0xC4 with trigger-level data in the FIFO
//        (swept over the read's timing; found from the probe)
//   U7   IIR shows RDA from the level and int_o from the pending flag:
//        both U21 (int_o 1, IIR 0xC1) and U20 (int_o 0, IIR 0xC4) show it
class fw_uart16550_ref_irq_test extends fw_uart16550_ref_base_test;
    `uvm_component_utils(fw_uart16550_ref_irq_test)

    localparam bit [7:0] FCR_T4 = 8'h40;      // trigger level 4
    localparam bit [7:0] FCR_T8 = 8'h80;      // trigger level 8

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function bit int_o();
        return probe.vpads.int_o;
    endfunction

    // FIFOs reset at trigger 4, RDA pending cleared, RDA enabled.
    task rearm();
        reg_write(IER, 8'h00);
        reg_write(FCR, FCR_T4 | 8'h06);
        reg_write(IER, 8'h01);
        clocks(4);
    endtask

    task fill4();
        tx_send('{8'h01, 8'h02, 8'h03, 8'h04});
        tx_idle(2);
        check(int_o() == 1'b1 && probe.cur.rda_pnd, "four characters at trigger 4 did not raise int_o");
    endtask

    task body();
        fwvip_uart_cfg_item c = fwvip_uart_cfg_item::type_id::create("c");
        int unsigned e0;
        bit          u21_ok, u20_ok;
        fork track(); join_none

        // ---- U21
        e0 = errors;
        init(c.set(2));
        rearm();
        fill4();
        expect_reg("U21 IIR with 4 at trigger 4", IIR, 8'hC4);
        reg_write(FCR, FCR_T4 | 8'h02);               // RX FIFO reset
        clocks(4);
        check(probe.cur.rf_count == 0, "U21a: RX FIFO not empty after the reset");
        check(int_o() == 1'b1, "U21a: int_o fell after the RX FIFO reset");
        expect_reg("U21a IIR after the RX FIFO reset", IIR, 8'hC1);
        rearm();
        fill4();
        reg_write(FCR, FCR_T8);                       // trigger 8, count 4
        clocks(4);
        check(int_o() == 1'b1, "U21b: int_o fell when the trigger level rose above the count");
        expect_reg("U21b IIR with 4 at trigger 8", IIR, 8'hC1);
        u21_ok = (errors == e0);
        if (u21_ok) confirmed("U21", "RDA pending stays set after an RX FIFO reset or a raised trigger level: int_o 1, IIR 0xC1");

        // ---- U20
        e0 = errors;
        init(c.set(1));                               // a tick every clock
        begin
            int unsigned n_hit = 0;
            string       ks = "";
            for (int unsigned k = 0; k < 48; k++) begin
                bit [7:0] d;
                bit       hit;
                rearm();
                fill4();
                tx_send('{8'h05});
                wait_rstate(SR_REC_STOP);
                clocks(k);
                reg_read(RBR, d);
                tx_idle(2);
                hit = (last_rbr_count == 4) &&
                      (last_rf_push_clk == last_rbr_clk || last_rf_push_clk == last_rbr_clk + 1);
                if (hit) begin
                    n_hit++;
                    ks = {ks, $sformatf(" %0d", k)};
                    check(probe.cur.rf_count == 4, $sformatf("U20 k=%0d: count %0d", k, probe.cur.rf_count));
                    check(int_o() == 1'b0, $sformatf("U20 k=%0d: int_o still 1", k));
                    expect_reg($sformatf("U20 k=%0d IIR", k), IIR, 8'hC4);
                end else
                    check(int_o() == 1'b1, $sformatf("U20 k=%0d (no coincidence): int_o 0 with %0d characters",
                                                     k, probe.cur.rf_count));
            end
            note("U20", $sformatf("push in the RBR read's strobe or pop clock at k =%s", ks));
            check(n_hit != 0, "U20: no read met a push; widen the sweep");
            u20_ok = (errors == e0 && n_hit != 0);
            if (u20_ok) confirmed("U20", "RDA lost when a push meets the RBR read at the trigger level: int_o 0, IIR 0xC4");
        end
        if (u20_ok && u21_ok)
            confirmed("U7", "IIR reports RDA from the FIFO level, int_o from the edge-set pending flag");
    endtask
endclass
