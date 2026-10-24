// One item on the tx agent, for tests that drive the line op by op.
class fw_uart16550_tx_op_seq extends fwvip_uart_tx_seq_base;
    `uvm_object_utils(fw_uart16550_tx_op_seq)

    fwvip_uart_char item;

    function new(string name = "fw_uart16550_tx_op_seq");
        super.new(name);
    endfunction

    task body();
        do_item(item);
    endtask
endclass
