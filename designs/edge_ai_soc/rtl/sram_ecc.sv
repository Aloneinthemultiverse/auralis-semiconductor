// ECC-protected SRAM bank: 64-bit data, SECDED(72,64) storage, 1-cycle read latency.
// Single errors are corrected on read and scrubbed (written back); double errors are flagged.
// Error events (corrected / uncorrectable + address) go to the SoC error aggregator.
// inj_mask XORs the stored codeword on a write (fault-injection for safety self-test).
// The 8 MB on-chip SRAM = 16 banks of 64K x 72 (bit-plane interleaved in layout).
module sram_ecc #(parameter int DEPTH = 1024, parameter int AW = $clog2(DEPTH)) (
  input  logic          clk,
  input  logic          rst_n,
  input  logic          req,
  input  logic          we,
  input  logic [AW-1:0] addr,
  input  logic [63:0]   wdata,
  input  logic [71:0]   inj_mask,
  output logic          rvalid,
  output logic [63:0]   rdata,
  output logic          err_corr,
  output logic          err_uncorr,
  output logic [AW-1:0] err_addr
);
  logic [71:0] enc, raw, fixed;
  logic [63:0] dec;
  logic        c1, u1;
  logic [AW-1:0] raddr;
  logic        rd;

  // storage through the foundry-mappable RAM wrapper: writes (host or scrub of a corrected word), reads
  logic          m_we;
  logic [AW-1:0] m_wa;
  logic [71:0]   m_wd;
  assign m_we = (req && we) || (rd && c1);
  assign m_wa = (req && we) ? addr : raddr;
  assign m_wd = (req && we) ? (enc ^ inj_mask) : fixed;
  ram_1r1w #(.W(72), .D(DEPTH)) u_mem (.clk(clk), .we(m_we), .waddr(m_wa), .wdata(m_wd),
                                       .re(req && !we), .raddr(addr), .rdata(raw));

  secded_enc u_enc (.d(wdata), .cw(enc));
  secded_dec u_dec (.cw(raw), .d(dec), .cw_fixed(fixed), .corrected(c1), .uncorrectable(u1));

  always_ff @(posedge clk) begin

  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      rd <= 1'b0; raddr <= '0;
    end else begin
      rd    <= req && !we;
      raddr <= addr;
    end
  end

  assign rvalid     = rd;
  assign rdata      = dec;
  assign err_corr   = rd & c1;
  assign err_uncorr = rd & u1;
  assign err_addr   = raddr;
endmodule
