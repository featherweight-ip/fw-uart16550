// fw-uart16550 UVM environment: what every view and every test shares. Tests
// reach the design under test only through uart_model_base (published as
// "model") and the fwvip-uart agents. Plan: docs/design/ref-bench.md.
`include "uvm_macros.svh"

package fw_uart16550_env_pkg;
    import uvm_pkg::*;
    import fw_proto_wb_pkg::*;
    import fw_proto_uart_pkg::*;
    import fwvip_core_pkg::*;
    import fwvip_core_uvm_pkg::*;
    import fwvip_uart_xtor_pkg::*;
    import fwvip_uart_pkg::*;

    `include "uart_model_base.svh"
    `include "uart_ref_model.svh"
    `include "uart_ref_probe.svh"
    `include "fw_uart16550_env.svh"
endpackage
