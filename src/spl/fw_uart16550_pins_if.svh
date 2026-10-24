// The pins the model reads and drives that are not a protocol: the modem
// pads, MCR's outputs (with loopback), the interrupt, the transmitter's busy
// level and the baud tick. The pin top implements it on its interface; all
// methods are zero-time.
interface class fw_uart16550_pins_if;
    // MCR as written: {LOOP, OUT2, OUT1, RTS, DTR}.
    pure virtual function void set_mcr(bit [4:0] mcr);
    pure virtual function void set_irq(bit level);
    // The modem input pads in MSR order: {dcd, ri, dsr, cts}.
    pure virtual function bit [3:0] modem_in();
    // The transmit core has a character on the line.
    pure virtual function bit tx_busy();
    // The 16x baud tick, high for one clock.
    pure virtual function bit baud_tick();
endclass
