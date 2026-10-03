module tb_npu_array;
  localparam int R = 4, C = 4, M = 12, K = 7;
  logic clk = 0, rst_n = 0, en = 1, mode = 0, prec16 = 0, w_load = 0, a_valid = 0, os_first = 0;
  logic [C*8-1:0] w_row = '0;
  logic [R*16-1:0] a_row = '0;
  logic c_valid;
  logic [C*32-1:0] c_row;
  logic [R*C*32-1:0] acc_flat;
  integer fails = 0, checks = 0, got_rows;
  logic signed [15:0] A [64][64];
  logic signed [7:0]  W [64][64];
  logic signed [31:0] ref_c;

  npu_array #(.R(R), .C(C)) dut (.*);
  always #5 clk = ~clk;

  function automatic logic signed [15:0] act(input logic p16);
    logic [15:0] r = $urandom;
    return p16 ? $signed(r) : $signed({{8{r[7]}}, r[7:0]});
  endfunction

  task automatic run_ws(input logic p16);
    prec16 = p16; mode = 0;
    for (int k = 0; k < R; k++) for (int j = 0; j < C; j++) W[k][j] = $urandom;
    for (int m = 0; m < M; m++) for (int k = 0; k < R; k++) A[m][k] = act(p16);
    // weight load: last row first, R cycles (+C-1 for column skew to settle)
    for (int s = 0; s < R; s++) begin
      w_load = 1;
      for (int j = 0; j < C; j++) w_row[j*8 +: 8] = W[R-1-s][j];
      @(negedge clk);
    end
    w_load = 0; w_row = '0;
    got_rows = 0;
    fork
      begin
        for (int m = 0; m < M; m++) begin
          a_valid = 1;
          for (int k = 0; k < R; k++) a_row[k*16 +: 16] = A[m][k];
          @(negedge clk);
        end
        a_valid = 0;
      end
      begin
        while (got_rows < M) begin
          @(posedge clk); #1;
          if (c_valid) begin
            for (int j = 0; j < C; j++) begin
              ref_c = 0;
              for (int k = 0; k < R; k++) ref_c += 32'(A[got_rows][k]) * 32'(W[k][j]);
              checks++;
              if ($signed(c_row[j*32 +: 32]) !== ref_c) begin
                fails++; $display("FAIL WS m=%0d j=%0d got %0d exp %0d", got_rows, j, $signed(c_row[j*32 +: 32]), ref_c);
              end
            end
            got_rows++;
          end
        end
      end
    join
    @(negedge clk);
  endtask

  task automatic run_os(input logic p16);
    prec16 = p16; mode = 1;
    for (int i = 0; i < R; i++) for (int k = 0; k < K; k++) A[i][k] = act(p16);
    for (int k = 0; k < K; k++) for (int j = 0; j < C; j++) W[k][j] = $urandom;
    for (int k = 0; k < K; k++) begin
      os_first = (k == 0);
      for (int i = 0; i < R; i++) a_row[i*16 +: 16] = A[i][k];
      for (int j = 0; j < C; j++) w_row[j*8 +: 8] = W[k][j];
      @(negedge clk);
    end
    os_first = 0; a_row = '0; w_row = '0;
    repeat (R + C - 1) @(negedge clk);   // R+C-2 fill/drain + 1 PE pipeline stage
    for (int i = 0; i < R; i++) for (int j = 0; j < C; j++) begin
      ref_c = 0;
      for (int k = 0; k < K; k++) ref_c += 32'(A[i][k]) * 32'(W[k][j]);
      checks++;
      if ($signed(acc_flat[(i*C+j)*32 +: 32]) !== ref_c) begin
        fails++; $display("FAIL OS i=%0d j=%0d got %0d exp %0d", i, j, $signed(acc_flat[(i*C+j)*32 +: 32]), ref_c);
      end
    end
  endtask

  initial begin
    repeat (2) @(negedge clk); rst_n = 1;
    for (int t = 0; t < 6; t++) begin run_ws(t[0]); run_os(t[0]); end
    $display("%0d checks, %0d failures", checks, fails);
    if (fails == 0) $display("ALL TESTS PASSED"); else $display("TESTS FAILED");
    $finish;
  end
  initial begin #200000; $display("FAIL timeout"); $finish; end
endmodule
