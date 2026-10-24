// The env: the published model (the DUT) and the fwvip-uart agents on its
// serial pins:
//   m_tx      drives the DUT's srx; its predictions are what the DUT's
//             receiver should report
//   m_rx      receives the DUT's stx
//   m_mon_tx  monitors stx (the DUT transmits)
//   m_mon_rx  monitors srx (the DUT receives); a peer of m_tx
// The top binds the agents to the view's transactors (register macros) and
// publishes fwvip-core's clock and reset providers.
class fw_uart16550_env extends uvm_env;
    `uvm_component_utils(fw_uart16550_env)

    uart_model_base       model;
    fwvip_uart_tx_agent   m_tx;
    fwvip_uart_rx_agent   m_rx;
    fwvip_uart_mon_agent  m_mon_tx;
    fwvip_uart_mon_agent  m_mon_rx;
    fwvip_clock_config    m_clock;
    fwvip_reset_config    m_reset;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(uart_model_base)::get(this, "", "model", model))
            `uvm_fatal("CFG", "no uart_model_base \"model\" in the config DB")
        if (!uvm_config_db #(fwvip_clock_config)::get(this, "", "clock", m_clock))
            `uvm_fatal("CFG", "no clock provider (fwvip_clock_config) in the config DB")
        if (!uvm_config_db #(fwvip_reset_config)::get(this, "", "reset", m_reset))
            `uvm_fatal("CFG", "no reset provider (fwvip_reset_config) in the config DB")
        m_tx     = fwvip_uart_tx_agent::type_id::create("m_tx", this);
        m_rx     = fwvip_uart_rx_agent::type_id::create("m_rx", this);
        m_mon_tx = fwvip_uart_mon_agent::type_id::create("m_mon_tx", this);
        m_mon_rx = fwvip_uart_mon_agent::type_id::create("m_mon_rx", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        m_tx.add_peer(m_mon_rx.m_cfg);
    endfunction

    task run_phase(uvm_phase phase);
        model.start();
    endtask

    // Set every VIP role to framing `c`. Call with both lines idle.
    task set_line(fwvip_uart_cfg_item c);
        m_tx.m_cfg.configure_line(c);
        c.apply(m_rx.m_cfg);
        c.apply(m_mon_tx.m_cfg);
    endtask

    task wait_ready();
        m_reset.wait_reset();
    endtask
endclass
