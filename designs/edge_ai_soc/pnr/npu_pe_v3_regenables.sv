// Systolic-array processing element for the edge-AI NPU.
// mode 0 = weight-stationary (weight held, partial sums flow south)
// mode 1 = output-stationary (weights stream south, sum accumulates here)
// prec16 0 = INT8 activation (a_in[7:0]), 1 = INT16 activation; weights are INT8.
// Two-stage pipeline for 1 GHz: multiply -> prod_q register -> accumulate. psum_out appears 2 cycles
// after a_in; the row above's psum arrives exactly when prod_q is ready, so array skew is unchanged.
// Power (P&R showed ~2.5 pJ/cycle/PE at 28 nm): register enables let synthesis insert clock gates -
//  * zero-operand isolation: a zero activation or weight holds the multiplier inputs at 0 and does
//    not clock prod_q (a zero flag is pipelined instead) - ReLU outputs are often >50 % zero
//  * INT8 mode does not clock the upper activation byte; WS mode does not clock the weight
//    pass-through (except while loading) nor the OS accumulator
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
  logic signed [15:0] a_ext;
  logic signed [7:0]  w_sel;
  logic signed [31:0] prod;
  logic signed [31:0] acc_base;
  logic signed [31:0] prod_q;
  logic               clr_q, mode_q, zero, zero_q;
  logic signed [31:0] prod_eff;

  always_comb begin
    a_ext    = prec16 ? $signed(a_in) : $signed({{8{a_in[7]}}, a_in[7:0]});
    w_sel    = mode ? $signed(w_in) : w_stat;
    zero     = (a_ext == 16'sd0) || (w_sel == 8'sd0);
    prod     = zero ? 32'sd0 : 32'(a_ext) * 32'(w_sel);     // operand isolation
    prod_eff = zero_q ? 32'sd0 : prod_q;
    acc_base = clr_q ? 32'sd0 : acc;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      w_stat   <= '0;
      acc      <= '0;
      a_out    <= '0;
      w_out    <= '0;
      psum_out <= '0;
      prod_q   <= '0;
      clr_q    <= 1'b0;
      mode_q   <= 1'b0;
      zero_q   <= 1'b1;
    end else if (en) begin
      if (!zero) prod_q <= prod;                       // not clocked for zero operands
      zero_q <= zero;
      clr_q  <= clear_acc;
      mode_q <= mode;
      a_out[7:0] <= a_in[7:0];
      if (prec16) a_out[15:8] <= a_in[15:8];           // upper byte idle in INT8 mode
      if (mode || w_load) w_out <= w_in;               // weights only flow in OS mode / while loading
      if (w_load) w_stat <= $signed(w_in);
      if (!mode_q) begin
        psum_out <= psum_in + prod_eff;
      end else begin
        acc      <= acc_base + prod_eff;
        psum_out <= acc_base + prod_eff;
      end
    end
  end
endmodule
