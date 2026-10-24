// U23, U9, U22, U8: the modem pins.
//
//   U23  pins active high: MCR[0] drives DTR, MCR[1] RTS, as levels; MSR[7:4]
//        are {DCD, RI, DSR, CTS} as on the pads, not complemented
//   U9   (functional part) a pad change sets its delta bit in MSR[3:0]
//   U22  TERI is set on both edges of RI. In loopback MSR[7:4] follow MCR
//        (CTS = RTS, DSR = DTR, RI = OUT1, DCD = OUT2), MCR changes set no
//        delta, and pad changes still do
//   U8   in loopback RTS and DTR still drive the pads, stx is held at mark,
//        and a THR character comes back in RBR
class fw_uart16550_ref_modem_test extends fw_uart16550_ref_base_test;
    `uvm_component_utils(fw_uart16550_ref_modem_test)

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    // Set the pads {cts, dsr, ri, dcd} and let them reach MSR.
    task pads(bit [3:0] v);
        env.model.set_modem(v);
        clocks(4);
    endtask

    task body();
        int unsigned e0;
        init();

        // ---- U23: output pins follow MCR, active high
        reg_write(MCR, 8'h01);
        clocks(2);
        check(env.model.modem_out() == 2'b01, $sformatf("U23: {RTS,DTR} = %b with MCR 0x01", env.model.modem_out()));
        reg_write(MCR, 8'h02);
        clocks(2);
        check(env.model.modem_out() == 2'b10, $sformatf("U23: {RTS,DTR} = %b with MCR 0x02", env.model.modem_out()));
        reg_write(MCR, 8'h00);
        // ---- U23 and U9: each input pad, MSR[7:4] uncomplemented, delta set
        expect_reg("MSR idle", MSR, 8'h00);
        e0 = errors;
        pads(4'b1000);  expect_reg("CTS 1", MSR, 8'h11);  expect_reg("CTS 1, read again", MSR, 8'h10);
        pads(4'b1100);  expect_reg("DSR 1", MSR, 8'h32);  expect_reg("DSR 1, read again", MSR, 8'h30);
        pads(4'b1101);  expect_reg("DCD 1", MSR, 8'hB8);  expect_reg("DCD 1, read again", MSR, 8'hB0);
        pads(4'b0000);  expect_reg("CTS DSR DCD 0", MSR, 8'h0B);
        if (errors == e0) begin
            confirmed("U23", "modem pins active high: MCR bits drive DTR/RTS high, MSR[7:4] = pads");
            confirmed("U9", "a pad change sets its MSR delta bit (functional part)");
        end

        // ---- U22: TERI on both edges of RI
        e0 = errors;
        pads(4'b0010);  expect_reg("U22 RI rising", MSR, 8'h44);
        pads(4'b0000);  expect_reg("U22 RI falling", MSR, 8'h04);
        expect_reg("U22 MSR cleared", MSR, 8'h00);

        // ---- U22 and U8: loopback
        reg_write(MCR, 8'h10);                         // loopback, all outputs 0
        clocks(2);
        expect_reg("U22 loopback, MCR 0x10", MSR, 8'h00);
        reg_write(MCR, 8'h1F);                         // RTS DTR OUT1 OUT2
        clocks(4);
        expect_reg("U22 loopback, MCR 0x1F: MSR[7:4] follow MCR, no delta", MSR, 8'hF0);
        check(env.model.modem_out() == 2'b11,
              $sformatf("U8: {RTS,DTR} = %b in loopback with MCR 0x1F", env.model.modem_out()));
        pads(4'b1111);
        expect_reg("U22 loopback, pads all 1: deltas from the pads", MSR, 8'hFF);
        pads(4'b0000);
        expect_reg("U22 loopback, pads all 0", MSR, 8'hFF);
        expect_reg("U22 loopback, read again", MSR, 8'hF0);
        if (errors == e0) confirmed("U22", "TERI on both RI edges; in loopback MSR[7:4] follow MCR, deltas follow the pads");

        // ---- U8: loopback data path, stx held at mark
        e0 = errors;
        begin
            int unsigned n_stx = env.m_mon_tx.n_chars;
            reg_write(THR, 8'h96);
            clocks(3 * char_clocks());
            check(probe.vpads.stx == 1'b1, "U8: stx not at mark in loopback");
            check(env.m_mon_tx.n_chars == n_stx, "U8: a character appeared on stx in loopback");
            expect_reg("U8 loopback LSR", LSR, 8'h61);
            expect_reg("U8 loopback RBR", RBR, 8'h96);
        end
        reg_write(MCR, 8'h00);
        if (errors == e0) confirmed("U8", "loopback leaves RTS/DTR on the pads, holds stx at mark, loops THR to RBR");
    endtask
endclass
