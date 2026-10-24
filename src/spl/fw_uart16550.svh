// The fw-uart16550 UART (docs/design/index.md §3; behaviour per §5).
//
// Edges:
//
// - ``host``: register port, an export of ``wb_proto_if #(32, 32)``
// - ``tx``: the kit's transmit API (``uart_tx_if``), a port
// - ``line``: the kit's configuration API (``uart_config_if``), a port. DL
//   and LCR go to the cores on every write that changes them; the cores
//   apply them at the next character (K1)
// - ``pins``: ``fw_uart16550_pins_if``, a port: modem pads, MCR outputs,
//   interrupt, tx busy, baud tick
// - ``rx_sink``: the kit's receive API (``uart_rx_if``), which the view's
//   receive bridge calls for each character
//
// Registers follow U2B0 on a 4-byte stride (the shim's map): writes take
// bits [7:0]; ``wb_sel_i`` is ignored, as the shim ignores it. LCR.DLAB banks
// offsets 0x00 and 0x04 to DLL and DLM (design R2). Read side effects are
// here, not in the register block (R3), and only with DLAB = 0 (U25).
//
// Every state bit has one writer (design §3.2), except the TX FIFO's read
// pointer, which a TX FIFO reset writes from the host side (the host wins):
//
// - host: TX FIFO entries and ``wr_ptr``; RX FIFO ``rd_ptr``; ``rx_bad_clr``,
//   ``oe_ack``, ``head_ack``, ``thre_masked``, ``msr_ack``
// - ``tx_proc``: TX FIFO ``rd_ptr``
// - ``rx_recv`` (the receive bridge's thread): RX FIFO entries and
//   ``wr_ptr``; ``rx_bad_set``, ``oe_set``
// - ``status_proc``: ``msr_prev``, ``msr_set``, the timeout counter,
//   ``lsr_q``, ``iid_q``, ``rx_trig_q``, the interrupt pin
//
// Status is a relation over that state: LSR, IIR, MSR and ``int_o``. Unlike
// U2B0 (rules in parentheses):
//
// - U5/U14: a character that arrives with the RX FIFO full is dropped, and
//   sets OE (``overrun_head``)
// - U6: no THRE hold-off (``thre_holdoff``)
// - U15: a THR write to a full TX FIFO is ignored (``tx_overflow``)
// - U16/U17: same-clock push and pop lose nothing (``rx_pushpop``)
// - U18/U19: PE, FE and BI are those of the character at the head of the RX
//   FIFO, until an LSR read; LSR[7] is set while any character in the FIFO
//   has an error (``lsr_edge``, ``lsr7_clear``)
// - U20/U21: RDA, TI, RLS and MS are levels; only THRE is latched, as a mask
//   an IIR read sets (``rda_lost``, ``rda_stuck``)
// - U24: a DL write takes effect at the next baud tick (the kit baud core
//   has no restart; ``dlm_restart``, not done)
// - U26: a TX FIFO reset as the transmitter takes a byte sends that byte
//   once (``tx_reset_race``)
class fw_uart16550 extends fw_component;
    typedef bit [10:0] rx_ent_t;            // {BI, FE, PE, data}

    fw_uart16550_regs             regs;         // DLAB = 0 registers (RDL)
    fw_uart16550_dlab_regs        dlab_regs;    // DLL and DLM (RDL)
    fw_uart16550_host             host;         // register port
    fw_port #(uart_tx_if)         tx;           // to the kit's transmit core
    fw_port #(uart_config_if)     line;         // line configuration, to the cores
    fw_port #(fw_uart16550_pins_if) pins;       // pads, MCR, interrupt, tick
    fw_uart16550_rx_sink          rx_sink;      // from the kit's receive core

    fw_fifo #(bit [7:0], 16)      txf;          // TX FIFO
    fw_fifo #(rx_ent_t, 16)       rxf;          // RX FIFO

    // Host side.

    // LSR[7], an error anywhere in the RX FIFO: a toggle pair per entry,
    // with ``rx_bad_set``. A push sets its entry's pair to differ if the
    // character has an error; a pop (or a flush) makes it equal again. Unlike
    // counts of bad pushes and pops, a pop needs no read of the head entry's
    // error bits.
    bit [15:0] rx_bad_clr;
    bit        oe_ack;          // OE reported: an LSR read copies oe_set
    bit        head_ack;        // an LSR read has reported the head's errors
    bit        thre_masked;     // an IIR read has reported THRE
    bit [3:0]  msr_ack;         // MSR deltas reported: an MSR read copies msr_set

    // Receive side.

    // The receive side's half of the LSR[7] toggle pairs (see ``rx_bad_clr``).
    bit [15:0] rx_bad_set;
    bit        oe_set;          // toggled by an overrun: OE is oe_set != oe_ack

    // Status process.

    // The modem pads last clock, {dcd, ri, dsr, cts}.
    bit [3:0]  msr_prev;
    bit [3:0]  msr_set;         // toggled per pad change: delta i is set[i] != ack[i]
    bit [9:0]  to_cnt = 10'd639;    // character timeout, in ticks (8N1 at reset)
    bit        to_wr;           // RX FIFO wr_ptr[0] last clock (timeout reload)
    bit        to_rd;           // RX FIFO rd_ptr[0] last clock (timeout reload)
    bit [7:0]  lsr_q = 8'h60;   // LSR as of last clock: the host reads this
    bit [3:0]  iid_q = 4'h1;    // IIR[3:0] as of last clock: the host reads this
    bit        rx_trig_q;       // rx_trig() as of last clock, for iid()

    function new(string name, fw_component parent);
        fw_uart16550_proc p_tx, p_status;
        super.new(name, parent);
        p_tx     = new(this, fw_uart16550_proc::PROC_TX);
        p_status = new(this, fw_uart16550_proc::PROC_STATUS);
        add_runnable(p_tx);
        add_runnable(p_status);
    endfunction

    function void build();
        regs      = new("regs");     // the block adopts the component being built
        dlab_regs = new("dlab_regs");
        host      = new("host", this, this);
        tx        = new("tx", this);
        line      = new("line", this);
        pins      = new("pins", this);
        rx_sink   = new(this);
        txf       = new();
        rxf       = new();
    endfunction

    // ---- register port ----

    // One register access from the host port (``fw_uart16550_host``): the
    // DLAB decode, the writes and their side effects, the reads.
    task host_access(input bit [31:0] adr, input bit [31:0] dat_w, input bit [3:0] sel,
                     input bit we, output bit [31:0] dat_r, output bit err);
        bit [2:0]    idx  = adr[4:2];
        int unsigned off  = int'({idx, 2'b00});
        bit          dlab = regs.LCR.read().DLAB;
        bit [7:0]    v    = dat_w[7:0];
        bit          line_changed = 1'b0;   // one apply_line() call site
        err   = 1'b0;
        dat_r = '0;
        if (dlab && idx < 3'd2) begin
            if (we) begin
                dlab_regs.write_val(off, {24'h0, v});
                line_changed = 1'b1;
            end else begin
                dat_r = dlab_regs.read_val(off);
            end
        end else if (we) begin
            case (idx)
                3'd0: thr_write(v);
                3'd2: fcr_write(off, v);
                default: begin
                    regs.write_val(off, {24'h0, v});
                    case (idx)
                        3'd1: thre_masked = 1'b0;    // IER: THRE raises again
                        3'd3: line_changed = 1'b1;
                        3'd4: pins.t.set_mcr(5'(regs.MCR.read()));
                        default: ;
                    endcase
                end
            endcase
        end else begin
            case (idx)
                3'd0:    dat_r = {24'h0, rbr_read()};
                3'd2:    dat_r = {24'h0, iir_read(!dlab)};
                3'd5:    dat_r = {24'h0, lsr_read(!dlab)};
                3'd6:    dat_r = {24'h0, msr_read(!dlab)};
                default: dat_r = regs.read_val(off);
            endcase
        end
        if (line_changed) apply_line();
    endtask

    // DL and LCR to the cores, and the break level. (Keeping toc_value() in
    // a register set here cost 16 LUT4 and 4 FF for about 1 MHz: not done.)
    task apply_line();
        fw_uart16550_regs__LCR_t lcr = regs.LCR.read();
        line.t.configure({dlab_regs.DLM.read().DLM, dlab_regs.DLL.read().DLL},
                         4'(lcr.WLS) + 4'd5, lcr.PEN, lcr.EPS, lcr.SP, {1'b0, lcr.STB});
        tx.t.set_break(lcr.BC);
    endtask

    // THR: push, unless the TX FIFO is full (U15); THRE raises again.
    protected task thr_write(bit [7:0] v);
        if (!txf.full()) txf.push(v);
        thre_masked = 1'b0;
    endtask

    // FCR: the trigger level, and the RX (bit 1) and TX (bit 2) FIFO resets.
    protected task fcr_write(int unsigned off, bit [7:0] v);
        regs.write_val(off, {24'h0, v});     // RX_TRIG; the reset bits are pulses
        if (v[1]) begin
            rxf.flush();
            rx_bad_clr = rx_bad_set;
            oe_ack    = oe_set;
            head_ack  = 1'b0;
        end
        if (v[2]) begin
            txf.flush();                     // a second writer of rd_ptr: the host wins
            thre_masked = 1'b0;
        end
    endtask

    // RBR: the head character, popped (with its LSR[7] toggle pair).
    protected function bit [7:0] rbr_read();
        rx_ent_t e = rxf.head();
        if (!rxf.empty()) begin
            for (int i = 0; i < 16; i++)
                if (rxf.rd_ptr[3:0] == 4'(i)) rx_bad_clr[i] = rx_bad_set[i];
            rxf.pop();
            head_ack = 1'b0;
        end
        return e[7:0];
    endfunction

    // IIR: ``iid_q``; reading THRE masks it until the next THR write.
    protected function bit [7:0] iir_read(bit side_effects);
        bit [3:0] id = iid_q;
        if (side_effects && id == 4'h2) thre_masked = 1'b1;
        return {4'hC, id};
    endfunction

    // LSR: ``lsr_q``; the read reports OE and the head's errors.
    protected function bit [7:0] lsr_read(bit side_effects);
        bit [7:0] lsr = lsr_q;
        if (side_effects) begin
            oe_ack = oe_set;
            if (!rxf.empty()) head_ack = 1'b1;
        end
        return lsr;
    endfunction

    // MSR: ``msr_value()``; the read reports the deltas.
    protected function bit [7:0] msr_read(bit side_effects);
        bit [7:0] msr = msr_value();
        if (side_effects) msr_ack = msr_set;
        return msr;
    endfunction

    // ---- status: relations ----

    // {BI, FE, PE} of the head character, until an LSR read reports them.
    function bit [2:0] head_err();
        rx_ent_t e = rxf.head();
        if (rxf.empty() || head_ack) return 3'b000;
        return e[10:8];
    endfunction

    // LSR[1], OE: an overrun not yet reported.
    function bit oe(); return oe_set != oe_ack; endfunction

    // LSR now; ``status_proc`` registers it as ``lsr_q``.
    function bit [7:0] lsr_value();
        bit [2:0] he   = head_err();
        bit       thre = txf.empty();
        return {(rx_bad_set ^ rx_bad_clr) != '0, thre && !pins.t.tx_busy(), thre,
                he, oe(), !rxf.empty()};
    endfunction

    // MSR: the pads (or MCR's outputs in loopback) and the deltas.
    function bit [7:0] msr_value();
        fw_uart16550_regs__MCR_t mcr = regs.MCR.read();
        bit [3:0] hi = mcr.LOOP ? {mcr.OUT2, mcr.OUT1, mcr.DTR, mcr.RTS} : msr_prev;
        return {hi, msr_set ^ msr_ack};
    endfunction

    // RX FIFO at or above the trigger level: 1, 4, 8, 14 (FCR[7:6]). Level
    // 1 is !empty(), not count() >= 1: the two are the same function, and
    // Yosys's abc9 then builds every empty() from the count's subtractor
    // and compare, a carry chain into the host's pop.
    function bit rx_trig();
        bit [4:0] n = rxf.count();
        case (regs.FCR.read().RX_TRIG)
            2'd0: return !rxf.empty();
            2'd1: return n >= 5'd4;
            2'd2: return n >= 5'd8;
            default: return n >= 5'd14;
        endcase
    endfunction

    // IIR[3:0], by priority RLS > RDA > TI > THRE > MS. The head's error
    // bits come out of a read mux, the FIFO count out of a subtractor and
    // the timeout out of its reload, too deep to have the priority after
    // them in the same clock, so IIR is from last clock's state, as U2B0
    // builds IIR from its registered LSR: RLS is LSR[4:1] as the host reads
    // it (lsr_q), RDA the trigger level (rx_trig_q), TI the timeout and
    // LSR.DR, MS the deltas. Each term's inputs lag together, so none
    // glitches. THRE keeps the TX FIFO's empty() (a compare): it pairs with
    // thre_masked, which a THR write clears in the clock it pushes, and a
    // lagged THRE would raise int_o for that clock. IIR lags by a clock,
    // which no read sees: the kit's WISHBONE target accepts a request at
    // most every third clock (WATCH, RESP, DRAIN).
    function bit [3:0] iid();
        fw_uart16550_regs__IER_t ier = regs.IER.read();
        if (ier.RLS && lsr_q[4:1] != 4'b0000)               return 4'h6;
        if (ier.RDA && rx_trig_q)                           return 4'h4;
        if (ier.RDA && to_cnt == '0 && lsr_q[0])            return 4'hC;
        if (ier.THRE && txf.empty() && !thre_masked)        return 4'h2;
        if (ier.MS && (msr_set != msr_ack))                 return 4'h0;
        return 4'h1;
    endfunction

    // Four character times in ticks, minus 1 (docs/reference/timing.md): a
    // character of h half-bits is 8h ticks, so 32h - 1.
    function bit [9:0] toc_value();
        fw_uart16550_regs__LCR_t lcr = regs.LCR.read();
        bit [4:0] h = 5'd2 * (5'd6 + 5'(lcr.WLS) + 5'(lcr.PEN)) + 5'd2
                    + (lcr.STB ? ((lcr.WLS == 2'd0) ? 5'd1 : 5'd2) : 5'd0);
        return {h, 5'b0} - 10'd1;
    endfunction

    // ---- receive ----

    // One character from the receive core (``fw_uart16550_rx_sink``):
    // ``status`` is {OE, BI, FE, PE}. Pushed with its errors unless the RX
    // FIFO is full; an overrun (the core's, or a full FIFO) sets OE.
    task rx_recv(input bit [7:0] data, input bit [3:0] status);
        if (rxf.full() || status[3]) begin
            if (oe_set == oe_ack) oe_set = !oe_set;
            if (rxf.full()) return;
        end
        for (int i = 0; i < 16; i++)
            if (rxf.wr_ptr[3:0] == 4'(i))
                rx_bad_set[i] = rx_bad_clr[i] ^ (status[2:0] != 3'b000);
        rxf.push({status[2:0], data});
    endtask

    // ---- processes ----

    // The transmitter: each character from the head of the TX FIFO to the
    // core. The entry is popped once the core has taken it, so THRE rises as
    // the last character starts, unless a TX FIFO reset moved rd_ptr while
    // it waited.
    task tx_proc();
        if (!tx.is_connected())   $fatal(1, "fw_uart16550 %s: the tx port is unconnected", get_name());
        if (!line.is_connected()) $fatal(1, "fw_uart16550 %s: the line port is unconnected", get_name());
        if (!pins.is_connected()) $fatal(1, "fw_uart16550 %s: the pins port is unconnected", get_name());
        apply_line();               // DL and LCR reset values
        forever begin
            bit [4:0] p;
            bit [7:0] d;
            // Polled once a clock, not `wait (txf.wr_ptr != txf.rd_ptr)`: the
            // lowered process looks once a clock either way, and Verilator
            // re-evaluates a wait on class members at every evaluation
            // (docs/design/tlm-view.md).
            while (txf.wr_ptr == txf.rd_ptr) tick();
            p = txf.rd_ptr;
            d = txf.head();
            tx.t.send(d);
            if (txf.rd_ptr == p) txf.pop();
            // One clock before the next head: without it the lowering reads
            // the head again in the state after the handshake (a second read
            // mux at the next index). The core starts the next frame at its
            // next tick.
            tick();
        end
    endtask

    // Each clock: IIR and LSR for the host's reads, the MSR deltas and
    // copies of the pads, the character timeout, and the interrupt pin.
    task status_proc();
        forever begin
            bit [3:0] pads = pins.t.modem_in();
            // IIR first, from last clock's state (lsr_q, rx_trig_q, to_cnt,
            // msr_set): see iid(). Then LSR and the RX trigger level for
            // the next clock: one copy of the status logic, here, instead
            // of one per read.
            iid_q     = iid();
            lsr_q     = lsr_value();
            rx_trig_q = rx_trig();
            pins.t.set_irq(iid_q != 4'h1);

            // MSR: a delta sets on any change of its pad (U22), and holds until
            // an MSR read. msr_prev resets to 0, so a pad that is 1 out of
            // reset sets its delta (U2B0 clears the deltas on the first clock).
            msr_set  = msr_set ^ ((pads ^ msr_prev) & ~(msr_set ^ msr_ack));
            msr_prev = pads;

            // Timeout: reloaded on a push or a pop and while the FIFO is
            // empty; counts down on ticks to 0. A push or a pop moves its
            // pointer by one, so bit 0 shows it; a flush empties the FIFO.
            if (rxf.wr_ptr[0] != to_wr || rxf.rd_ptr[0] != to_rd || rxf.empty())
                to_cnt = toc_value();
            else if (pins.t.baud_tick() && to_cnt != '0)
                to_cnt = to_cnt - 1'b1;
            to_wr = rxf.wr_ptr[0];
            to_rd = rxf.rd_ptr[0];
            tick();
        end
    endtask
endclass
