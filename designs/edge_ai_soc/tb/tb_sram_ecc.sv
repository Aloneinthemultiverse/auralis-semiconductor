module tb_sram_ecc;
  localparam int DEPTH = 64, AW = 6;
  logic clk = 0, rst_n = 0, req = 0, we = 0;
  logic [AW-1:0] addr = 0;
  logic [63:0] wdata = 0;
  logic [71:0] inj_mask = 0;
  logic rvalid, err_corr, err_uncorr;
  logic [63:0] rdata;
  logic [AW-1:0] err_addr;
  logic [63:0] ref_d [DEPTH];
  integer fails = 0, checks = 0;
  sram_ecc #(.DEPTH(DEPTH)) dut (.*);
  always #5 clk = ~clk;

  task automatic chk(input bit ok, input string what);
    checks++;
    if (!ok) begin fails++; $display("FAIL %s", what); end
  endtask

  task automatic wr(input int a, input logic [63:0] d, input logic [71:0] m);
    req = 1; we = 1; addr = a; wdata = d; inj_mask = m; @(negedge clk);
    req = 0; we = 0; inj_mask = 0;
  endtask

  task automatic rd(input int a, output logic [63:0] d, output logic c, output logic u);
    req = 1; we = 0; addr = a; @(negedge clk);
    req = 0;
    chk(rvalid === 1'b1, "rvalid");
    d = rdata; c = err_corr; u = err_uncorr;
    if (c || u) chk(err_addr === a[AW-1:0], "err_addr");
    @(negedge clk);   // allow scrub write-back
  endtask

  initial begin
    logic [63:0] d; logic c, u;
    int b1, b2;
    repeat (2) @(negedge clk); rst_n = 1;
    // clean write/read
    for (int a = 0; a < DEPTH; a++) begin ref_d[a] = {$urandom, $urandom}; wr(a, ref_d[a], '0); end
    for (int a = 0; a < DEPTH; a++) begin
      rd(a, d, c, u);
      chk(d === ref_d[a] && !c && !u, $sformatf("clean read a=%0d", a));
    end
    // every single-bit position is corrected, then scrubbed
    for (int b = 0; b < 72; b++) begin
      ref_d[0] = {$urandom, $urandom};
      wr(0, ref_d[0], 72'(1) << b);
      rd(0, d, c, u);
      chk(d === ref_d[0] && c && !u, $sformatf("single-bit %0d corrected", b));
      rd(0, d, c, u);
      chk(d === ref_d[0] && !c && !u, $sformatf("single-bit %0d scrubbed", b));
    end
    // random double-bit errors are detected
    for (int t = 0; t < 300; t++) begin
      b1 = $urandom_range(0, 71);
      do b2 = $urandom_range(0, 71); while (b2 == b1);
      ref_d[1] = {$urandom, $urandom};
      wr(1, ref_d[1], (72'(1) << b1) | (72'(1) << b2));
      rd(1, d, c, u);
      chk(u && !c, $sformatf("double-bit %0d,%0d detected", b1, b2));
    end
    $display("%0d checks, %0d failures", checks, fails);
    if (fails == 0) $display("ALL TESTS PASSED"); else $display("TESTS FAILED");
    $finish;
  end
endmodule
