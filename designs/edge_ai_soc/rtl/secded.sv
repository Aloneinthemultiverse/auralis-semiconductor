// Extended Hamming SECDED (72,64): Hamming positions 1..71, check bits at powers of two
// (1,2,4,...,64), data at the other 64 positions; bit 0 of the codeword is overall parity.
module secded_enc (
  input  logic [63:0] d,
  output logic [71:0] cw
);
  always_comb begin
    logic [71:0] c;
    int k;
    c = '0;
    k = 0;
    for (int p = 1; p < 72; p++)
      if ((p & (p - 1)) != 0) begin c[p] = d[k]; k++; end
    for (int b = 0; b < 7; b++) begin
      logic x;
      x = 1'b0;
      for (int p = 1; p < 72; p++) if (((p >> b) & 1) == 1 && p != (1 << b)) x ^= c[p];
      c[1 << b] = x;
    end
    c[0] = ^c[71:1];
    cw = c;
  end
endmodule

module secded_dec (
  input  logic [71:0] cw,
  output logic [63:0] d,
  output logic [71:0] cw_fixed,
  output logic        corrected,
  output logic        uncorrectable
);
  always_comb begin
    logic [6:0]  syn;
    logic        par;
    logic [71:0] c;
    int k;
    for (int b = 0; b < 7; b++) begin
      logic x;
      x = 1'b0;
      for (int p = 1; p < 72; p++) if (((p >> b) & 1) == 1) x ^= cw[p];
      syn[b] = x;
    end
    par = ^cw;
    c = cw;
    corrected = 1'b0;
    uncorrectable = 1'b0;
    if (par) begin              // odd number of flips: single error at position syn (0 = parity bit)
      c[syn] = ~c[syn];
      corrected = 1'b1;
    end else if (syn != 0) begin // even flips with nonzero syndrome: double error
      uncorrectable = 1'b1;
    end
    k = 0;
    d = '0;
    for (int p = 1; p < 72; p++)
      if ((p & (p - 1)) != 0) begin d[k] = c[p]; k++; end
    cw_fixed = c;
  end
endmodule
