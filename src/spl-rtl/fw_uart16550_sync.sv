// Two-flop synchronizer for srx_pad_i, as U2B0's uart_sync_flops. Leaf RTL:
// the lowering keeps it as an instance.
module fw_uart16550_sync (
        input  wire clock,
        input  wire reset,
        input  wire d,
        output reg  q
    );
    reg q0;
    always @(posedge clock or posedge reset) begin
        if (reset) begin
            q0 <= 1'b1;
            q  <= 1'b1;
        end else begin
            q0 <= d;
            q  <= q0;
        end
    end
endmodule
