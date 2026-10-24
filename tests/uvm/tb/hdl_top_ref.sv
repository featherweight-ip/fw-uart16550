// HDL top for the `ref` view: the U2B0 arm alone, with clock and reset, and
// fwvip-core's clock and reset transactor interfaces for the UART VIP.
module hdl_top_ref;
    logic clock = 1'b0;
    logic reset = 1'b1;
    always #5ns clock = ~clock;          // 100 MHz
    initial begin
        repeat (4) @(posedge clock);
        reset = 1'b0;
    end

    fwvip_clock_xtor_if               u_clk_if (.clock(clock), .reset(reset));
    fwvip_reset_xtor_if #(.ACTIVE(1)) u_rst_if (.clock(clock), .reset(reset));

    oc_uart16550_ref_arm u_arm (.clock(clock), .reset(reset));
endmodule
