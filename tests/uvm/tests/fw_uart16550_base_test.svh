// Base test: builds the env, counts check failures, reports the verdict.
// Helpers: the register port by register index (the shim puts register n at
// byte address 4n), line setup on the DUT and the VIP together, and the
// VIP's serial side. A test puts its work in body().
class fw_uart16550_base_test extends uvm_test;
    `uvm_component_utils(fw_uart16550_base_test)

    // Register indices (docs/reference/registers.md).
    localparam int RBR = 0, THR = 0, DLL = 0, IER = 1, DLM = 1, IIR = 2, FCR = 2,
                   LCR = 3, MCR = 4, LSR = 5, MSR = 6, SCR = 7;

    fw_uart16550_env  env;
    int unsigned      errors;
    longint unsigned  timeout_clocks = 2_000_000;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = fw_uart16550_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        env.wait_ready();
        fork
            body();
            begin
                env.m_clock.tick(int'(timeout_clocks));
                `uvm_fatal("TIMEOUT", $sformatf("%s did not finish in %0d clocks",
                                                get_type_name(), timeout_clocks))
            end
        join_any
        disable fork;
        phase.drop_objection(this);
    endtask

    virtual task body();
    endtask

    function void check(bit cond, string what);
        if (!cond) begin
            errors++;
            `uvm_error("CHECK", what)
        end
    endfunction

    task clocks(int unsigned n);
        env.m_clock.tick(n);
    endtask

    // ---- register port ----

    task reg_write(int idx, bit [7:0] data);
        bit [31:0] rd;
        bit        err;
        env.model.rf_if().access(32'(4 * idx), {24'h0, data}, 4'hF, 1'b1, rd, err);
        check(!err, $sformatf("write reg %0d <- 0x%02h: bus error", idx, data));
    endtask

    task reg_read(int idx, output bit [7:0] data);
        bit [31:0] rd;
        bit        err;
        env.model.rf_if().access(32'(4 * idx), 32'h0, 4'hF, 1'b0, rd, err);
        check(!err, $sformatf("read reg %0d: bus error", idx));
        check(rd[31:8] == 0, $sformatf("read reg %0d: 0x%08h, upper bytes not 0", idx, rd));
        data = rd[7:0];
    endtask

    task expect_reg(string what, int idx, bit [7:0] exp, bit [7:0] mask = 8'hFF);
        bit [7:0] d;
        reg_read(idx, d);
        check((d & mask) == (exp & mask),
              $sformatf("%s: reg %0d = 0x%02h, expected 0x%02h (mask 0x%02h)", what, idx, d, exp, mask));
    endtask

    // ---- line setup ----

    // LCR[5:0] for framing `c` (word length, stop bits, parity enable, even,
    // stick).
    function bit [7:0] lcr_of(fwvip_uart_cfg_item c);
        return {2'b00, c.parity_stick, c.parity_even, c.parity_en, c.stop_bits[0],
                2'(c.word_bits - 5)};
    endfunction

    // Program the DUT (LCR, DLL, DLM) and set every VIP role to `c`. The
    // lines must be idle. DLL is written before DLM, as Linux does (U24: a
    // later DLM write waits for the next divider reload).
    task configure(fwvip_uart_cfg_item c);
        reg_write(LCR, 8'h80 | lcr_of(c));
        reg_write(DLL, c.divisor[7:0]);
        reg_write(DLM, c.divisor[15:8]);
        reg_write(LCR, lcr_of(c));
        env.set_line(c);
    endtask

    // The usual start: framing `c` (8N1 at divisor 2 by default), FIFOs
    // reset with trigger level `trig` (FCR[7:6]), no interrupts enabled.
    task init(fwvip_uart_cfg_item c = null, bit [1:0] trig = 2'b00);
        if (c == null) begin
            c = fwvip_uart_cfg_item::type_id::create("c");
            void'(c.set(2));
        end
        configure(c);
        reg_write(FCR, {trig, 6'b000110});
        reg_write(IER, 8'h00);
    endtask

    function fwvip_uart_cfg_item line();
        return env.m_tx.m_cfg.line;
    endfunction

    // Clocks in one character at the framing in force.
    function int unsigned char_clocks();
        return line().char_clocks();
    endfunction

    // ---- the VIP's serial side ----

    task tx_item(fwvip_uart_char t);
        fw_uart16550_tx_op_seq s = fw_uart16550_tx_op_seq::type_id::create("op");
        s.item = t;
        s.start(env.m_tx.m_seqr);
    endtask

    protected function fwvip_uart_char mk(fwvip_uart_op_e op);
        fwvip_uart_char t = fwvip_uart_char::type_id::create("t");
        t.op = op;
        return t;
    endfunction

    // Send characters into the DUT's srx (returns once queued).
    task tx_send(bit [7:0] data[]);
        foreach (data[i]) begin
            fwvip_uart_char t = mk(FWVIP_UART_CHAR);
            t.data = data[i];
            tx_item(t);
        end
    endtask

    task tx_err(bit [7:0] data, bit bad_parity = 0, bit bad_stop = 0, int baud_ppm = 0,
                int unsigned glitch_at = 0, int unsigned glitch_len = 0);
        fwvip_uart_char t = mk(FWVIP_UART_ERR);
        t.data = data; t.bad_parity = bad_parity; t.bad_stop = bad_stop;
        t.baud_ppm = baud_ppm; t.glitch_at = glitch_at; t.glitch_len = glitch_len;
        tx_item(t);
    endtask

    task tx_break(int unsigned n_chars);
        fwvip_uart_char t = mk(FWVIP_UART_BREAK);
        t.n_chars = n_chars;
        tx_item(t);
    endtask

    // Wait until everything sent has left the line, then n_bits more.
    task tx_idle(int unsigned n_bits = 0);
        fwvip_uart_char t = mk(FWVIP_UART_IDLE);
        t.n_bits = n_bits;
        tx_item(t);
    endtask

    // The next character the DUT transmitted, or null if none within
    // `max_clocks`. Polls instead of forking a timeout: in Verilator 5.052
    // a class handle filled by a task call inside a fork ... join_any branch
    // does not reach the caller (an int does; see
    // scripts/repro/verilator_fork_handle_out.sv).
    task rx_get(output fwvip_uart_char t, input int unsigned max_clocks = 0);
        int unsigned n = 0;
        if (max_clocks == 0) max_clocks = 4 * char_clocks() + 1000;
        t = null;
        while (env.m_rx.available() == 0 && n < max_clocks) begin
            env.m_clock.tick(4);
            n += 4;
        end
        if (env.m_rx.available() != 0) env.m_rx.get(t);
    endtask

    // Expect the DUT to transmit `data` (in order, clean).
    task expect_rx(string what, bit [7:0] data[]);
        foreach (data[i]) begin
            fwvip_uart_char t;
            rx_get(t);
            if (t == null) begin
                check(0, $sformatf("%s: character %0d (0x%02h) not received", what, i, data[i]));
                return;
            end
            check(t.data == (data[i] & line().mask()) && t.status == 0,
                  $sformatf("%s: character %0d: got 0x%02h %s, expected 0x%02h", what, i,
                            t.data, fwvip_uart_status_str(t.status), data[i]));
        end
    endtask

    function void report_phase(uvm_phase phase);
        if (errors == 0 && uvm_report_server::get_server().get_severity_count(UVM_ERROR) == 0)
            `uvm_info("RESULT", "** TEST PASSED **", UVM_LOW)
        else
            `uvm_error("RESULT", $sformatf("** TEST FAILED (%0d check errors) **", errors))
    endfunction
endclass
