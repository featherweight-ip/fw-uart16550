// Wait-style microbenchmark (docs/design/tlm-view.md): one waiter woken every
// 100 clocks for 2 M clocks, in the style +style=N picks:
//   0 wait (expr) on class members   1 @(event)   2 semaphore   3 mailbox
//   4 a check every clock            5 no waiter (baseline)
// Run: scripts/repro/wait_styles.sh
class obj;
    bit [4:0] wr, rd;
    event     ev;
    semaphore sem = new(0);
    mailbox #(int) mb = new();
endclass
module top;
    logic clock = 0;
    always #5 clock = ~clock;
    obj o = new();
    int style, n_wake;
    event never;     // module-level, never triggered
    initial begin
        if (!$value$plusargs("style=%d", style)) style = 0;
        fork
            forever begin                  // the waiter
                case (style)
                0: wait (o.wr != o.rd);
                1: begin @(o.ev); end
                2: o.sem.get(1);
                3: begin int v; o.mb.get(v); end
                4: @(posedge clock);       // poll every clock, as a per-clock process
                5: @never;                 // baseline: no waiter
                endcase
                if (style == 4 && o.wr == o.rd) continue;
                o.rd = o.wr; n_wake++;
            end
            forever begin                  // the producer
                repeat (100) @(posedge clock);
                o.wr++;
                case (style) 1: ->o.ev; 2: o.sem.put(1); 3: o.mb.put(1); default: ; endcase
            end
        join_none
        repeat (2000000) @(posedge clock);
        $display("style %0d wakes %0d", style, n_wake);
        $finish;
    end
endmodule
