// The classes that put the fw-uart16550 class model behind pins
// (fw_uart16550_top.sv): exports for the model's tx, line and pins ports on
// fw_uart16550_xtor_if, the threads of the register port and the receive
// path, and the model's root component.
package fw_uart16550_spl_rtl_pkg;
    import fw_hdl_pkg::*;
    import fw_proto_wb_pkg::*;
    import fw_proto_uart_pkg::*;
    import fw_uart16550_spl_pkg::*;

    // uart_tx_if on the tx core. send_break() is not used by the design.
    class fw_uart16550_tx_export extends fw_export #(uart_tx_if) implements uart_tx_if;
        virtual fw_uart16550_xtor_if vif;
        function new(string name, fw_component parent, virtual fw_uart16550_xtor_if vif);
            super.new(name, parent, null);
            set_imp(this);
            this.vif = vif;
        endfunction
        virtual task send(input bit [7:0] data); vif.send(data); endtask
        virtual task set_break(input bit on);    vif.set_break(on); endtask
        virtual task send_break(input int unsigned n_chars);
            $error("fw_uart16550_tx_export: send_break() is not supported");
        endtask
    endclass

    // uart_config_if: the levels both cores and the baud core read.
    class fw_uart16550_line_export extends fw_export #(uart_config_if) implements uart_config_if;
        virtual fw_uart16550_xtor_if vif;
        function new(string name, fw_component parent, virtual fw_uart16550_xtor_if vif);
            super.new(name, parent, null);
            set_imp(this);
            this.vif = vif;
        endfunction
        virtual task configure(input bit [15:0] divisor, input bit [3:0] word_bits,
                               input bit parity_en, input bit parity_even,
                               input bit parity_stick, input bit [1:0] stop_bits);
            vif.configure(divisor, word_bits, parity_en, parity_even, parity_stick, stop_bits);
        endtask
    endclass

    // fw_uart16550_pins_if on the pins: modem pads, MCR, interrupt, tx busy
    // and the baud tick.
    class fw_uart16550_pins_export extends fw_export #(fw_uart16550_pins_if) implements fw_uart16550_pins_if;
        virtual fw_uart16550_xtor_if vif;
        function new(string name, fw_component parent, virtual fw_uart16550_xtor_if vif);
            super.new(name, parent, null);
            set_imp(this);
            this.vif = vif;
        endfunction
        virtual function void set_mcr(bit [4:0] mcr)  ; vif.set_mcr(mcr);      endfunction
        virtual function void set_irq(bit level)      ; vif.set_irq(level);    endfunction
        virtual function bit [3:0] modem_in()         ; return vif.modem_in(); endfunction
        virtual function bit tx_busy()                ; return vif.tx_busy();  endfunction
        virtual function bit baud_tick()              ; return vif.baud_tick(); endfunction
    endclass

    // The receive path: each character from the rx core to the model.
    class fw_uart16550_rx_runner implements fw_runnable;
        virtual fw_uart16550_xtor_if vif;
        uart_rx_if                   sink;
        function new(virtual fw_uart16550_xtor_if vif, uart_rx_if sink);
            this.vif  = vif;
            this.sink = sink;
        endfunction
        virtual task run();
            bit [7:0] data;
            bit [3:0] status;
            forever begin
                vif.recv(data, status);
                sink.recv(data, status);
            end
        endtask
    endclass

    // The register port's bridge thread as a runnable, so an fw_root bind can
    // start it (the kit bridge is a plain class with a run() task).
    class fw_uart16550_wb_runner implements fw_runnable;
        wb_target_xtor_bridge #(32, 32) br;
        function new(wb_target_xtor_bridge #(32, 32) br); this.br = br; endfunction
        virtual task run(); br.run(); endtask
    endclass

    // The model's root: fw_uart16550 on the pins interface.
    class fw_uart16550_pin_top extends fw_component;
        fw_uart16550                 dut;
        fw_uart16550_tx_export       tx;
        fw_uart16550_line_export     line;
        fw_uart16550_pins_export     pins;
        virtual fw_uart16550_xtor_if vif;     // set before build()

        function new(string name, fw_component parent); super.new(name, parent); endfunction

        function void build();
            dut  = new("dut", this);
            tx   = new("tx", this, vif);
            line = new("line", this, vif);
            pins = new("pins", this, vif);
        endfunction

        function void connect();
            dut.tx.connect(tx);
            dut.line.connect(line);
            dut.pins.connect(pins);
        endfunction
    endclass
endpackage
