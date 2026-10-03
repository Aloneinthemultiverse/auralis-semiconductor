// Systolic-array processing element for the edge-AI NPU.
// mode 0 = weight-stationary (weight held, partial sums flow south)
// mode 1 = output-stationary (weights stream south, sum accumulates here)
// prec16 0 = INT8 activation (a_in[7:0]), 1 = INT16 activation; weights are INT8.
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

  always_comb begin
    a_ext    = prec16 ? $signed(a_in) : $signed({{8{a_in[7]}}, a_in[7:0]});
    w_sel    = mode ? $signed(w_in) : w_stat;
    prod     = 32'(a_ext) * 32'(w_sel);
    acc_base = clear_acc ? 32'sd0 : acc;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      w_stat   <= '0;
      acc      <= '0;
      a_out    <= '0;
      w_out    <= '0;
      psum_out <= '0;
    end else if (en) begin
      a_out <= a_in;
      w_out <= w_in;
      if (w_load) w_stat <= $signed(w_in);
      if (!mode) begin
        psum_out <= psum_in + prod;
      end else begin
        acc      <= acc_base + prod;
        psum_out <= acc_base + prod;
      end
    end
  end
endmodule
