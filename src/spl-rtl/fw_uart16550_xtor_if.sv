// The model's side of the pins (design §3.1): the kit tx core's request
// channel and break level, the kit rx core's response channel, the line
// configuration both cores and the baud core read, the baud tick, the modem
// pads, MCR's outputs and the interrupt. The class side calls these tasks
// and functions through the bridges in fw_uart16550_spl_rtl_pkg.
//
// Channels follow the fw-proto-wb transactor interfaces: a beat moves on a
// rising edge with valid and ready both high.
interface fw_uart16550_xtor_if (
        input  wire        clock,
        input  wire        reset,
        // tx core
        output reg  [7:0]  req_dat,
        output reg         req_valid,
        input  wire        req_ready,
        input  wire        busy,
        output reg         brk,
        // rx core: {data, OE, BI, FE, PE}
        input  wire [11:0] rsp_dat,
        input  wire        rsp_valid,
        output reg         rsp_ready,
        // line configuration (uart_config_if) and the baud tick
        output reg  [15:0] cfg_divisor,
        output reg  [3:0]  cfg_word_bits,
        output reg         cfg_parity_en,
        output reg         cfg_parity_even,
        output reg         cfg_parity_stick,
        output reg  [1:0]  cfg_stop_bits,
        input  wire        tick,
        // pins: MCR {LOOP, OUT2, OUT1, RTS, DTR}, interrupt, modem pads
        // {dcd, ri, dsr, cts}
        output reg  [4:0]  mcr,
        output reg         irq,
        input  wire [3:0]  modem
    );

    initial begin
        req_dat          = 8'd0;
        req_valid        = 1'b0;
        brk              = 1'b0;
        rsp_ready        = 1'b0;
        cfg_divisor      = 16'd0;
        cfg_word_bits    = 4'd8;
        cfg_parity_en    = 1'b0;
        cfg_parity_even  = 1'b0;
        cfg_parity_stick = 1'b0;
        cfg_stop_bits    = 2'd0;
        mcr              = 5'd0;
        irq              = 1'b0;
    end

    task automatic send(input bit [7:0] data);
        req_dat   <= data;
        req_valid <= 1'b1;
        do @(posedge clock); while (!(req_valid && req_ready));
        req_valid <= 1'b0;
    endtask

    task automatic recv(output bit [7:0] data, output bit [3:0] status);
        rsp_ready <= 1'b1;
        do @(posedge clock); while (!(rsp_valid && rsp_ready));
        {data, status} = rsp_dat;
        rsp_ready <= 1'b0;
    endtask

    function automatic void set_break(input bit on); brk = on; endfunction

    function automatic void configure(
            input bit [15:0] divisor, input bit [3:0] word_bits, input bit parity_en,
            input bit parity_even, input bit parity_stick, input bit [1:0] stop_bits);
        cfg_divisor      = divisor;
        cfg_word_bits    = word_bits;
        cfg_parity_en    = parity_en;
        cfg_parity_even  = parity_even;
        cfg_parity_stick = parity_stick;
        cfg_stop_bits    = stop_bits;
    endfunction

    function automatic void set_mcr(input bit [4:0] v); mcr = v;   endfunction
    function automatic void set_irq(input bit level);   irq = level; endfunction
    function automatic bit [3:0] modem_in();            return modem; endfunction
    function automatic bit tx_busy();                   return busy;  endfunction
    function automatic bit baud_tick();                 return tick;  endfunction
endinterface
