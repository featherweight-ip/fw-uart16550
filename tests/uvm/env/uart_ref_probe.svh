// What the reference confirmation tests see of U2B0 beyond its pins: the
// core's internals, sampled every clock by the `ref` top (hvl_top_ref), and
// the arm's pads interface (srx override, back-to-back driver). Published as
// "ref_probe" by the `ref` view only.
//
// A sample holds the values in the clock before the edge it was taken at,
// so `cur` is what the core's registers held during the last clock.
typedef struct {
    bit        we, re;          // register strobes (uart_wb we_o, re_o)
    bit [2:0]  addr;            // register index
    bit        enable;          // the 16x baud tick
    bit [4:0]  rf_count, tf_count;
    bit        rf_push, rf_pop, tf_push, tf_pop;
    bit        rf_error_bit;    // OR of the RX FIFO entries' error flags (U17)
    bit [7:0]  lsr;
    bit [3:0]  iir;
    bit [7:0]  block_cnt;       // THRE hold-off (U6)
    bit        rda_int;         // RDA level (U7)
    bit        rls_pnd, rda_pnd, thre_pnd, ms_pnd, ti_pnd;
    bit        int_o;
    bit [3:0]  rstate, rcounter16;
    bit [2:0]  tstate;
    bit        serial_in;       // the receiver's input (after the synchronizer and loopback)
    bit [15:0] dlc;             // the baud divider's counter
} uart_ref_sample_s;

class uart_ref_probe;
    virtual uart_ref_pads_if  vpads;
    longint unsigned          n_clk;
    uart_ref_sample_s         cur, prev;
    event                     clk_ev;
    // Counts since the start of the run.
    longint unsigned          n_enable, n_rf_push, n_rf_pop, n_tf_push;

    function void tick(uart_ref_sample_s s);
        n_clk++;
        prev = cur;
        cur  = s;
        if (s.enable)  n_enable++;
        if (s.rf_push) n_rf_push++;
        if (s.rf_pop)  n_rf_pop++;
        if (s.tf_push) n_tf_push++;
        -> clk_ev;
    endfunction

    task wait_clocks(int unsigned n); repeat (n) @(clk_ev); endtask
endclass
