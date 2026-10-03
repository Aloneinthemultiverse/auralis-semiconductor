// Workload for power analysis: INT8 output-stationary MACs at 1 GHz, 50 % zero activations (post-ReLU),
// random weights; dumps a VCD of the PE for OpenSTA activity annotation.
`timescale 1ns/1ps
module tb_pe_power;
  logic clk = 0, rst_n = 0, en = 1, mode = 1, prec16 = 0, w_load = 0, clear_acc = 0;
  logic [15:0] a_in = 0; logic [7:0] w_in = 0; logic [31:0] psum_in = 0;
  logic [15:0] a_out; logic [7:0] w_out; logic [31:0] psum_out;
  npu_pe dut (.*);
  always #0.5 clk = ~clk;
  initial begin
    $dumpfile("pe.vcd"); $dumpvars(0, tb_pe_power.dut);
    repeat (3) @(negedge clk); rst_n = 1;
    for (int c = 0; c < 4000; c++) begin
      a_in = ($urandom_range(0, 1) == 0) ? 16'h0 : {8'h0, 8'($urandom_range(1, 127))};
      w_in = $urandom; clear_acc = (c % 64 == 0);
      @(negedge clk);
    end
    $finish;
  end
endmodule
