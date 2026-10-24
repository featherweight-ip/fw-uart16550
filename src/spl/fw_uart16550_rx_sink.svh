// The receive side: the kit's receive API (uart_rx_if). The view's receive
// bridge calls recv() for each character the line delivers; it goes to
// fw_uart16550::rx_recv().
class fw_uart16550_rx_sink implements uart_rx_if;
    local fw_uart16550 m_dev;
    function new(fw_uart16550 dev); m_dev = dev; endfunction
    virtual task recv(input bit [7:0] data, input bit [3:0] status);
        m_dev.rx_recv(data, status);
    endtask
endclass
