// U24: only a DLL write restarts the baud divider.
//
//   - From reset (DL = 0, no ticks), DLL <- 0x10 then DLM <- 0x01: the DLL
//     write starts the divider at DL = 0x0010, so the first tick comes 16
//     clocks later; the DLM write takes effect at that reload, and the
//     period is then 0x110.
//   - A DLL write alone restarts the divider at once (DL - 1).
//   - From DL = 0, DLL <- 0 then DLM <- 0x01: the DLL write restarts the
//     counter at DL - 1 = 0xFFFF, so the first tick comes about 65536
//     clocks later, and the period is then 0x100.
//   - The divider runs with DLAB = 1.
class fw_uart16550_ref_baud_test extends fw_uart16550_ref_base_test;
    `uvm_component_utils(fw_uart16550_ref_baud_test)

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    // Clocks from now to the next tick (enable), up to `max`.
    task clocks_to_tick(output longint unsigned n, input longint unsigned max = 200000);
        n = 0;
        do begin @(probe.clk_ev); n++; end
        while (!probe.cur.enable && n < max);
    endtask

    task body();
        longint unsigned n0, n1, n2;
        int unsigned e0 = errors;
        fork track(); join_none

        reg_write(LCR, 8'h83);
        clocks(10);
        check(probe.n_enable == 0, $sformatf("U24: %0d ticks with DL = 0", probe.n_enable));
        reg_write(DLL, 8'h10);
        reg_write(DLM, 8'h01);
        clocks_to_tick(n0);
        clocks_to_tick(n1);
        clocks_to_tick(n2);
        note("U24", $sformatf("DLL 0x10 then DLM 0x01: tick intervals %0d, %0d, %0d clocks (after the DLM write)", n0, n1, n2));
        check(n1 == 16'h110 && n2 == 16'h110, $sformatf("U24: period %0d, %0d, expected %0d", n1, n2, 16'h110));
        check(n0 < 16, $sformatf("U24: first tick %0d clocks after the DLM write, expected within 16 of the DLL write", n0));

        // A DLL write alone restarts at once: DL = 0x0100. The counter is
        // loaded with DL - 1 two clocks after the strobe (start_dlc, then
        // the load), so the first tick is DL + 2 clocks after the strobe.
        reg_write(DLL, 8'h00);
        clocks_to_tick(n0);
        n0 = probe.n_clk - last_we_clk;
        clocks_to_tick(n1);
        note("U24", $sformatf("DLL 0x00 (DL = 0x100): first tick %0d clocks after the write strobe, then %0d", n0, n1));
        check(n0 == 16'h100 + 2, $sformatf("U24: first tick %0d clocks after a DLL write strobe, expected DL + 2 = 258", n0));
        check(n1 == 16'h100, $sformatf("U24: period %0d after DLL 0x00, expected 256", n1));

        // From DL = 0: the counter runs at 0xFFFF.
        reg_write(DLM, 8'h00);                 // DL = 0: no more ticks after this reload
        reg_write(DLL, 8'h00);
        clocks(300);
        n0 = probe.n_enable;
        clocks(300);
        check(probe.n_enable == n0, "U24: ticks with DL = 0");
        reg_write(DLL, 8'h00);                 // start_dlc with DL = 0: dlc = 0xFFFF
        reg_write(DLM, 8'h01);                 // DL = 0x100, not a restart
        clocks_to_tick(n0, 70000);
        clocks_to_tick(n1);
        note("U24", $sformatf("DLL 0x00 then DLM 0x01 from DL = 0: first tick %0d clocks after the DLM write, then %0d", n0, n1));
        check(n0 > 65000, $sformatf("U24: first tick after %0d clocks, expected about 65536", n0));
        check(n1 == 16'h100, $sformatf("U24: then period %0d, expected 256", n1));
        if (errors == e0) confirmed("U24", "only a DLL write restarts the divider; a DLM write waits for the next reload (65536 clocks from DL = 0)");
        reg_write(LCR, 8'h03);
    endtask
endclass
