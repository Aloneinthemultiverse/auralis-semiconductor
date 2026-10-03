// NPU core: tiled GEMM end-to-end through the register and buffer interface, RAW32 and INT8
// requant (round-half-up, zero point, ReLU, saturation), INT8 and INT16 activations, bad sizes.
module tb_npu_core;
  localparam int R = 4, C = 4;
  logic clk = 0, rst_n = 0;
  logic r_req = 0, r_we = 0; logic [7:0] r_addr = 0; logic [31:0] r_wdata = 0, r_rdata;
  logic h_req = 0, h_we = 0; logic [1:0] h_sel = 0; logic [15:0] h_addr = 0;
  logic [C*32-1:0] h_wdata = 0, h_rdata;
  logic irq;
  integer fails = 0, checks = 0;
  logic signed [15:0] A [32][64];
  logic signed [7:0]  W [64][32];

  npu_core #(.R(R), .C(C)) dut (.*);
  always #5 clk = ~clk;

  task automatic chk(input bit ok, input string what);
    checks++; if (!ok) begin fails++; $display("FAIL %s", what); end
  endtask
  task automatic wreg(input logic [7:0] a, input logic [31:0] d);
    r_req = 1; r_we = 1; r_addr = a; r_wdata = d; @(negedge clk); r_req = 0; r_we = 0;
  endtask
  task automatic hwr(input logic [1:0] s, input int a, input logic [C*32-1:0] d);
    h_req = 1; h_we = 1; h_sel = s; h_addr = a; h_wdata = d; @(negedge clk); h_req = 0; h_we = 0;
  endtask
  task automatic hrd(input int a, output logic [C*32-1:0] d);
    h_req = 1; h_we = 0; h_sel = 2; h_addr = a; @(negedge clk); h_req = 0; d = h_rdata;
  endtask

  function automatic logic signed [31:0] rq(input logic signed [31:0] acc, input logic signed [31:0] m,
                                           input int sh, input logic signed [7:0] z, input bit rl);
    logic signed [63:0] p, y;
    p = 64'(acc) * 64'(m);
    if (sh > 0) p = (p + (64'sd1 <<< (sh - 1))) >>> sh;
    y = p + 64'(z);
    if (rl && y < 64'(z)) y = 64'(z);
    if (y > 127) y = 127;
    if (y < -128) y = -128;
    return 32'(y);
  endfunction

  task automatic gemm(input int mt, input int nt, input int kk, input bit p16, input bit q, input bit rl,
                      input logic signed [31:0] m, input int sh, input logic signed [7:0] z);
    logic [C*32-1:0] d;
    logic signed [31:0] acc, expv;
    int c;
    for (int i = 0; i < mt*R; i++) for (int k = 0; k < kk; k++) begin
      logic [15:0] r16 = $urandom;
      A[i][k] = p16 ? $signed(r16) : $signed({{8{r16[7]}}, r16[7:0]});
    end
    for (int k = 0; k < kk; k++) for (int j = 0; j < nt*C; j++) W[k][j] = $urandom;
    for (int mi = 0; mi < mt; mi++) for (int k = 0; k < kk; k++) begin
      d = '0; for (int i = 0; i < R; i++) d[i*16 +: 16] = A[mi*R+i][k];
      hwr(0, mi*kk + k, d);
    end
    for (int nj = 0; nj < nt; nj++) for (int k = 0; k < kk; k++) begin
      d = '0; for (int j = 0; j < C; j++) d[j*8 +: 8] = W[k][nj*C+j];
      hwr(1, nj*kk + k, d);
    end
    wreg(8'h04, mt); wreg(8'h08, nt); wreg(8'h0C, kk); wreg(8'h10, {rl, q, p16});
    wreg(8'h14, m); wreg(8'h18, sh); wreg(8'h1C, 32'(z)); wreg(8'h00, 1);
    c = 0; while (!(r_addr == 0 && r_rdata[1]) && c < 100000) begin r_addr = 0; @(negedge clk); c++; end
    chk(r_rdata[2:0] == 3'b010, $sformatf("gemm %0dx%0dx%0d done ok", mt*R, nt*C, kk));
    r_addr = 8'h24; #1; chk(r_rdata == mt*nt, "tile counter");
    for (int mi = 0; mi < mt; mi++) for (int nj = 0; nj < nt; nj++) for (int i = 0; i < R; i++) begin
      hrd((mi*nt + nj)*R + i, d);
      for (int j = 0; j < C; j++) begin
        acc = 0;
        for (int k = 0; k < kk; k++) acc += 32'(A[mi*R+i][k]) * 32'(W[k][nj*C+j]);
        expv = q ? rq(acc, m, sh, z, rl) : acc;
        chk($signed(d[j*32 +: 32]) === expv,
            $sformatf("C[%0d][%0d] got %0d exp %0d (q=%0d p16=%0d)", mi*R+i, nj*C+j, $signed(d[j*32 +: 32]), expv, q, p16));
      end
    end
  endtask

  initial begin
    repeat (2) @(negedge clk); rst_n = 1;
    gemm(1, 1, 1, 0, 0, 0, 1, 0, 0);
    gemm(2, 3, 9, 0, 0, 0, 1, 0, 0);
    gemm(3, 2, 16, 1, 0, 0, 1, 0, 0);
    gemm(2, 2, 12, 0, 1, 0, 32'sd77, 12, 8'sd0);
    gemm(2, 2, 12, 0, 1, 1, 32'sd1500, 16, 8'sd5);
    gemm(2, 3, 7, 1, 1, 1, 32'sd3, 20, -8'sd10);
    gemm(1, 2, 20, 0, 1, 0, 32'sd9000, 8, 8'sd0);   // heavy saturation
    // a layer that does not fit the buffers is rejected
    wreg(8'h04, 200); wreg(8'h08, 1); wreg(8'h0C, 200); wreg(8'h00, 1);
    r_addr = 0; #1; chk(r_rdata[2:0] == 3'b110, "oversized layer flagged");
    $display("%0d checks, %0d failures", checks, fails);
    if (fails == 0) $display("ALL TESTS PASSED"); else $display("TESTS FAILED");
    $finish;
  end
endmodule
