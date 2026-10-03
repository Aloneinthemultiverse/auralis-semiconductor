// Systolic-array processing element for the edge-AI NPU.
// mode 0 = weight-stationary (weight held, partial sums flow south)
// mode 1 = output-stationary (weights stream south, sum accumulates here)
// prec16 0 = INT8 activation (a_in[7:0]), 1 = INT16 activation; weights are INT8.
// Three-stage pipeline for 1 GHz and low power: operand registers -> multiply -> prod_q -> accumulate.
// psum_out appears 3 cycles after a_in; the row above's psum arrives exactly when this PE's product
// is ready, so the array skew is unchanged.
// Power (measured with VCD-annotated P&R power: the multiplier is ~78 % of PE power): when either
// operand is zero the operand registers HOLD, so the multiplier does not switch, and a pipelined
// zero flag replaces the product with 0. (Gating only the registers after the multiplier was
// measured to cost +9 %: the multiplier still switched.)
module npu_pe (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        en,
  input  logic        mode,
  input  logic        prec16,
  input  logic        w_load,
  input  logic        clear_acc,
  input  logic [15:0] a_in,
  input  logic [7:0]  w_in,
  input  logic [31:0] psum_in,
  output logic [15:0] a_out,
  output logic [7:0]  w_out,
  output logic [31:0] psum_out
);
  logic signed [7:0]  w_stat;
  logic signed [31:0] acc;
  logic signed [15:0] a_ext, op_a;
  logic signed [7:0]  w_sel, op_w;
  logic signed [31:0] prod_q, prod_eff, acc_base;
  logic               zero, zero1, zero2;
  logic               clr1, clr2, mode1, mode2;

  always_comb begin
    a_ext    = prec16 ? $signed(a_in) : $signed({{8{a_in[7]}}, a_in[7:0]});
    w_sel    = mode ? $signed(w_in) : w_stat;
    zero     = (a_ext == 16'sd0) || (w_sel == 8'sd0);
    prod_eff = zero2 ? 32'sd0 : prod_q;
    acc_base = clr2 ? 32'sd0 : acc;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      w_stat <= '0; acc <= '0; a_out <= '0; w_out <= '0; psum_out <= '0;
      op_a <= '0; op_w <= '0; prod_q <= '0;
      zero1 <= 1'b1; zero2 <= 1'b1; clr1 <= 1'b0; clr2 <= 1'b0; mode1 <= 1'b0; mode2 <= 1'b0;
    end else if (en) begin
      // stage 1: operands (held on zero -> multiplier inputs stay still)
      if (!zero) begin op_a <= a_ext; op_w <= w_sel; end
      zero1 <= zero; clr1 <= clear_acc; mode1 <= mode;
      // stage 2: multiply
      prod_q <= 32'(op_a) * 32'(op_w);
      zero2 <= zero1; clr2 <= clr1; mode2 <= mode1;
      // stage 3: accumulate
      if (!mode2) psum_out <= psum_in + prod_eff;
      else begin
        acc      <= acc_base + prod_eff;
        psum_out <= acc_base + prod_eff;
      end
      // systolic pass-through
      a_out <= a_in;
      w_out <= w_in;
      if (w_load) w_stat <= $signed(w_in);
    end
  end
endmodule
