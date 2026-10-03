// Secure-boot root of trust. Out of reset the application CPUs are held in reset while this
// controller reads the stage-1 image from boot flash over its bus master, hashes it with the
// hardware SHA-256 (padding generated in hardware) and compares the digest with the value
// fused in OTP (constant-time compare). Anti-rollback: the image version must be >= the
// OTP minimum version. Only on success is cpu_rst_n released; the decision is one-way until
// the next power-on reset. On failure the CPUs stay in reset and boot_fail goes to err_agg.
// Image layout at img_base: word 0 = {version[31:0], nwords[31:0]}, then nwords payload words;
// the hash covers the header and payload (64-bit words, big-endian bytes).
module secure_boot #(parameter int MAX_WORDS = 1 << 20) (
  input  logic         clk,
  input  logic         rst_n,
  input  logic [31:0]  img_base,
  input  logic [255:0] otp_digest,
  input  logic [31:0]  otp_min_version,
  output logic         m_req,
  output logic [31:0]  m_addr,
  input  logic         m_gnt,
  input  logic         m_rvalid,
  input  logic [63:0]  m_rdata,
  input  logic         m_err,
  output logic         cpu_rst_n,
  output logic         boot_ok,
  output logic         boot_fail,
  output logic [255:0] measured   // digest exposed for measured boot / attestation
);
  localparam logic [2:0] S_HDR = 3'd0, S_FILL = 3'd1, S_HASH = 3'd2, S_CHECK = 3'd3, S_OK = 3'd4, S_FAIL = 3'd5;
  logic [2:0]   st;
  logic [31:0]  n, k, total, version;   // n = message words (header + payload)
  logic [511:0] blk;
  logic [2:0]   slot;
  logic         first_blk, wait_r, sha_start, sha_busy, sha_done;
  logic [255:0] dig;
  logic [63:0]  word;
  logic         need_mem;
  logic         eq;

  sha256 u_sha (.clk(clk), .rst_n(rst_n), .start(sha_start), .init(first_blk), .block(blk),
                .busy(sha_busy), .done(sha_done), .digest(dig));

  // padded message word k: message, then 0x80.., zeros, and the bit length as the last word
  assign need_mem = (k < n);
  always_comb begin
    if (k == n)               word = 64'h8000_0000_0000_0000;
    else if (k == total - 1)  word = {26'd0, n, 6'd0};   // n*64 bits
    else                      word = '0;
  end

  // constant-time comparison: OR-reduce of XOR, no early exit
  assign eq = ~|(dig ^ otp_digest);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      st <= S_HDR; n <= '0; k <= '0; total <= '0; version <= '0; blk <= '0; slot <= '0;
      first_blk <= 1'b1; wait_r <= 1'b0; sha_start <= 1'b0;
      cpu_rst_n <= 1'b0; boot_ok <= 1'b0; boot_fail <= 1'b0;
    end else begin
      sha_start <= 1'b0;
      case (st)
        S_HDR: if (!wait_r) begin
                 if (m_gnt) wait_r <= 1'b1;
               end else if (m_rvalid) begin
                 wait_r <= 1'b0;
                 if (m_err || m_rdata[31:0] >= 32'(MAX_WORDS)) st <= S_FAIL;
                 else begin
                   version <= m_rdata[63:32];
                   n       <= m_rdata[31:0] + 1;
                   total   <= ((m_rdata[31:0] + 1 + 2 + 7) >> 3) << 3;  // ceil((n+2)/8)*8
                   blk     <= {448'd0, m_rdata};
                   slot    <= 3'd1;
                   k       <= 32'd1;
                   st      <= S_FILL;
                 end
               end
        S_FILL: begin
                 if (need_mem) begin
                   if (!wait_r) begin
                     if (m_gnt) wait_r <= 1'b1;
                   end else if (m_rvalid) begin
                     wait_r <= 1'b0;
                     if (m_err) st <= S_FAIL;
                     else begin
                       blk <= {blk[447:0], m_rdata}; slot <= slot + 1; k <= k + 1;
                       if (slot == 3'd7) begin sha_start <= 1'b1; st <= S_HASH; end
                     end
                   end
                 end else begin
                   blk <= {blk[447:0], word}; slot <= slot + 1; k <= k + 1;
                   if (slot == 3'd7) begin sha_start <= 1'b1; st <= S_HASH; end
                 end
               end
        S_HASH: if (sha_done) begin
                  first_blk <= 1'b0;
                  st <= (k == total) ? S_CHECK : S_FILL;
                end
        S_CHECK: st <= (eq && version >= otp_min_version) ? S_OK : S_FAIL;
        S_OK:   begin cpu_rst_n <= 1'b1; boot_ok <= 1'b1; end
        S_FAIL: begin cpu_rst_n <= 1'b0; boot_fail <= 1'b1; end
        default: st <= S_FAIL;   // illegal state (glitch): fail closed
      endcase
    end
  end

  assign m_req    = ((st == S_HDR) || (st == S_FILL && need_mem)) && !wait_r;
  assign m_addr   = img_base + (k << 3);
  assign measured = dig;
endmodule
