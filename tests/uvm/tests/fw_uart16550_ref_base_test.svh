// Base for the reference confirmation tests (docs/reference/verification.md):
// `ref` view only. Adds the probe (the core's internals each clock, and the
// arm's pads interface) and helpers that wait on it or drive srx directly.
class fw_uart16550_ref_base_test extends fw_uart16550_base_test;
    `uvm_component_utils(fw_uart16550_ref_base_test)

    // Receiver and transmitter states (uart_receiver.v, uart_transmitter.v).
    localparam bit [3:0] SR_IDLE = 4'd0, SR_REC_START = 4'd1, SR_REC_STOP = 4'd4,
                         SR_PUSH = 4'd10;
    localparam bit [2:0] S_IDLE = 3'd0, S_SEND_START = 3'd1, S_POP_BYTE = 3'd5;

    uart_ref_probe probe;

    // Kept by track() (start it with `fork track(); join_none`). Clock
    // numbers are probe.n_clk at the sample.
    longint unsigned n_rx_coinc;        // clocks with an RX FIFO push and pop
    longint unsigned n_tx_coinc;        // clocks with a TX FIFO push and pop
    longint unsigned last_rf_push_clk, last_tf_pop_clk;
    longint unsigned last_rbr_clk;      // the last RBR read strobe
    int unsigned     last_rbr_count;    // the RX FIFO count in that clock
    longint unsigned last_tf_push_clk, last_tf_push_ticks;   // probe.n_enable then
    longint unsigned last_thre_rise_clk, last_thre_rise_ticks;
    longint unsigned last_we_clk;       // the last register write strobe

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(uart_ref_probe)::get(this, "", "ref_probe", probe))
            `uvm_fatal("CFG", "no \"ref_probe\": the reference confirmation tests run on the ref view only")
    endfunction

    // Report a confirmed item in the log, for docs/reference/deviations.md.
    function void confirmed(string id, string what);
        `uvm_info("CONFIRM", $sformatf("%s: %s", id, what), UVM_LOW)
    endfunction

    function void note(string id, string what);
        `uvm_info(id, what, UVM_LOW)
    endfunction

    task track();
        forever begin
            @(probe.clk_ev);
            if (probe.cur.rf_push && probe.cur.rf_pop) n_rx_coinc++;
            if (probe.cur.tf_push && probe.cur.tf_pop) n_tx_coinc++;
            if (probe.cur.rf_push) last_rf_push_clk = probe.n_clk;
            if (probe.cur.tf_pop)  last_tf_pop_clk  = probe.n_clk;
            if (probe.cur.tf_push) begin
                last_tf_push_clk   = probe.n_clk;
                last_tf_push_ticks = probe.n_enable;
            end
            if (probe.cur.we) last_we_clk = probe.n_clk;
            if (probe.cur.lsr[5] && !probe.prev.lsr[5]) begin
                last_thre_rise_clk   = probe.n_clk;
                last_thre_rise_ticks = probe.n_enable;
            end
            if (probe.cur.re && probe.cur.addr == 3'(RBR)) begin
                last_rbr_clk   = probe.n_clk;
                last_rbr_count = probe.cur.rf_count;
            end
        end
    endtask

    // ---- waits on the probe (each returns at the clock edge after the
    // condition held for a clock) ----

    task wait_rstate(bit [3:0] st, int unsigned max_clocks = 100000);
        int unsigned n = 0;
        do begin @(probe.clk_ev); n++; end
        while (probe.cur.rstate != st && n < max_clocks);
        check(probe.cur.rstate == st, $sformatf("receiver did not reach state %0d in %0d clocks", st, max_clocks));
    endtask

    task wait_tstate(bit [2:0] st, int unsigned max_clocks = 100000);
        int unsigned n = 0;
        do begin @(probe.clk_ev); n++; end
        while (probe.cur.tstate != st && n < max_clocks);
        check(probe.cur.tstate == st, $sformatf("transmitter did not reach state %0d in %0d clocks", st, max_clocks));
    endtask

    task wait_rf_count(int unsigned c, int unsigned max_clocks = 100000);
        int unsigned n = 0;
        while (probe.cur.rf_count != c && n < max_clocks) begin @(probe.clk_ev); n++; end
        check(probe.cur.rf_count == c, $sformatf("RX FIFO count did not reach %0d in %0d clocks (%0d)",
                                                 c, max_clocks, probe.cur.rf_count));
    endtask

    // ---- srx driven by the test, clock by clock ----

    // Take srx from the test (level `v`), or give it back to the tx agent.
    task srx_take(bit v = 1'b1);
        probe.vpads.srx_ovr    = v;
        probe.vpads.srx_ovr_en = 1'b1;
        @(probe.clk_ev);
    endtask

    task srx_give();
        probe.vpads.srx_ovr    = 1'b1;
        @(probe.clk_ev);
        probe.vpads.srx_ovr_en = 1'b0;
        @(probe.clk_ev);
    endtask

    task srx_hold(bit v, int unsigned n_clocks);
        probe.vpads.srx_ovr = v;
        repeat (n_clocks) @(probe.clk_ev);
    endtask

    // One frame of `data` at the framing in force, with every bit
    // `bit_clocks` long; `stop` is the first stop bit's level. Leaves srx at
    // the stop level.
    task srx_frame(bit [7:0] data, bit stop = 1'b1, bit bad_parity = 1'b0);
        fwvip_uart_cfg_item c = line();
        int unsigned b = c.bit_clocks();
        srx_hold(1'b0, b);
        for (int i = 0; i < c.word_bits; i++) srx_hold(data[i], b);
        if (c.parity_en) srx_hold(c.parity(data) ^ bad_parity, b);
        srx_hold(stop, b);
    endtask
endclass
