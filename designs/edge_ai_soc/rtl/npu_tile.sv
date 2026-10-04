// NPU tile for SKY130 hardening: 4x4 systolic array + tiling controller + requantization
// (npu_core with 16-entry scratch buffers). The production chip uses R = C = 64.
module npu_tile (
  input  logic          clk,
  input  logic          rst_n,
  input  logic          r_req,
  input  logic          r_we,
  input  logic [7:0]    r_addr,
  input  logic [31:0]   r_wdata,
  output logic [31:0]   r_rdata,
  input  logic          h_req,
  input  logic          h_we,
  input  logic [1:0]    h_sel,
  input  logic [15:0]   h_addr,
  input  logic [127:0]  h_wdata,
  output logic [127:0]  h_rdata,
  output logic          irq
);
  npu_core #(.R(4), .C(4), .ADEPTH(16), .WDEPTH(16), .CDEPTH(16)) u_core (.*);
endmodule
