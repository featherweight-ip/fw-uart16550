// Registers (every view): reset values, the read-write registers, the DLAB
// bank, MCR's pins and its read of 0 (U1), and the unused upper bits.
class fw_uart16550_regs_test extends fw_uart16550_base_test;
    `uvm_component_utils(fw_uart16550_regs_test)

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task body();
        bit [7:0] scr[] = '{8'h5A, 8'hA5, 8'hFF, 8'h00};
        clocks(4);
        // Reset values, with the modem pads at 0.
        expect_reg("IER at reset", IER, 8'h00);
        expect_reg("IIR at reset", IIR, 8'hC1);
        expect_reg("LCR at reset", LCR, 8'h03);
        expect_reg("MCR at reset (reads 0)", MCR, 8'h00);
        expect_reg("LSR at reset", LSR, 8'h60);
        expect_reg("MSR at reset", MSR, 8'h00);
        expect_reg("SCR at reset", SCR, 8'h00);

        // The divisor latch, and the registers it hides.
        reg_write(IER, 8'h05);
        reg_write(LCR, 8'h83);
        expect_reg("DLL at reset", DLL, 8'h00);
        expect_reg("DLM at reset", DLM, 8'h00);
        reg_write(DLL, 8'h5A);
        reg_write(DLM, 8'hA5);
        expect_reg("DLL", DLL, 8'h5A);
        expect_reg("DLM", DLM, 8'hA5);
        expect_reg("LCR with DLAB", LCR, 8'h83);
        reg_write(LCR, 8'h1F);
        expect_reg("LCR", LCR, 8'h1F);
        expect_reg("IER under DLL/DLM", IER, 8'h05);
        reg_write(RBR, 8'h00);              // THR: a character, not DLL
        reg_write(LCR, 8'h83);
        expect_reg("DLL after a THR write", DLL, 8'h5A);
        reg_write(DLL, 8'h00);
        reg_write(DLM, 8'h00);
        reg_write(LCR, 8'h03);

        // IER keeps bits 3:0.
        reg_write(IER, 8'hF0);
        expect_reg("IER upper bits", IER, 8'h00);
        reg_write(IER, 8'h0A);
        expect_reg("IER", IER, 8'h0A);
        reg_write(IER, 8'h00);

        // SCR is eight bits of storage.
        foreach (scr[i]) begin
            reg_write(SCR, scr[i]);
            expect_reg("SCR", SCR, scr[i]);
        end

        // MCR drives RTS and DTR (active high, U23) and reads 0 (U1).
        reg_write(MCR, 8'h03);
        clocks(4);
        check(env.model.modem_out() == 2'b11, $sformatf("RTS/DTR with MCR = 3: %b", env.model.modem_out()));
        expect_reg("MCR reads 0", MCR, 8'h00);
        reg_write(MCR, 8'h02);
        clocks(4);
        check(env.model.modem_out() == 2'b10, $sformatf("RTS/DTR with MCR = 2: %b", env.model.modem_out()));
        reg_write(MCR, 8'h00);
        clocks(4);
        check(env.model.modem_out() == 2'b00, $sformatf("RTS/DTR with MCR = 0: %b", env.model.modem_out()));
    endtask
endclass
