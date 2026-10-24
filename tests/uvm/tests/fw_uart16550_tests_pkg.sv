// fw-uart16550 tests. The common tests (every view) program the device
// through the register port and drive the serial side through the
// fwvip-uart agents; the reference confirmation tests (fw_uart16550_ref_*)
// run on the `ref` view only.
`include "uvm_macros.svh"

package fw_uart16550_tests_pkg;
    import uvm_pkg::*;
    import fw_proto_wb_pkg::*;
    import fwvip_uart_xtor_pkg::*;
    import fwvip_uart_pkg::*;
    import fw_uart16550_env_pkg::*;

    `include "fw_uart16550_tx_op_seq.svh"
    `include "fw_uart16550_base_test.svh"
    `include "fw_uart16550_smoke_test.svh"
    // Reference confirmation tests, `ref` view only.
    `include "fw_uart16550_ref_base_test.svh"
    `include "fw_uart16550_ref_regs_test.svh"
    `include "fw_uart16550_ref_modem_test.svh"
    `include "fw_uart16550_ref_bus_test.svh"
    `include "fw_uart16550_ref_baud_test.svh"
    `include "fw_uart16550_ref_rx_fifo_test.svh"
    `include "fw_uart16550_ref_irq_test.svh"
    `include "fw_uart16550_ref_tx_test.svh"
    `include "fw_uart16550_ref_rx_test.svh"
endpackage
