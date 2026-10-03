// SHA-256 compression core (FIPS 180-4): one 512-bit block, 64 rounds at 1 round/cycle.
// init=1 with start begins a new message (H = IV); otherwise chains from the previous digest.
module sha256 (
  input  logic         clk,
  input  logic         rst_n,
  input  logic         start,
  input  logic         init,
  input  logic [511:0] block,     // word 0 in [511:480] (big-endian)
  output logic         busy,
  output logic         done,      // one-cycle pulse when the block is absorbed
  output logic [255:0] digest     // H0 in [255:224]
);
  function automatic logic [31:0] k_of(input logic [5:0] i);
    case (i)
      6'd0: k_of = 32'h428a2f98; 6'd1: k_of = 32'h71374491; 6'd2: k_of = 32'hb5c0fbcf; 6'd3: k_of = 32'he9b5dba5;
      6'd4: k_of = 32'h3956c25b; 6'd5: k_of = 32'h59f111f1; 6'd6: k_of = 32'h923f82a4; 6'd7: k_of = 32'hab1c5ed5;
      6'd8: k_of = 32'hd807aa98; 6'd9: k_of = 32'h12835b01; 6'd10: k_of = 32'h243185be; 6'd11: k_of = 32'h550c7dc3;
      6'd12: k_of = 32'h72be5d74; 6'd13: k_of = 32'h80deb1fe; 6'd14: k_of = 32'h9bdc06a7; 6'd15: k_of = 32'hc19bf174;
      6'd16: k_of = 32'he49b69c1; 6'd17: k_of = 32'hefbe4786; 6'd18: k_of = 32'h0fc19dc6; 6'd19: k_of = 32'h240ca1cc;
      6'd20: k_of = 32'h2de92c6f; 6'd21: k_of = 32'h4a7484aa; 6'd22: k_of = 32'h5cb0a9dc; 6'd23: k_of = 32'h76f988da;
      6'd24: k_of = 32'h983e5152; 6'd25: k_of = 32'ha831c66d; 6'd26: k_of = 32'hb00327c8; 6'd27: k_of = 32'hbf597fc7;
      6'd28: k_of = 32'hc6e00bf3; 6'd29: k_of = 32'hd5a79147; 6'd30: k_of = 32'h06ca6351; 6'd31: k_of = 32'h14292967;
      6'd32: k_of = 32'h27b70a85; 6'd33: k_of = 32'h2e1b2138; 6'd34: k_of = 32'h4d2c6dfc; 6'd35: k_of = 32'h53380d13;
      6'd36: k_of = 32'h650a7354; 6'd37: k_of = 32'h766a0abb; 6'd38: k_of = 32'h81c2c92e; 6'd39: k_of = 32'h92722c85;
      6'd40: k_of = 32'ha2bfe8a1; 6'd41: k_of = 32'ha81a664b; 6'd42: k_of = 32'hc24b8b70; 6'd43: k_of = 32'hc76c51a3;
      6'd44: k_of = 32'hd192e819; 6'd45: k_of = 32'hd6990624; 6'd46: k_of = 32'hf40e3585; 6'd47: k_of = 32'h106aa070;
      6'd48: k_of = 32'h19a4c116; 6'd49: k_of = 32'h1e376c08; 6'd50: k_of = 32'h2748774c; 6'd51: k_of = 32'h34b0bcb5;
      6'd52: k_of = 32'h391c0cb3; 6'd53: k_of = 32'h4ed8aa4a; 6'd54: k_of = 32'h5b9cca4f; 6'd55: k_of = 32'h682e6ff3;
      6'd56: k_of = 32'h748f82ee; 6'd57: k_of = 32'h78a5636f; 6'd58: k_of = 32'h84c87814; 6'd59: k_of = 32'h8cc70208;
      6'd60: k_of = 32'h90befffa; 6'd61: k_of = 32'ha4506ceb; 6'd62: k_of = 32'hbef9a3f7; default: k_of = 32'hc67178f2;
    endcase
  endfunction

  function automatic logic [31:0] rotr(input logic [31:0] x, input int n);
    rotr = (x >> n) | (x << (32 - n));
  endfunction

  localparam logic [255:0] IV = {32'h6a09e667, 32'hbb67ae85, 32'h3c6ef372, 32'ha54ff53a,
                                 32'h510e527f, 32'h9b05688c, 32'h1f83d9ab, 32'h5be0cd19};

  logic [511:0] w;          // sliding window: w[511:480] = W[t]
  logic [255:0] h, st;      // chaining value, working state a..h
  logic [5:0]   t;
  logic [31:0]  a, b, c, d, e, f, g, hh, t1, t2, s0, s1, wnew;

  always_comb begin
    {a, b, c, d, e, f, g, hh} = st;
    t1 = hh + (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) + ((e & f) ^ (~e & g)) + k_of(t) + w[511:480];
    t2 = (rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) + ((a & b) ^ (a & c) ^ (b & c));
    // W[t+16] = s1(W[t+14]) + W[t+9] + s0(W[t+1]) + W[t]
    s0   = rotr(w[479:448], 7) ^ rotr(w[479:448], 18) ^ (w[479:448] >> 3);
    s1   = rotr(w[63:32], 17) ^ rotr(w[63:32], 19) ^ (w[63:32] >> 10);
    wnew = s1 + w[223:192] + s0 + w[511:480];
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      busy <= 1'b0; done <= 1'b0; t <= '0; w <= '0; h <= IV; st <= '0;
    end else begin
      done <= 1'b0;
      if (start && !busy) begin
        busy <= 1'b1; t <= '0; w <= block;
        if (init) begin h <= IV; st <= IV; end else st <= h;
      end else if (busy) begin
        st <= {t1 + t2, a, b, c, d + t1, e, f, g};
        w  <= {w[479:0], wnew};
        t  <= t + 1;
        if (t == 6'd63) begin
          busy <= 1'b0;
          done <= 1'b1;
          h <= {h[255:224] + t1 + t2, h[223:192] + a, h[191:160] + b, h[159:128] + c,
                h[127:96] + d + t1, h[95:64] + e, h[63:32] + f, h[31:0] + g};
        end
      end
    end
  end

  assign digest = h;
endmodule
