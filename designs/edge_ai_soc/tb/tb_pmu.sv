// PMU: power-down/up sequence ordering, switch-ack timeout, auto-idle, thermal throttle, ICG.
module tb_pmu;
  localparam int D = 4;
  logic clk = 0, rst_n = 0;
  logic r_req = 0, r_we = 0; logic [7:0] r_addr = 0; logic [31:0] r_wdata = 0, r_rdata;
  logic [D-1:0] idle = 0, pwr_ack, clk_en, iso_en, ret_save, pwr_en, dom_rst_n, dom_err;
  logic [11:0] temp = 100;
  logic throttle;
  logic [D-1:0] ack_stuck = 0;
  integer fails = 0, checks = 0;

  pmu #(.D(D), .NPU_DOM(0)) dut (.*);
  always #5 clk = ~clk;

  // power switch model: acknowledge follows pwr_en after 3 cycles unless stuck
  logic [D-1:0] a1, a2, a3;
  always @(posedge clk) begin a1 <= pwr_en; a2 <= a1; a3 <= a2; end
  assign pwr_ack = a3 & ~ack_stuck | (ack_stuck & {D{1'b1}});

  // sequence checker: the order of the protection signals must never be violated
  always @(posedge clk) if (rst_n)
    for (int d = 0; d < D; d++) begin
      if (!pwr_en[d] && !iso_en[d]) begin fails++; $display("FAIL d%0d: powered off without isolation", d); end
      if (!pwr_en[d] && clk_en[d]) begin fails++; $display("FAIL d%0d: clock running while off", d); end
      if (!pwr_en[d] && !ret_save[d]) begin fails++; $display("FAIL d%0d: powered off without retention", d); end
      if (clk_en[d] && iso_en[d]) begin fails++; $display("FAIL d%0d: clock on while isolated", d); end
    end

  task automatic chk(input bit ok, input string what);
    checks++; if (!ok) begin fails++; $display("FAIL %s", what); end
  endtask
  task automatic wreg(input logic [7:0] a, input logic [31:0] d);
    r_req = 1; r_we = 1; r_addr = a; r_wdata = d; @(negedge clk); r_req = 0; r_we = 0;
  endtask
  task automatic rreg(input logic [7:0] a, output logic [31:0] d);
    r_addr = a; #1; d = r_rdata;
  endtask

  // icg
  logic gclk, g_en = 0;
  icg u_icg (.clk(clk), .en(g_en), .test_en(1'b0), .gclk(gclk));
  int gcount = 0;
  always @(posedge gclk) gcount++;

  initial begin
    logic [31:0] d;
    repeat (2) @(negedge clk); rst_n = 1;
    repeat (10) @(negedge clk);
    rreg(8'h08, d); chk(d[3:0] == 4'hF, "all domains on after reset");
    chk(&clk_en && !(|iso_en) && &pwr_en && &dom_rst_n, "on-state outputs");
    // power down domain 2
    wreg(8'h00, 4'b1011);
    repeat (20) @(negedge clk);
    chk(!pwr_en[2] && iso_en[2] && ret_save[2] && !clk_en[2] && !dom_rst_n[2], "domain 2 off");
    chk(clk_en[0] && clk_en[1] && clk_en[3], "other domains unaffected");
    // power it back up
    wreg(8'h00, 4'b1111);
    repeat (20) @(negedge clk);
    rreg(8'h08, d); chk(d[2], "domain 2 back on");
    chk(clk_en[2] && !iso_en[2] && !ret_save[2] && dom_rst_n[2], "domain 2 restored");
    // switch-ack stuck high on power-down -> timeout error, domain stays isolated
    wreg(8'h18, 32);
    ack_stuck[1] = 1;
    wreg(8'h00, 4'b1101);
    repeat (60) @(negedge clk);
    chk(dom_err[1], "stuck switch ack raises domain error");
    chk(iso_en[1] && !clk_en[1], "errored domain stays isolated, clock off");
    ack_stuck[1] = 0;
    wreg(8'h0C, 4'b0010); repeat (5) @(negedge clk);
    chk(!dom_err[1], "error cleared");
    wreg(8'h00, 4'b1111); repeat (20) @(negedge clk);
    rreg(8'h08, d); chk(d[1], "domain 1 recovered after retry");
    // auto-idle on domain 3
    wreg(8'h10, 50); wreg(8'h04, 4'b1000);
    idle[3] = 1; repeat (40) @(negedge clk);
    rreg(8'h08, d); chk(d[3], "not yet idle long enough");
    repeat (30) @(negedge clk);
    rreg(8'h08, d); chk(!d[3], "auto-idle powered domain 3 down");
    idle[3] = 0; wreg(8'h04, 0); wreg(8'h00, 4'b1111); repeat (20) @(negedge clk);
    rreg(8'h08, d); chk(d[3], "domain 3 woken by request");
    // thermal throttle halves the NPU clock enable duty cycle
    begin
      int on_cnt;
      on_cnt = 0;
      wreg(8'h14, 2000); temp = 2500; repeat (3) @(negedge clk);
      chk(throttle, "throttle above threshold");
      for (int t = 0; t < 100; t++) begin @(negedge clk); on_cnt += clk_en[0]; end
      chk(on_cnt >= 45 && on_cnt <= 55, $sformatf("NPU clock enable duty ~50%% (%0d)", on_cnt));
      chk(&clk_en[3:1], "other domains not throttled");
      temp = 100; repeat (3) @(negedge clk); chk(!throttle && clk_en[0], "throttle released");
    end
    // ICG: gated clock pulses only while enabled, no glitch on enable change mid-high phase
    gcount = 0; repeat (10) @(negedge clk); chk(gcount == 0, "gated clock stopped");
    g_en = 1; repeat (10) @(negedge clk); chk(gcount == 10, $sformatf("gated clock runs (%0d)", gcount));
    @(posedge clk); #2 g_en = 0; @(negedge clk); chk(gcount == 11, "enable change in high phase does not glitch");
    $display("%0d checks, %0d failures", checks, fails);
    if (fails == 0) $display("ALL TESTS PASSED"); else $display("TESTS FAILED");
    $finish;
  end
endmodule
