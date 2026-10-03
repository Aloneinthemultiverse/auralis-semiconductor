// MIPI CSI-2 receiver (digital) behind a 4-lane D-PHY. The D-PHY HS receiver front end (LP/HS
// detection, termination, clock lane, deserializer) is analog/mixed-signal; this starts at its
// per-lane byte output (bytes with an unknown bit offset while hs_active).

// D-PHY lane: lock the bit offset on the SoT sync byte 0xB8 (00011101 on the wire, LSB first)
// and deliver aligned bytes until HS ends.
module dphy_lane_align (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       hs_active,
  input  logic [7:0] raw,          // LSB = earliest bit
  output logic       valid,
  output logic [7:0] data
);
  logic [15:0] win;
  logic [2:0]  off;
  logic        synced;
  logic        found;
  logic [2:0]  hit;
  always_comb begin
    found = 1'b0; hit = '0;
    for (int o = 0; o < 8; o++)
      if (!found && win[o +: 8] == 8'hB8) begin found = 1'b1; hit = 3'(o); end
  end
  always_ff @(posedge clk) begin
    if (!rst_n || !hs_active) begin
      win <= '0; off <= '0; synced <= 1'b0; valid <= 1'b0; data <= '0;
    end else begin
      win <= {raw, win[15:8]};
      valid <= 1'b0;
      if (!synced) begin
        if (found) begin synced <= 1'b1; off <= hit; end
      end else begin
        valid <= 1'b1; data <= win[4'(off) +: 8];
      end
    end
  end
endmodule

// CSI-2 packet layer (one packet per HS burst, as on the wire: SoT, packet, EoT). With L = 4 lanes
// the first aligned beat is the 4-byte header (byte k on lane k): DI {VC, DT}, WC LSB, WC MSB, ECC.
// The header ECC (6 bits over 24) corrects single-bit and detects double-bit errors. Long packets
// (DT >= 0x10) carry WC payload bytes, L per cycle, then a CRC-16 (x^16+x^12+x^5+1, LSB first,
// init 0xFFFF). Short packets (DT < 0x10: frame/line start/end) carry a 16-bit data field in WC.
module csi2_rx #(parameter int L = 4) (
  input  logic           clk,
  input  logic           rst_n,
  input  logic           hs_active,
  input  logic [L*8-1:0] lane_raw,
  output logic           pkt_start,      // header accepted (pulse)
  output logic [1:0]     vc,
  output logic [5:0]     dt,
  output logic [15:0]    wc,             // word count (long) or data field (short)
  output logic [L-1:0]   pix_valid,      // payload bytes this cycle (byte i = lane i order)
  output logic [L*8-1:0] pix,
  output logic           pkt_end,        // long packet finished, CRC checked (pulse)
  output logic           crc_err,
  output logic           ecc_corrected,
  output logic           ecc_err,
  output logic [15:0]    frames
);
  // per-lane alignment + deskew FIFO: lanes may find SoT one byte-clock apart; a beat is formed
  // only when every lane has a byte
  logic [L-1:0]   av, fne;
  logic [L*8-1:0] ad, ld;
  logic [L-1:0]   lv;
  logic           pop;
  assign pop = &fne;
  for (genvar i = 0; i < L; i++) begin : g_lane
    logic [7:0] q [4];
    logic [1:0] wp, rp;
    logic [2:0] n;
    dphy_lane_align u_al (.clk(clk), .rst_n(rst_n), .hs_active(hs_active), .raw(lane_raw[i*8 +: 8]),
                          .valid(av[i]), .data(ad[i*8 +: 8]));
    always_ff @(posedge clk) begin
      if (!rst_n || !hs_active) begin wp <= '0; rp <= '0; n <= '0; end
      else begin
        if (av[i]) begin q[wp] <= ad[i*8 +: 8]; wp <= wp + 1; end
        if (pop) rp <= rp + 1;
        n <= n + 3'(av[i]) - 3'(pop);
      end
    end
    assign fne[i] = (n != 0);
    assign ld[i*8 +: 8] = q[rp];
    assign lv[i] = pop;
  end

  // header ECC: parity equations P0..P5 over D0..D23 (CSI-2), P7:P6 = 0
  function automatic logic [5:0] ecc6(input logic [23:0] d);
    ecc6[0] = d[0]^d[1]^d[2]^d[4]^d[5]^d[7]^d[10]^d[11]^d[13]^d[16]^d[20]^d[21]^d[22]^d[23];
    ecc6[1] = d[0]^d[1]^d[3]^d[4]^d[6]^d[8]^d[10]^d[12]^d[14]^d[17]^d[20]^d[21]^d[22]^d[23];
    ecc6[2] = d[0]^d[2]^d[3]^d[5]^d[6]^d[9]^d[11]^d[12]^d[15]^d[18]^d[20]^d[21]^d[22];
    ecc6[3] = d[1]^d[2]^d[3]^d[7]^d[8]^d[9]^d[13]^d[14]^d[15]^d[19]^d[20]^d[21]^d[23];
    ecc6[4] = d[4]^d[5]^d[6]^d[7]^d[8]^d[9]^d[16]^d[17]^d[18]^d[19]^d[20]^d[22]^d[23];
    ecc6[5] = d[10]^d[11]^d[12]^d[13]^d[14]^d[15]^d[16]^d[17]^d[18]^d[19]^d[21]^d[22]^d[23];
  endfunction

  function automatic logic [15:0] crc_byte(input logic [15:0] c, input logic [7:0] b);
    logic [15:0] x;
    x = c ^ {8'd0, b};
    for (int i = 0; i < 8; i++) x = x[0] ? ((x >> 1) ^ 16'h8408) : (x >> 1);
    crc_byte = x;
  endfunction

  // header decode of the current beat (used when it is the first beat of the burst)
  logic [23:0] hdr, hfix;
  logic [5:0]  syn;
  logic        hcorr, herr, hitc;
  always_comb begin
    hdr  = ld[23:0];
    syn  = ecc6(hdr) ^ ld[29:24];
    hfix = hdr; hcorr = 1'b0; herr = 1'b0; hitc = 1'b0;
    if (syn != 0 || ld[31:30] != 2'b00) begin
      for (int b = 0; b < 24; b++)
        if (ecc6(24'(1) << b) == syn) begin hfix[b] = ~hfix[b]; hitc = 1'b1; end
      if (!hitc && (syn == 6'd1 || syn == 6'd2 || syn == 6'd4 || syn == 6'd8 || syn == 6'd16 || syn == 6'd32))
        hitc = 1'b1;                                       // a parity bit flipped
      hcorr = hitc;
      herr  = !hitc;
    end
  end

  localparam logic [1:0] S_HDR = 2'd0, S_PAY = 2'd1, S_SKIP = 2'd2;
  logic [1:0]  st;
  logic [16:0] pos;            // byte index after the header
  logic [15:0] crc, rx_crc;
  logic [15:0] len;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      st <= S_HDR; pos <= '0; crc <= 16'hFFFF; rx_crc <= '0; len <= '0;
      pkt_start <= 1'b0; vc <= '0; dt <= '0; wc <= '0; pix_valid <= '0; pix <= '0; pkt_end <= 1'b0;
      crc_err <= 1'b0; ecc_corrected <= 1'b0; ecc_err <= 1'b0; frames <= '0;
    end else begin
      pkt_start <= 1'b0; pkt_end <= 1'b0; crc_err <= 1'b0; ecc_corrected <= 1'b0; ecc_err <= 1'b0;
      pix_valid <= '0;
      if (!hs_active) st <= S_HDR;
      else if (&lv) begin
        case (st)
          S_HDR: begin
                   ecc_corrected <= hcorr; ecc_err <= herr;
                   if (herr) st <= S_SKIP;                         // drop the packet
                   else begin
                     pkt_start <= 1'b1; vc <= hfix[7:6]; dt <= hfix[5:0]; wc <= hfix[23:8];
                     if (hfix[5:0] < 6'h10) begin
                       if (hfix[5:0] == 6'h01) frames <= frames + 1; // frame end
                       st <= S_SKIP;
                     end else begin
                       len <= hfix[23:8]; pos <= '0; crc <= 16'hFFFF; st <= S_PAY;
                     end
                   end
                 end
          S_PAY: begin
                   logic [15:0] c;
                   logic [15:0] r;
                   logic        fin;
                   c = crc; r = rx_crc; fin = 1'b0;
                   for (int i = 0; i < L; i++) begin
                     logic [16:0] p;
                     logic [7:0]  b;
                     p = pos + 17'(i);
                     b = ld[i*8 +: 8];
                     if (p < 17'(len)) begin
                       pix_valid[i] <= 1'b1; pix[i*8 +: 8] <= b;
                       c = crc_byte(c, b);
                     end else if (p == 17'(len)) r[7:0] = b;
                     else if (p == 17'(len) + 1) begin r[15:8] = b; fin = 1'b1; end
                   end
                   crc <= c; rx_crc <= r; pos <= pos + 17'(L);
                   if (fin) begin pkt_end <= 1'b1; crc_err <= (r != c); st <= S_SKIP; end
                 end
          default: ;                                               // S_SKIP: wait for EoT
        endcase
      end
    end
  end
endmodule
