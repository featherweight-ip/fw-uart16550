// U1, U2, U3, U25 and the reset values (docs/reference/registers.md).
//
//   reset  IER 0x00, IIR 0xC1, LCR 0x03, MCR 0x00, LSR 0x60, MSR 0x00,
//          SCR 0x00, DLL 0x00, DLM 0x00
//   U1     MCR is write-only: it reads 0, and the written value drives the
//          RTS and DTR pads
//   U2     SCR holds what is written
//   U3     FIFO always on: with FCR[0] = 0, IIR[7:6] still read 11 and
//          three characters wait in the RX FIFO without an overrun
//   U25    with DLAB = 1, LSR, MSR and IIR reads return their value and
//          clear nothing; with DLAB = 0 the same reads clear
class fw_uart16550_ref_regs_test extends fw_uart16550_ref_base_test;
    `uvm_component_utils(fw_uart16550_ref_regs_test)

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task body();
        fwvip_uart_cfg_item c = fwvip_uart_cfg_item::type_id::create("c");
        bit [7:0] d;

        // ---- reset values
        expect_reg("reset IER", IER, 8'h00);
        expect_reg("reset IIR", IIR, 8'hC1);
        expect_reg("reset LCR", LCR, 8'h03);
        expect_reg("reset MCR", MCR, 8'h00);
        expect_reg("reset LSR", LSR, 8'h60);
        expect_reg("reset MSR", MSR, 8'h00);
        expect_reg("reset SCR", SCR, 8'h00);
        reg_write(LCR, 8'h83);
        expect_reg("reset DLL", DLL, 8'h00);
        expect_reg("reset DLM", DLM, 8'h00);
        reg_write(LCR, 8'h03);

        // ---- U1: MCR write-only, pads follow it
        reg_write(MCR, 8'h03);
        expect_reg("U1 MCR read after 0x03", MCR, 8'h00);
        clocks(2);
        check(env.model.modem_out() == 2'b11, $sformatf("U1: {RTS,DTR} = %b after MCR 0x03", env.model.modem_out()));
        reg_write(MCR, 8'h00);
        clocks(2);
        check(env.model.modem_out() == 2'b00, $sformatf("U1: {RTS,DTR} = %b after MCR 0x00", env.model.modem_out()));
        if (errors == 0) confirmed("U1", "MCR reads 0; the written value drives RTS and DTR");

        // ---- U2: SCR
        reg_write(SCR, 8'hA5);
        expect_reg("U2 SCR", SCR, 8'hA5);
        reg_write(SCR, 8'h5A);
        expect_reg("U2 SCR", SCR, 8'h5A);
        if (errors == 0) confirmed("U2", "SCR is read-write");

        // ---- U3: FIFOs always on
        init(c.set(2, 8, 1, 1));               // 8E1/2
        reg_write(FCR, 8'h00);                 // FCR[0] = 0: "16450 mode"
        expect_reg("U3 IIR with FCR[0] = 0", IIR, 8'hC1);
        tx_send('{8'h11, 8'h22, 8'h33});
        tx_idle(2);
        check(probe.cur.rf_count == 3, $sformatf("U3: RX FIFO count %0d after 3 characters", probe.cur.rf_count));
        expect_reg("U3 LSR (no OE)", LSR, 8'h61);
        expect_reg("U3 RBR 0", RBR, 8'h11);
        expect_reg("U3 RBR 1", RBR, 8'h22);
        expect_reg("U3 RBR 2", RBR, 8'h33);
        if (errors == 0) confirmed("U3", "FCR[0] = 0 leaves the FIFOs on; IIR[7:6] = 11");

        // ---- U25: DLAB = 1 reads clear nothing
        // Make a parity error (LSR.PE, LSR[7]), a CTS change (MSR.DCTS) and
        // a THRE interrupt (IIR 0xC2).
        env.m_mon_rx.allow_status(FWVIP_UART_PE);
        tx_err(8'h5A, .bad_parity(1));
        tx_idle(2);
        env.model.set_modem(4'b1000);           // CTS
        clocks(4);
        reg_write(IER, 8'h02);                  // ETBEI: THRE is pending
        clocks(4);
        reg_write(LCR, 8'h80 | lcr_of(c));      // DLAB = 1
        repeat (2) begin
            expect_reg("U25 LSR, DLAB = 1", LSR, 8'hE5);
            expect_reg("U25 MSR, DLAB = 1", MSR, 8'h11);
            expect_reg("U25 IIR, DLAB = 1", IIR, 8'hC2);
        end
        reg_write(LCR, lcr_of(c));              // DLAB = 0
        expect_reg("U25 LSR, DLAB = 0", LSR, 8'hE5);
        expect_reg("U25 LSR after a read", LSR, 8'h61);
        expect_reg("U25 MSR, DLAB = 0", MSR, 8'h11);
        expect_reg("U25 MSR after a read", MSR, 8'h10);
        expect_reg("U25 IIR, DLAB = 0", IIR, 8'hC2);
        expect_reg("U25 IIR after a read", IIR, 8'hC1);
        expect_reg("U25 RBR", RBR, 8'h5A);
        if (errors == 0) confirmed("U25", "with DLAB = 1, LSR, MSR and IIR reads clear nothing");
    endtask
endclass
