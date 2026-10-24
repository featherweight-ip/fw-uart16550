// The bench's pins on the arm (uart16550_arm), for the HVL side. Its own
// file because the env's models name it, and the tlm view has no arm.
interface uart_ref_pads_if (input logic clock);
    // Written by the bench.
    logic        cts = 1'b0, dsr = 1'b0, ri = 1'b0, dcd = 1'b0;
    logic        srx_ovr_en = 1'b0;    // srx from srx_ovr, not the tx transactor
    logic        srx_ovr    = 1'b1;
    // The back-to-back driver's request (U13): set the fields, then toggle go.
    logic        b2b_go = 1'b0;
    logic [4:0]  b2b_adr0, b2b_adr1;
    logic [7:0]  b2b_dat0, b2b_dat1;
    logic        b2b_we0, b2b_we1;
    logic [3:0]  b2b_gap;
    // Watched by the bench.
    logic        int_o, stx, srx, rts, dtr;
    logic        b2b_busy;
    logic [7:0]  b2b_rd0, b2b_rd1;

    task automatic wait_clocks(int unsigned n);
        repeat (n) @(posedge clock);
    endtask

    // Two accesses with `gap` idle clocks between the first ack and the
    // second strobe. Returns the read data of each.
    task automatic b2b(input bit we0, input bit [4:0] adr0, input bit [7:0] dat0,
                       input bit we1, input bit [4:0] adr1, input bit [7:0] dat1,
                       input bit [3:0] gap, output bit [7:0] rd0, output bit [7:0] rd1);
        b2b_we0 = we0; b2b_adr0 = adr0; b2b_dat0 = dat0;
        b2b_we1 = we1; b2b_adr1 = adr1; b2b_dat1 = dat1;
        b2b_gap = gap;
        b2b_go  = !b2b_go;
        repeat (3) @(posedge clock);
        while (b2b_busy) @(posedge clock);
        rd0 = b2b_rd0;
        rd1 = b2b_rd1;
    endtask
endinterface
