module tb_npu_pe;
  logic clk = 0, rst_n = 0, en = 0, mode = 0, prec16 = 0, w_load = 0, clear_acc = 0;
  logic [15:0] a_in = 0;
  logic [7:0]  w_in = 0;
  logic [31:0] psum_in = 0;
  logic [15:0] a_out;
  logic [7:0]  w_out;
  logic [31:0] psum_out;
  integer fails = 0, checks = 0;
  logic [7:0] ws;
  logic signed [31:0] acc_ref, prev_ref;

  npu_pe dut(.clk(clk), .rst_n(rst_n), .en(en), .mode(mode), .prec16(prec16), .w_load(w_load),
             .clear_acc(clear_acc), .a_in(a_in), .w_in(w_in), .psum_in(psum_in),
             .a_out(a_out), .w_out(w_out), .psum_out(psum_out));
  always #5 clk = ~clk;

  function automatic logic signed [31:0] mul(input logic [15:0] a, input logic [7:0] w, input logic p16);
    logic signed [15:0] ae;
    logic signed [7:0]  we;
    ae = p16 ? $signed(a) : $signed({{8{a[7]}}, a[7:0]});
    we = $signed(w);
    mul = 32'(ae) * 32'(we);
  endfunction

  task automatic check(input logic [31:0] got, input logic [31:0] exp, input integer tag);
    checks = checks + 1;
    if (got !== exp) begin
      fails = fails + 1;
      $display("FAIL check %0d (tag %0d): got %0d expected %0d", checks, tag, $signed(got), $signed(exp));
    end
  endtask

  initial begin
    repeat (2) @(negedge clk);
    rst_n = 1; en = 1;
    // Weight-stationary: latch a weight, then psum_out = psum_in + a * w (INT8 and INT16).
    for (int i = 0; i < 200; i++) begin
      mode = 0; prec16 = i[0]; w_in = $urandom; w_load = 1;
      @(negedge clk);
      w_load = 0; ws = w_in;
      a_in = $urandom; psum_in = $urandom; w_in = $urandom;
      @(negedge clk); @(negedge clk); @(negedge clk);   // 3-stage pipeline: inputs held, result after 3 cycles
      check(psum_out, psum_in + mul(a_in, ws, prec16), 1);
    end
    // Output-stationary: weights stream in, 16-term dot products accumulate locally.
    for (int t = 0; t < 40; t++) begin
      mode = 1; prec16 = t[0];
      for (int k = 0; k < 16; k++) begin
        a_in = $urandom; w_in = $urandom; clear_acc = (k == 0);
        @(negedge clk);
        if (k > 1) check(psum_out, prev_ref, 2);      // result of step k-2 (two cycles behind)
        prev_ref = acc_ref;
        acc_ref = (k == 0 ? 32'sd0 : acc_ref) + mul(a_in, w_in, prec16);
      end
      a_in = 0; clear_acc = 0;                         // drain: adds 0
      @(negedge clk); @(negedge clk);
      check(psum_out, acc_ref, 2);
    end
    clear_acc = 0;
    // Extremes: most negative INT16 x most negative INT8.
    mode = 1; prec16 = 1; a_in = 16'h8000; w_in = 8'h80; clear_acc = 1;
    @(negedge clk); @(negedge clk); @(negedge clk);
    check(psum_out, 32'sd4194304, 3);
    // Systolic pass-through of activation and weight.
    clear_acc = 0; a_in = 16'hBEEF; w_in = 8'h5A;
    @(negedge clk);
    check({16'h0, a_out}, 32'h0000BEEF, 4);
    check({24'h0, w_out}, 32'h0000005A, 5);
    // Hold when disabled.
    en = 0; a_in = 16'h1234;
    @(negedge clk);
    check({16'h0, a_out}, 32'h0000BEEF, 6);
    if (fails == 0) begin
      $display("PASS all %0d checks (WS INT8/INT16, OS dot products, extremes, pass-through, enable)", checks);
      $display("ALL TESTS PASSED");
    end else begin
      $display("%0d of %0d checks failed", fails, checks);
    end
    $finish;
  end
endmodule
