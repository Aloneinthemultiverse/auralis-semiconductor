// Watchdog + error aggregator + reset synchronizer.
module tb_safety;
  logic clk = 0, arst_n = 0, rst_n;
  logic w_req = 0, w_we = 0; logic [7:0] w_addr = 0; logic [31:0] w_wdata = 0, w_rdata;
  logic e_req = 0, e_we = 0; logic [7:0] e_addr = 0; logic [31:0] e_wdata = 0, e_rdata;
  logic bark, bite, irq, fatal;
  logic [15:0] fault = 0;
  integer fails = 0, checks = 0;

  rst_sync rs (.clk(clk), .arst_n(arst_n), .rst_n(rst_n));
  watchdog wd (.clk(clk), .rst_n(rst_n), .r_req(w_req), .r_we(w_we), .r_addr(w_addr), .r_wdata(w_wdata),
               .r_rdata(w_rdata), .bark(bark), .bite(bite));
  err_agg #(.N(16), .FATAL_MASK(16'h8002)) ea (.clk(clk), .rst_n(rst_n), .fault(fault), .r_req(e_req),
               .r_we(e_we), .r_addr(e_addr), .r_wdata(e_wdata), .r_rdata(e_rdata), .irq(irq), .fatal(fatal));
  always #5 clk = ~clk;

  task automatic chk(input bit ok, input string what);
    checks++; if (!ok) begin fails++; $display("FAIL %s", what); end
  endtask
  task automatic wd_w(input logic [7:0] a, input logic [31:0] d);
    w_req = 1; w_we = 1; w_addr = a; w_wdata = d; @(negedge clk); w_req = 0; w_we = 0;
  endtask
  task automatic ea_w(input logic [7:0] a, input logic [31:0] d);
    e_req = 1; e_we = 1; e_addr = a; e_wdata = d; @(negedge clk); e_req = 0; e_we = 0;
  endtask
  task automatic ea_r(input logic [7:0] a, output logic [31:0] d);
    e_addr = a; #1; d = e_rdata;
  endtask
  task automatic pulse(input int k);
    fault[k] = 1; @(negedge clk); fault[k] = 0;
  endtask

  initial begin
    logic [31:0] d;
    // reset synchronizer: async assert, 2-cycle synchronous release
    @(negedge clk); chk(rst_n === 1'b0, "reset held");
    arst_n = 1; @(negedge clk); chk(rst_n === 1'b0, "release cycle 1");
    @(negedge clk); chk(rst_n === 1'b1, "released after 2 flops");
    #2 arst_n = 0; #1 chk(rst_n === 1'b0, "asynchronous assert"); arst_n = 1;
    repeat (3) @(negedge clk);

    // ---- watchdog ----
    wd_w(8'h04, 100); wd_w(8'h08, 40); wd_w(8'h00, 1);
    // valid kicks inside the window keep it quiet
    for (int t = 0; t < 5; t++) begin
      repeat (70) @(negedge clk);
      wd_w(8'h0C, 32'h5AFE);
      chk(!bark && !bite, $sformatf("in-window kick %0d accepted", t));
    end
    // early kick (outside window) -> bark
    repeat (5) @(negedge clk); wd_w(8'h0C, 32'h5AFE);
    chk(bark, "early kick barks");
    wd_w(8'h10, 1); chk(!bark, "bark cleared");
    // wrong key -> bark
    repeat (80) @(negedge clk); wd_w(8'h0C, 32'h1234); chk(bark, "wrong key barks");
    wd_w(8'h10, 1);
    // no kick: first expiry bark, second expiry bite
    repeat (102) @(negedge clk); chk(bark && !bite, "first expiry barks");
    repeat (102) @(negedge clk); chk(bite, "second expiry bites");
    // lock: cannot disable
    arst_n = 0; @(negedge clk); arst_n = 1; repeat (3) @(negedge clk);
    chk(!bite && !bark, "reset clears watchdog");
    wd_w(8'h04, 50); wd_w(8'h08, 50); wd_w(8'h00, 3); wd_w(8'h00, 0);
    w_addr = 8'h00; #1; chk(w_rdata[1:0] == 2'b11, "locked watchdog cannot be disabled");
    wd_w(8'h04, 9999); w_addr = 8'h04; #1; chk(w_rdata == 50, "locked LOAD not writable");
    arst_n = 0; @(negedge clk); arst_n = 1; repeat (3) @(negedge clk);

    // ---- error aggregator ----
    ea_w(8'h04, 16'h0010);              // mask source 4
    pulse(4); ea_r(8'h00, d); chk(d[4] && !irq, "masked source sticky but no irq");
    pulse(7); pulse(3);
    ea_r(8'h00, d); chk(d[7] && d[3] && irq, "sticky status + irq");
    ea_r(8'h08, d); chk(d[8] && d[7:0] == 7, "first fault is source 7 (root cause kept)");
    ea_r(8'h10, d); chk(d == 3, "non-fatal event count");
    chk(!fatal, "no fatal yet");
    ea_w(8'h00, 32'h0098); ea_r(8'h00, d); chk(d[15:0] == 0 && !irq, "W1C clears status");
    ea_w(8'h14, 1); ea_r(8'h08, d); chk(!d[8], "first-fault latch cleared");
    pulse(1); chk(fatal, "fatal source (uncorrectable ECC) raises fatal");
    ea_r(8'h08, d); chk(d[7:0] == 1, "first fault after clear is source 1");
    // simultaneous faults: lowest id wins the first-fault latch
    ea_w(8'h00, 32'hFFFF); ea_w(8'h14, 1);
    fault = 16'h0420; @(negedge clk); fault = 0;
    ea_r(8'h08, d); chk(d[7:0] == 5, "simultaneous faults: lowest id latched");
    $display("%0d checks, %0d failures", checks, fails);
    if (fails == 0) $display("ALL TESTS PASSED"); else $display("TESTS FAILED");
    $finish;
  end
endmodule
