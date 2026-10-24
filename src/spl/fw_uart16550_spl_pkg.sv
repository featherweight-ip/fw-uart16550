// fw-uart16550: the 16550 UART as an fw-hdl class model (docs/design/index.md
// §3). U2B0-compatible registers (the generated fw_uart16550_regs and the
// DLAB bank), TX and RX FIFOs (fw_fifo), the transmitter process, the receive
// sink, and status and interrupts as relations. The bit level is the
// fw-proto-uart kit, through its APIs.
package fw_uart16550_spl_pkg;
    import fw_hdl_pkg::*;
    import fw_std_pkg::*;
    import fw_proto_wb_pkg::*;
    import fw_proto_uart_pkg::*;
    import fw_uart16550_reg_pkg::*;
    import fw_uart16550_dlab_reg_pkg::*;

    typedef class fw_uart16550;

    `include "fw_uart16550_pins_if.svh"
    `include "fw_uart16550_host.svh"
    `include "fw_uart16550_rx_sink.svh"
    `include "fw_uart16550_proc.svh"
    `include "fw_uart16550.svh"
endpackage
