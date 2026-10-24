// The `tlm` view (docs/design/tlm-view.md): the fw-uart16550 class model with
// no pins and no signal-level transactors. The bench reaches the model
// through its method ports: register accesses through a port connected to
// the model's ``host`` export, characters through ``uart_tlm_line``, and
// the pads, MCR, interrupt and baud tick through a class on its ``pins``
// port.
`include "uvm_macros.svh"

package fw_uart16550_tlm_view_pkg;
    import uvm_pkg::*;
    import fw_hdl_pkg::*;
    import fw_proto_wb_pkg::*;
    import fw_proto_uart_pkg::*;
    import fwvip_uart_pkg::*;
    import fw_uart16550_spl_pkg::*;
    import fw_uart16550_env_pkg::*;

    // Status bits as the kit's receive API carries them: {OE, BI, FE, PE}.
    localparam bit [3:0] ST_BI = 4'b0100, ST_FE = 4'b0010, ST_PE = 4'b0001;

    // A line's framing, as uart_config_if::configure() gives it.
    typedef struct {
        bit [15:0] divisor;
        bit [3:0]  word_bits;
        bit        parity_en;
        bit        parity_even;
        bit        parity_stick;
        bit [1:0]  stop_bits;
    } framing_t;

    function automatic framing_t framing_of(fwvip_uart_cfg_item c);
        framing_t f;
        f.divisor = c.divisor;   f.word_bits = c.word_bits;
        f.parity_en = c.parity_en; f.parity_even = c.parity_even;
        f.parity_stick = c.parity_stick; f.stop_bits = c.stop_bits;
        return f;
    endfunction

    // Clocks in one bit: 16 ticks of `divisor` clocks (uart_baud_xtor_core).
    function automatic int unsigned bit_clocks(framing_t f);
        return 16 * int'(f.divisor);
    endfunction

    // Bits from the start bit to the parity bit.
    function automatic int unsigned frame_bits(framing_t f);
        return 1 + int'(f.word_bits) + int'(f.parity_en);
    endfunction

    // Clocks from the start bit to the middle of the first stop bit, where
    // the kit rx core samples it and delivers the character.
    function automatic int unsigned sample_clocks(framing_t f);
        return frame_bits(f) * bit_clocks(f) + bit_clocks(f) / 2;
    endfunction

    // Clocks in a whole frame: 1, 1.5 (5-bit words) or 2 stop bits.
    function automatic int unsigned char_clocks(framing_t f);
        int unsigned halves = (f.stop_bits == 0) ? 2 : ((f.word_bits == 5) ? 3 : 4);
        return ((2 * frame_bits(f) + halves) * bit_clocks(f)) / 2;
    endfunction

    // A receiver on a line: its framing, whether it is on the line now
    // (loopback moves the model's receiver), and where a character goes.
    virtual class uart_tlm_sink;
        pure virtual function framing_t framing();
        virtual function bit enabled(); return 1'b1; endfunction
        pure virtual task deliver(bit [7:0] data, bit [3:0] status);
    endclass

    // One direction of a serial line. A character is a send() call: it waits
    // until the line is free and not in break, is taken on the next clock
    // (the kit tx core's req_ready), keeps the line busy for the frame, and
    // reaches every enabled receiver half a bit into the first stop bit, as
    // the kit rx core samples it. The data is masked to the receiver's word
    // length; a bad parity bit is PE where the receiver checks parity.
    //
    // A break (set_break) is space: after a frame of it each receiver gets
    // one (0, BI) character, and a character it started under is lost.
    // After the break the line is mark for a bit before the next start bit.
    class uart_tlm_line extends fw_component;
        uart_tlm_sink sinks[$];
        bit           busy;          // a character is on the line
        bit           brk;           // the line is held at space
        protected int unsigned m_brk_n;       // breaks started, to tell them apart
        protected int unsigned m_mark_wait;   // clocks of mark owed after a break

        function new(string name, fw_component parent); super.new(name, parent); endfunction

        function void add_sink(uart_tlm_sink s); sinks.push_back(s); endfunction

        task send(bit [7:0] data, framing_t f, bit bad_parity = 0, bit bad_stop = 0);
            int unsigned brk_n;
            if (f.divisor == 0) begin
                $error("[uart_tlm_line %s] send() with divisor 0: no baud tick", get_name());
                return;
            end
            while (busy || brk) tick(1);
            if (m_mark_wait != 0) begin
                tick(m_mark_wait);
                m_mark_wait = 0;
            end
            busy  = 1'b1;
            brk_n = m_brk_n;
            tick(1);
            fork
                frame(data, f, bad_parity, bad_stop, brk_n);
            join_none
        endtask

        protected task frame(bit [7:0] data, framing_t f, bit bad_parity, bit bad_stop,
                             int unsigned brk_n);
            int unsigned at = sample_clocks(f);
            tick(at - 1);              // send() took a clock
            if (m_brk_n == brk_n && !brk) begin
                foreach (sinks[i]) begin
                    framing_t g = sinks[i].framing();
                    bit [3:0] st = 4'b0;
                    if (!sinks[i].enabled()) continue;
                    if (bad_parity && g.parity_en) st |= ST_PE;
                    if (bad_stop)                  st |= ST_FE;
                    sinks[i].deliver(data & 8'((1 << g.word_bits) - 1), st);
                end
            end
            tick(char_clocks(f) - at);
            busy = 1'b0;
        endtask

        // Until the character on the line has ended.
        task wait_idle();
            while (busy) tick(1);
        endtask

        // The line held at space (LCR.BC, or the VIP's break), framed as `f`.
        task set_break(bit on, framing_t f);
            if (on == brk) return;
            brk = on;
            if (on) begin
                m_brk_n++;
                fork
                    break_char(f, m_brk_n);
                join_none
            end else begin
                m_mark_wait = bit_clocks(f);
            end
        endtask

        protected task break_char(framing_t f, int unsigned brk_n);
            tick(sample_clocks(f));
            if (brk && m_brk_n == brk_n)
                foreach (sinks[i])
                    if (sinks[i].enabled()) sinks[i].deliver(8'h00, ST_BI);
        endtask

        task send_break(int unsigned n_chars, framing_t f);
            set_break(1'b1, f);
            tick(n_chars * char_clocks(f));
            set_break(1'b0, f);
        endtask
    endclass

    // The 16x baud tick, as uart_baud_xtor_core: one tick every `divisor`
    // clocks (none while divisor is 0). Computed from the time when it is
    // read, so it costs no process: the model's status process reads it
    // once a clock, which is the only clocked reader. The phase is set when
    // the divisor changes, so the first tick is `divisor` clocks later, as
    // the core reloads.
    class uart_tlm_baud;
        realtime             clk_period = 10ns;
        protected bit [15:0] m_divisor;
        protected longint    m_phase;

        protected function longint cycle();
            return longint'($realtime / clk_period);
        endfunction

        function void set_divisor(bit [15:0] d);
            if (d == m_divisor) return;
            m_divisor = d;
            m_phase   = cycle();
        endfunction

        function bit tick_o();
            longint c = cycle();
            if (m_divisor == 0 || c <= m_phase) return 1'b0;
            return ((c - m_phase) % m_divisor) == 0;
        endfunction
    endclass

    typedef class fw_uart16550_tlm_top;

    // The model's receiver: its rx_sink, on `srx` unless in loopback, and on
    // the model's own `stx` in loopback.
    class tlm_dut_rx_sink extends uart_tlm_sink;
        fw_uart16550_tlm_top top;
        bit                  loop_side;   // the stx line's sink (loopback)
        function new(fw_uart16550_tlm_top top, bit loop_side);
            this.top = top; this.loop_side = loop_side;
        endfunction
        virtual function framing_t framing(); return top.line.f; endfunction
        virtual function bit enabled(); return top.pins.loop() == loop_side; endfunction
        virtual task deliver(bit [7:0] data, bit [3:0] status);
            top.dut.rx_sink.recv(data, status);
        endtask
    endclass

    // The VIP rx agent, on `stx` (nothing reaches it in loopback).
    class tlm_vip_rx_sink extends uart_tlm_sink;
        fw_uart16550_tlm_top top;
        fwvip_uart_rx_config cfg;
        function new(fw_uart16550_tlm_top top, fwvip_uart_rx_config cfg);
            this.top = top; this.cfg = cfg;
        endfunction
        virtual function framing_t framing(); return framing_of(cfg.line); endfunction
        virtual function bit enabled(); return !top.pins.loop(); endfunction
        virtual task deliver(bit [7:0] data, bit [3:0] status); cfg.recv(data, status); endtask
    endclass

    // A VIP monitor: on `stx` (not in loopback, when stx is mark) or `srx`.
    class tlm_vip_mon_sink extends uart_tlm_sink;
        fw_uart16550_tlm_top  top;
        fwvip_uart_mon_config cfg;
        function new(fw_uart16550_tlm_top top, fwvip_uart_mon_config cfg);
            this.top = top; this.cfg = cfg;
        endfunction
        virtual function framing_t framing(); return framing_of(cfg.line); endfunction
        virtual function bit enabled(); return !(cfg.is_tx && top.pins.loop()); endfunction
        virtual task deliver(bit [7:0] data, bit [3:0] status);
            cfg.observe(data, status, cfg.is_tx);
        endtask
    endclass

    // uart_tx_if on the `stx` line, at the model's framing.
    class tlm_tx_export extends fw_export #(uart_tx_if) implements uart_tx_if;
        fw_uart16550_tlm_top top;
        function new(string name, fw_component parent, fw_uart16550_tlm_top top);
            super.new(name, parent, null);
            set_imp(this);
            this.top = top;
        endfunction
        virtual task send(input bit [7:0] data); top.stx.send(data, top.line.f); endtask
        virtual task set_break(input bit on);    top.stx.set_break(on, top.line.f); endtask
        virtual task send_break(input int unsigned n_chars);
            top.stx.send_break(n_chars, top.line.f);
        endtask
    endclass

    // uart_config_if: the framing both directions use, and the baud divisor.
    class tlm_line_export extends fw_export #(uart_config_if) implements uart_config_if;
        fw_uart16550_tlm_top top;
        framing_t            f;
        function new(string name, fw_component parent, fw_uart16550_tlm_top top);
            super.new(name, parent, null);
            set_imp(this);
            this.top = top;
            f.word_bits = 4'd8;
        endfunction
        virtual task configure(input bit [15:0] divisor, input bit [3:0] word_bits,
                               input bit parity_en, input bit parity_even,
                               input bit parity_stick, input bit [1:0] stop_bits);
            f.divisor = divisor;   f.word_bits = word_bits;
            f.parity_en = parity_en; f.parity_even = parity_even;
            f.parity_stick = parity_stick; f.stop_bits = stop_bits;
            top.baud.set_divisor(divisor);
        endtask
    endclass

    // fw_uart16550_pins_if as methods: the pads, MCR, the interrupt, the
    // transmitter's busy level and the baud tick.
    class tlm_pins_export extends fw_export #(fw_uart16550_pins_if)
            implements fw_uart16550_pins_if;
        fw_uart16550_tlm_top top;
        bit [4:0]            mcr;      // {LOOP, OUT2, OUT1, RTS, DTR}
        bit [3:0]            modem;    // {dcd, ri, dsr, cts}
        uart_model_base      irq;      // set by the model before start()
        function new(string name, fw_component parent, fw_uart16550_tlm_top top);
            super.new(name, parent, null);
            set_imp(this);
            this.top = top;
        endfunction
        function bit loop(); return mcr[4]; endfunction
        virtual function void set_mcr(bit [4:0] mcr) ; this.mcr = mcr; endfunction
        virtual function void set_irq(bit level)     ; if (irq != null) irq.irq_changed(level); endfunction
        virtual function bit [3:0] modem_in()        ; return modem; endfunction
        virtual function bit tx_busy()               ; return top.stx.busy; endfunction
        virtual function bit baud_tick()             ; return top.baud.tick_o(); endfunction
    endclass

    // The view's root: the model, its register port's peer, the two lines,
    // the pins and the baud tick.
    class fw_uart16550_tlm_top extends fw_component;
        fw_uart16550                    dut;
        fw_port #(wb_proto_if #(32, 32)) rf;     // to the model's host export
        uart_tlm_line                   stx;    // the model transmits
        uart_tlm_line                   srx;    // the model receives
        uart_tlm_baud                   baud;
        tlm_tx_export                   tx;
        tlm_line_export                 line;
        tlm_pins_export                 pins;

        // Set by the model before start().
        fwvip_uart_rx_config            vip_rx;
        fwvip_uart_mon_config           vip_mon_tx;
        fwvip_uart_mon_config           vip_mon_rx;
        uart_model_base                 irq;

        function new(string name, fw_component parent); super.new(name, parent); endfunction

        function void build();
            tlm_dut_rx_sink  rx_srx, rx_loop;
            tlm_vip_rx_sink  vrx;
            tlm_vip_mon_sink mtx, mrx;
            dut  = new("dut", this);
            rf   = new("rf", this);
            stx  = new("stx", this);
            srx  = new("srx", this);
            baud = new();
            tx   = new("tx", this, this);
            line = new("line", this, this);
            pins = new("pins", this, this);
            pins.irq = irq;
            rx_srx  = new(this, 1'b0);
            rx_loop = new(this, 1'b1);
            vrx     = new(this, vip_rx);
            mtx     = new(this, vip_mon_tx);
            mrx     = new(this, vip_mon_rx);
            stx.add_sink(vrx);
            stx.add_sink(mtx);
            stx.add_sink(rx_loop);
            srx.add_sink(mrx);
            srx.add_sink(rx_srx);
        endfunction

        function void connect();
            rf.connect(dut.host);
            dut.tx.connect(tx);
            dut.line.connect(line);
            dut.pins.connect(pins);
        endfunction
    endclass

    // The VIP tx agent on the `srx` line: characters, errors and breaks at
    // the agent's framing. Glitches have no meaning without a bit level.
    class fwvip_uart_tlm_tx_config extends fwvip_uart_tx_config;
        `uvm_object_utils(fwvip_uart_tlm_tx_config)

        fw_component_root #(fw_uart16550_tlm_top) root;   // set by the model

        function new(string name = "fwvip_uart_tlm_tx_config"); super.new(name); endfunction

        protected task line_ready();
            if (root == null) `uvm_fatal("TLMTX", "no tlm root: the model seats it")
            wait (root.elaborated);
        endtask

        protected virtual task xtor_configure(input bit [15:0] divisor, input bit [3:0] word_bits,
                                              input bit parity_en, input bit parity_even,
                                              input bit parity_stick, input bit [1:0] stop_bits);
            // The framing is `line`, which configure() has set.
        endtask

        virtual task send(input bit [7:0] data);
            line_ready();
            root.srx.send(data, framing_of(line));
        endtask

        virtual task set_break(input bit on);
            line_ready();
            root.srx.set_break(on, framing_of(line));
        endtask

        virtual task send_break(input int unsigned n_chars);
            line_ready();
            root.srx.send_break(n_chars, framing_of(line));
        endtask

        virtual task send_err(input bit [7:0] data, input bit bad_parity, input bit bad_stop,
                              input int baud_ppm, input int unsigned glitch_at,
                              input int unsigned glitch_len);
            if (glitch_len != 0)
                `uvm_error("TLMTX", "send_err() with a glitch: no meaning at TLM (tlm-view.md)")
            line_ready();
            root.srx.send(data, framing_of(line), bad_parity, bad_stop);
            // Unlike send(), the kit transactor's send_err() returns once the
            // frame is off the line, and the driver times from that.
            root.srx.wait_idle();
        endtask

        virtual task glitch(input int unsigned glitch_len);
            `uvm_error("TLMTX", "glitch(): no meaning at TLM (tlm-view.md)")
        endtask
    endclass

    // The register port: the root's `rf` port, connected to the model's host
    // export. Accesses that arrive before the model has elaborated wait.
    //
    // An access keeps the bus's timing: it starts on a clock edge and the
    // next one can start three clocks later, as through the fw-proto-wb
    // target (WATCH, RESP, DRAIN). The model relies on that: LSR and IIR are
    // registered (iid_q, lsr_q), so a read in the clock after an access that
    // changed them would see the old value. A zero-time access() would.
    class fw_uart16550_tlm_rf implements wb_proto_if #(32, 32);
        fw_component_root #(fw_uart16550_tlm_top) root;
        virtual task access(input  [31:0] adr, input [31:0] dat_w, input [3:0] sel, input we,
                            output [31:0] dat_r, output err);
            wait (root.elaborated);
            root.tick(1);
            root.rf.t.access(adr, dat_w, sel, we, dat_r, err);
            root.tick(2);
        endtask
    endclass

    // The model as the bench sees it (uart_model_base), at TLM.
    class uart_tlm_model extends uart_model_base;
        virtual fw_clock_xtor_if                  vclk;
        fw_component_root #(fw_uart16550_tlm_top) root;
        fwvip_uart_tlm_tx_config                  vip_tx;
        protected fw_uart16550_tlm_rf             m_rf;

        function new(string name = "tlm");
            super.new(name);
            root = new("root");
            m_rf = new();
            m_rf.root = root;
            vip_tx = fwvip_uart_tlm_tx_config::type_id::create("tlm_tx_cfg");
            vip_tx.root = root;
            root.vip_rx     = fwvip_uart_rx_config::type_id::create("tlm_rx_cfg");
            root.vip_mon_tx = fwvip_uart_mon_config::type_id::create("tlm_mon_tx_cfg");
            root.vip_mon_rx = fwvip_uart_mon_config::type_id::create("tlm_mon_rx_cfg");
            root.vip_mon_tx.is_tx = 1'b1;
            root.vip_mon_rx.is_tx = 1'b0;
            root.irq = this;
        endfunction

        // File the VIP configs for the env's agents (instead of the
        // fwvip_uart_*_register macros, which bind transactors).
        function void register_vip(string env_path);
            uvm_config_db #(fwvip_uart_tx_config)::set(null, {env_path, ".m_tx*"}, "cfg", vip_tx);
            uvm_config_db #(fwvip_uart_rx_config)::set(null, {env_path, ".m_rx*"}, "cfg", root.vip_rx);
            uvm_config_db #(fwvip_uart_mon_config)::set(null, {env_path, ".m_mon_tx*"}, "cfg", root.vip_mon_tx);
            uvm_config_db #(fwvip_uart_mon_config)::set(null, {env_path, ".m_mon_rx*"}, "cfg", root.vip_mon_rx);
        endfunction

        virtual function wb_proto_if #(32, 32) rf_if(); return m_rf; endfunction

        virtual task start();
            fw_clock_xtor_bridge clk;
            if (vclk == null) `uvm_fatal("TLMMODEL", "vclk not seated")
            clk = new("clock", root, vclk);
            root.clock.connect(clk);
            fork
                root.start();
            join_none
            wait (root.elaborated);
        endtask

        virtual task set_modem(bit [3:0] cts_dsr_ri_dcd);
            bit cts, dsr, ri, dcd;
            {cts, dsr, ri, dcd} = cts_dsr_ri_dcd;
            wait (root.elaborated);
            root.pins.modem = {dcd, ri, dsr, cts};
        endtask

        virtual function bit [1:0] modem_out();
            if (!root.elaborated) return 2'b00;
            return {root.pins.mcr[1], root.pins.mcr[0]};    // {RTS, DTR}
        endfunction
    endclass
endpackage
