// R x C systolic array of npu_pe with built-in input skew and output de-skew.
// 64x64 at 1 GHz = 4096 MAC/cycle = 8.19 TOPS (INT8).
// mode 0 (WS): load weights with w_load (rows shifted in from the top, last row first, R cycles),
//              then stream A rows: a_row = A[m][0..R-1]; c_row = (A*W)[m][0..C-1] after R+C-1 cycles.
// mode 1 (OS): stream k = 0..K-1: a_row = A[0..R-1][k], w_row = W[k][0..C-1], os_first on k = 0;
//              acc_flat[(i*C+j)*32 +: 32] = C[i][j], final os_lat = R+C-1 cycles after the last k.
module npu_array #(parameter int R = 2, parameter int C = 2) (
  input  logic              clk,
  input  logic              rst_n,
  input  logic              en,
  input  logic              mode,
  input  logic              prec16,
  input  logic              w_load,
  input  logic [C*8-1:0]    w_row,
  input  logic              a_valid,
  input  logic [R*16-1:0]   a_row,
  input  logic              os_first,
  output logic              c_valid,
  output logic [C*32-1:0]   c_row,
  output logic [R*C*32-1:0] acc_flat
);
  // a/w/psum interconnect
  wire [R*(C+1)*16-1:0] a_h;  // a_h[((i)*(C+1)+(j))*16 +: 16] at ((i*(C+1))+j)*16
  wire [(R+1)*C*8-1:0]  w_v;  // w_v[((i)*C+(j))*8 +: 8] at (i*C+j)*8
  wire [(R+1)*C*32-1:0] p_v; // p_v[((i)*C+(j))*32 +: 32] at (i*C+j)*32
  wire [R*C-1:0]        clr; // clr[(i)*C+(j)] at i*C+j
  wire [C-1:0]            wl;

  genvar i, j;
  generate
    // row i: activations + OS first flag delayed i cycles (shift register of {flag, a})
    for (i = 0; i < R; i++) begin : g_in
      if (i == 0) begin : g_z
        assign a_h[((0)*(C+1)+(0))*16 +: 16] = a_row[15:0];
        assign clr[(0)*C+(0)] = os_first;
      end else begin : g_d
        logic [(i+1)*17-1:0] sr;  // stage d at [d*17 +: 17]
        always_ff @(posedge clk)
          if (!rst_n) sr <= '0;
          else if (en) sr <= {sr[i*17-1:0], os_first, a_row[i*16 +: 16]};
        assign {clr[(i)*C+(0)], a_h[((i)*(C+1)+(0))*16 +: 16]} = sr[i*17-1 -: 17];
      end
      // clear flag moves east with the activation
      for (j = 1; j < C; j++) begin : g_c
        logic r;
        always_ff @(posedge clk) if (!rst_n) r <= 1'b0; else if (en) r <= clr[(i)*C+(j-1)];
        assign clr[(i)*C+(j)] = r;
      end
    end
    // column j: weights + w_load delayed j cycles
    for (j = 0; j < C; j++) begin : g_win
      if (j == 0) begin : g_z
        assign w_v[((0)*C+(0))*8 +: 8] = w_row[7:0];
        assign wl[0]     = w_load;
      end else begin : g_d
        logic [(j+1)*9-1:0] sr;
        always_ff @(posedge clk)
          if (!rst_n) sr <= '0;
          else if (en) sr <= {sr[j*9-1:0], w_load, w_row[j*8 +: 8]};
        assign {wl[j], w_v[((0)*C+(j))*8 +: 8]} = sr[j*9-1 -: 9];
      end
      assign p_v[((0)*C+(j))*32 +: 32] = '0;
    end
    for (i = 0; i < R; i++) begin : g_row
      for (j = 0; j < C; j++) begin : g_col
        npu_pe pe (.clk(clk), .rst_n(rst_n), .en(en), .mode(mode), .prec16(prec16), .w_load(wl[j]),
                   .clear_acc(clr[(i)*C+(j)]), .a_in(a_h[((i)*(C+1)+(j))*16 +: 16]), .w_in(w_v[((i)*C+(j))*8 +: 8]), .psum_in(p_v[((i)*C+(j))*32 +: 32]),
                   .a_out(a_h[((i)*(C+1)+(j+1))*16 +: 16]), .w_out(w_v[((i+1)*C+(j))*8 +: 8]), .psum_out(p_v[((i+1)*C+(j))*32 +: 32]));
        assign acc_flat[(i*C+j)*32 +: 32] = p_v[((i+1)*C+(j))*32 +: 32];
      end
    end
    // output de-skew: column j delayed C-1-j cycles
    for (j = 0; j < C; j++) begin : g_out
      if (j == C - 1) begin : g_z
        assign c_row[j*32 +: 32] = p_v[((R)*C+(j))*32 +: 32];
      end else begin : g_d
        localparam int D = C - 1 - j;
        logic [(D+1)*32-1:0] sr;
        always_ff @(posedge clk)
          if (!rst_n) sr <= '0;
          else if (en) sr <= {sr[D*32-1:0], p_v[((R)*C+(j))*32 +: 32]};
        assign c_row[j*32 +: 32] = sr[D*32-1 -: 32];
      end
    end
  endgenerate

  // valid pipeline (R + C - 1 cycles)
  logic [R+C-2:0] vpipe;
  always_ff @(posedge clk)
    if (!rst_n) vpipe <= '0;
    else if (en) vpipe <= {vpipe[R+C-3:0], a_valid & ~mode};
  assign c_valid = vpipe[R+C-2];
endmodule
