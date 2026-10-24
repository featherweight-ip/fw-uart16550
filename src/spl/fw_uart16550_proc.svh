// The model's processes as runnables: fw_uart16550 has two (the transmitter
// and the per-clock status process), and a component has one run().
class fw_uart16550_proc implements fw_runnable;
    typedef enum { PROC_TX, PROC_STATUS } which_e;
    local fw_uart16550 m_dev;
    local which_e      m_which;
    function new(fw_uart16550 dev, which_e which); m_dev = dev; m_which = which; endfunction
    virtual task run();
        case (m_which)
            PROC_TX:     m_dev.tx_proc();
            PROC_STATUS: m_dev.status_proc();
        endcase
    endtask
endclass
