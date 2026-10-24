// The register port: an export providing wb_proto_if #(32, 32), as the
// fw-proto-wb target transactor's bridge expects. Each access goes to
// fw_uart16550::host_access().
class fw_uart16550_host extends fw_export #(wb_proto_if #(32, 32)) implements wb_proto_if #(32, 32);
    local fw_uart16550 m_imp;

    function new(string name, fw_component parent, fw_uart16550 imp);
        super.new(name, parent, null);
        set_imp(this);      // after super.new: passing `this` into it crashes Verilator
        m_imp = imp;
    endfunction

    virtual task access(input  [31:0] adr, input [31:0] dat_w, input [3:0] sel, input we,
                        output [31:0] dat_r, output err);
        m_imp.host_access(adr, dat_w, sel, we, dat_r, err);
    endtask
endclass
