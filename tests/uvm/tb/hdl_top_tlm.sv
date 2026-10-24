// HDL top for the `tlm` view: only the clock and reset. The class model's
// clock domain is u_clk; the UART VIP and the env take fwvip-core's clock
// and reset. There is no DUT RTL, no bus and no serial pin.
module hdl_top_tlm;
    logic clock = 1'b0;
    logic reset = 1'b1;
    always #5ns clock = ~clock;          // 100 MHz, as the other views
    initial begin
        repeat (4) @(posedge clock);
        reset = 1'b0;
    end

    fw_clock_xtor_if                  u_clk    (.clock(clock), .reset(reset));
    fwvip_clock_xtor_if               u_clk_if (.clock(clock), .reset(reset));
    fwvip_reset_xtor_if #(.ACTIVE(1)) u_rst_if (.clock(clock), .reset(reset));
endmodule
