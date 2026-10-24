// Verilator 5.052 (--binary --timing): a class-handle variable of the
// enclosing task, passed as the output actual of a task call inside a
// fork ... join_any branch, is not written back. The same shape with an int
// works, a direct assignment of the handle in the branch works, and plain
// fork ... join works. Found in fw-uart16550's bench (rx_get, step 4,
// 2026-10-24); see docs/design/ref-bench.md.
//
//   verilator --binary --timing -Wno-fatal verilator_fork_handle_out.sv
//   ./obj_dir/Vverilator_fork_handle_out
//
// Each line prints the result and, in brackets, what IEEE 1800 (6.21: an
// automatic variable a forked process refers to lives on and is shared;
// 13.5: outputs are copied to the actual when the call returns) gives.
// "handle output arg" may also fall under the 1800-2023 13.2.2 rule that
// Verilator quotes when the handle is assigned directly (writing an output
// formal after a timing control); "handle local" does not.
module verilator_fork_handle_out;
  logic clk = 0;
  always #5 clk = ~clk;
  class Item; int v; function new(int v); this.v = v; endfunction endclass
  class Src;
    Item q[$];
    task get(output Item v); wait (q.size() != 0); v = q.pop_front(); endtask
    task get_int(output int v); wait (q.size() != 0); v = q.pop_front().v; endtask
  endclass
  class T;
    Src s = new;
    task h_out(output Item t);               // handle output arg, set by a call in the branch
      bit got = 0;
      fork begin s.get(t); got = 1; end repeat (1000) @(posedge clk); join_any
      disable fork;
      $display("handle output arg: got=%0d t_null=%0d (LRM: 1 0)", got, t == null);
    endtask
    task i_out(output int t);                // int output arg, same shape
      bit got = 0;
      t = -1;
      fork begin s.get_int(t); got = 1; end repeat (1000) @(posedge clk); join_any
      disable fork;
      $display("int output arg:    got=%0d t=%0d (LRM: 1 7)", got, t);
    endtask
    task h_local();                          // handle local, same shape
      Item t; bit got = 0;
      fork begin s.get(t); got = 1; end repeat (1000) @(posedge clk); join_any
      disable fork;
      $display("handle local:      got=%0d t_null=%0d (LRM: 1 0)", got, t == null);
    endtask
    task h_local_direct();                   // handle local, assigned directly in the branch
      Item t; bit got = 0;
      fork begin @(posedge clk); t = new(9); got = 1; end repeat (1000) @(posedge clk); join_any
      disable fork;
      $display("handle local, direct assign: got=%0d t_null=%0d (LRM: 1 0)", got, t == null);
    endtask
    task h_local_join();                     // handle local, call in the branch, plain fork-join
      Item t;
      fork begin s.get(t); end join
      $display("handle local, fork-join:     t_null=%0d (LRM: 0)", t == null);
    endtask
  endclass
  initial begin
    T x = new; Item r; int ri;
    fork begin repeat (5) @(posedge clk); begin Item it = new(5); x.s.q.push_back(it); end end join_none
    x.h_out(r);  $display("  caller sees r_null=%0d", r == null);
    fork begin repeat (5) @(posedge clk); begin Item it = new(7); x.s.q.push_back(it); end end join_none
    x.i_out(ri); $display("  caller sees ri=%0d", ri);
    fork begin repeat (5) @(posedge clk); begin Item it = new(8); x.s.q.push_back(it); end end join_none
    x.h_local();
    x.h_local_direct();
    fork begin repeat (5) @(posedge clk); begin Item it = new(6); x.s.q.push_back(it); end end join_none
    x.h_local_join();
    $finish;
  end
endmodule
