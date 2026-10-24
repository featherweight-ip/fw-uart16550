// U13: a WISHBONE access that starts in the clock after the previous ack
// (no idle clock) is acked but not performed. With one idle clock it is.
//
// Writes: SCR <- 0x11 then SCR <- 0x22. Reads: two RBR reads with two
// characters in the RX FIFO; a read that is not performed does not pop.
class fw_uart16550_ref_bus_test extends fw_uart16550_ref_base_test;
    `uvm_component_utils(fw_uart16550_ref_bus_test)

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task body();
        bit [7:0] r0, r1;
        int unsigned e0 = errors;
        init();

        // Writes, gap 1: both performed.
        probe.vpads.b2b(1, 5'(4 * SCR), 8'h11, 1, 5'(4 * SCR), 8'h22, 4'd1, r0, r1);
        expect_reg("U13 gap 1: second write performed", SCR, 8'h22);
        // Writes, gap 0: the second is lost.
        probe.vpads.b2b(1, 5'(4 * SCR), 8'h11, 1, 5'(4 * SCR), 8'h33, 4'd0, r0, r1);
        expect_reg("U13 gap 0: second write lost", SCR, 8'h11);

        // Reads of RBR with two characters waiting.
        tx_send('{8'hA1, 8'hA2});
        tx_idle(2);
        check(probe.cur.rf_count == 2, $sformatf("U13: RX FIFO count %0d before the reads", probe.cur.rf_count));
        probe.vpads.b2b(0, 5'(4 * RBR), 8'h00, 0, 5'(4 * RBR), 8'h00, 4'd0, r0, r1);
        clocks(4);
        check(r0 == 8'hA1, $sformatf("U13 gap 0: first read 0x%02h", r0));
        check(probe.cur.rf_count == 1,
              $sformatf("U13 gap 0: RX FIFO count %0d after two reads (the second must not pop)", probe.cur.rf_count));
        note("U13", $sformatf("gap 0: the unperformed RBR read returned 0x%02h", r1));
        reg_write(FCR, 8'h06);
        tx_send('{8'hB1, 8'hB2});
        tx_idle(2);
        probe.vpads.b2b(0, 5'(4 * RBR), 8'h00, 0, 5'(4 * RBR), 8'h00, 4'd1, r0, r1);
        clocks(4);
        check(r0 == 8'hB1 && r1 == 8'hB2, $sformatf("U13 gap 1: reads 0x%02h 0x%02h", r0, r1));
        check(probe.cur.rf_count == 0, $sformatf("U13 gap 1: RX FIFO count %0d after two reads", probe.cur.rf_count));
        if (errors == e0) confirmed("U13", "an access with no idle clock after the previous ack is acked but not performed");
    endtask
endclass
