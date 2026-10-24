// Line status (every view): a parity error, a framing error and a break,
// each reported in LSR with its character at the head of the RX FIFO and
// cleared by reading it; and an overrun.
class fw_uart16550_status_test extends fw_uart16550_base_test;
    `uvm_component_utils(fw_uart16550_status_test)

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task body();
        fwvip_uart_cfg_item c = fwvip_uart_cfg_item::type_id::create("c");
        bit [7:0] d;

        env.m_mon_rx.allow_status(FWVIP_UART_PE | FWVIP_UART_FE | FWVIP_UART_BI);

        // 8E1: a parity error.
        init(c.set(2, 8, 1, 1));
        tx_err(8'h5A, .bad_parity(1));
        tx_idle(2);
        expect_reg("parity error: LSR", LSR, 8'hE5);
        expect_reg("parity error: RBR", RBR, 8'h5A);
        expect_reg("parity error: LSR after RBR", LSR, 8'h60);

        // A framing error.
        tx_err(8'hC3, .bad_stop(1));
        tx_idle(2);
        expect_reg("framing error: LSR", LSR, 8'hE9);
        expect_reg("framing error: RBR", RBR, 8'hC3);
        expect_reg("framing error: LSR after RBR", LSR, 8'h60);

        // A clean character after an error is clean.
        tx_send('{8'h77});
        tx_idle(2);
        expect_reg("clean: LSR", LSR, 8'h61);
        expect_reg("clean: RBR", RBR, 8'h77);

        // A break: one zero character with BI (U12).
        init();
        tx_break(3);
        tx_idle(4);
        expect_reg("break: LSR", LSR, 8'hF1);
        expect_reg("break: RBR", RBR, 8'h00);
        expect_reg("break: LSR after RBR", LSR, 8'h60);

        // Overrun: 17 characters into the 16-deep FIFO. OE is set, the count
        // stays 16 and an LSR read clears OE. U2B0 also sets LSR[7] (U5),
        // which is not checked, and overwrites the head byte (U14), so the
        // data is checked from the second entry.
        init();
        for (int i = 0; i < 17; i++) tx_send('{8'(8'h40 + i)});
        tx_idle(2);
        expect_reg("overrun: LSR", LSR, 8'h63, 8'h7F);
        expect_reg("overrun: LSR again", LSR, 8'h61, 8'h7F);
        for (int i = 0; i < 16; i++) begin
            reg_read(RBR, d);
            if (i > 0) check(d == 8'(8'h40 + i), $sformatf("overrun: RBR %0d = 0x%02h", i, d));
        end
        expect_reg("overrun: LSR after 16 reads", LSR, 8'h60);
    endtask
endclass
