// Interrupts (every view): THRE, RDA at the trigger level, the character
// timeout, RLS and MS, each with IIR and int_o, and cleared the way the
// 16550 clears it.
class fw_uart16550_irq_test extends fw_uart16550_base_test;
    `uvm_component_utils(fw_uart16550_irq_test)

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function bit int_o(); return env.model.irq_level(); endfunction

    task expect_irq(string what, bit [7:0] iir);
        clocks(4);
        check(int_o() == (iir != 8'hC1), $sformatf("%s: int_o = %0b", what, int_o()));
        expect_reg({what, ": IIR"}, IIR, iir);
    endtask

    task body();
        fwvip_uart_cfg_item c = fwvip_uart_cfg_item::type_id::create("c");
        bit [7:0] d;

        // THRE: raised by enabling it with the FIFO empty, cleared by the
        // IIR read that reports it, raised again when the FIFO empties.
        init();
        reg_write(IER, 8'h02);
        expect_irq("THRE enabled", 8'hC2);
        expect_irq("THRE after the IIR read", 8'hC1);
        reg_write(THR, 8'h12);
        expect_rx("THRE", '{8'h12});
        clocks(char_clocks());
        expect_irq("THRE after the character", 8'hC2);
        reg_write(IER, 8'h00);
        expect_irq("THRE disabled", 8'hC1);

        // RDA at trigger level 4, and the timeout below it.
        init(null, 2'b01);
        reg_write(IER, 8'h01);
        tx_send('{8'h01, 8'h02, 8'h03});
        tx_idle(2);
        expect_irq("RDA with 3 at trigger 4", 8'hC1);
        tx_send('{8'h04});
        tx_idle(2);
        expect_irq("RDA with 4 at trigger 4", 8'hC4);
        reg_read(RBR, d);
        clocks(5 * char_clocks());
        expect_irq("timeout with 3 at trigger 4", 8'hCC);
        for (int i = 0; i < 3; i++) reg_read(RBR, d);
        expect_irq("RX FIFO empty", 8'hC1);
        reg_write(IER, 8'h00);

        // RLS: a parity error, cleared by reading LSR.
        env.m_mon_rx.allow_status(FWVIP_UART_PE);
        init(c.set(2, 8, 1, 1));
        reg_write(IER, 8'h04);
        tx_err(8'h33, .bad_parity(1));
        tx_idle(2);
        expect_irq("RLS", 8'hC6);
        expect_reg("RLS: LSR", LSR, 8'hE5);
        expect_irq("RLS after the LSR read", 8'hC1);
        reg_read(RBR, d);
        reg_write(IER, 8'h00);

        // MS: a CTS change, cleared by reading MSR.
        init();
        reg_write(IER, 8'h08);
        env.model.set_modem(4'b1000);
        expect_irq("MS on CTS", 8'hC0);
        expect_reg("MS: MSR", MSR, 8'h11);
        expect_irq("MS after the MSR read", 8'hC1);
        env.model.set_modem(4'b0000);
        expect_irq("MS on CTS falling", 8'hC0);
        expect_reg("MS: MSR after the fall", MSR, 8'h01);
        reg_write(IER, 8'h00);
    endtask
endclass
