// CSI-2 over 4 D-PHY lanes: frames of RAW8 lines with per-lane bit offsets, header ECC correction
// and detection, payload CRC, frame counting.
module tb_csi2;
  localparam int L = 4;
  logic clk = 0, rst_n = 0, hs = 0;
  logic [L*8-1:0] raw = '0;
  logic pkt_start, pkt_end, crc_err, ecc_corrected, ecc_err;
  logic [1:0] vc; logic [5:0] dt; logic [15:0] wc, frames;
  logic [L-1:0] pv; logic [L*8-1:0] pix;
  integer fails = 0, checks = 0;
  csi2_rx #(.L(L)) dut (.clk(clk), .rst_n(rst_n), .hs_active(hs), .lane_raw(raw), .pkt_start(pkt_start), .vc(vc),
    .dt(dt), .wc(wc), .pix_valid(pv), .pix(pix), .pkt_end(pkt_end), .crc_err(crc_err),
    .ecc_corrected(ecc_corrected), .ecc_err(ecc_err), .frames(frames));
  always #5 clk = ~clk;

  task automatic chk(input bit ok, input string what);
    checks++; if (!ok) begin fails++; $display("FAIL %s", what); end
  endtask

  function automatic logic [5:0] ecc6(input logic [23:0] d);
    logic [23:0] m [6];
    m[0] = 24'hF12CB7; m[1] = 24'hF2555B; m[2] = 24'h749A6D; m[3] = 24'hB8E38E; m[4] = 24'hDF03F0; m[5] = 24'hEFFC00;
    for (int p = 0; p < 6; p++) ecc6[p] = ^(d & m[p]);
  endfunction
  logic [7:0] pay [256];        // payload of the packet being sent
  int         pay_len;
  function automatic logic [15:0] crc16(input int n);
    logic [15:0] c;
    c = 16'hFFFF;
    for (int k = 0; k < n; k++) begin
      c = c ^ {8'd0, pay[k]};
      for (int i = 0; i < 8; i++) c = c[0] ? ((c >> 1) ^ 16'h8408) : (c >> 1);
    end
    return c;
  endfunction

  // received payload capture
  logic [7:0] got [$];
  always @(posedge clk) for (int i = 0; i < L; i++) if (pv[i]) got.push_back(pix[i*8 +: 8]);
  int n_start = 0, n_end = 0, n_crc = 0, n_corr = 0, n_eccerr = 0;
  always @(posedge clk) begin
    n_start = n_start + pkt_start; n_end = n_end + pkt_end; n_crc = n_crc + crc_err; n_corr = n_corr + ecc_corrected; n_eccerr = n_eccerr + ecc_err;
  end

  function automatic int off(input int l);   // per-lane bit skew
    return (l == 0) ? 0 : (l == 1) ? 3 : (l == 2) ? 5 : 7;
  endfunction

  // transmit one packet as one HS burst: per lane HS-zero, sync 0xB8, bytes, trail; LSB first, offset bits
  logic [7:0] bytes [300];
  bit         lanes [L*4096];
  int         llen [L];
  task automatic send(input logic [5:0] dtp, input logic [15:0] wcp, input logic [23:0] hdr_flip, input int pay_flip);
    logic [23:0] h;
    logic [15:0] c;
    int nb, nby;
    h = {wcp, 2'b00, dtp};
    bytes[0] = h[7:0]; bytes[1] = h[15:8]; bytes[2] = h[23:16]; bytes[3] = {2'b00, ecc6(h)};
    for (int b = 0; b < 3; b++) bytes[b] = bytes[b] ^ hdr_flip[b*8 +: 8];
    nby = 4;
    if (dtp >= 6'h10) begin
      c = crc16(pay_len);
      for (int k = 0; k < pay_len; k++) begin bytes[nby] = (k == pay_flip) ? pay[k] ^ 8'h10 : pay[k]; nby = nby + 1; end
      bytes[nby] = c[7:0]; bytes[nby + 1] = c[15:8]; nby = nby + 2;
    end
    while (nby % L) begin bytes[nby] = 8'h00; nby = nby + 1; end
    nb = 0;
    for (int l = 0; l < L; l++) begin
      llen[l] = 0;
      for (int z = 0; z < 16 + off(l); z++) begin lanes[l*4096 + llen[l]] = 1'b0; llen[l] = llen[l] + 1; end
      for (int i = 0; i < 8; i++) begin lanes[l*4096 + llen[l]] = (8'hB8 >> i) & 1; llen[l] = llen[l] + 1; end
      for (int k = l; k < nby; k += L)
        for (int i = 0; i < 8; i++) begin lanes[l*4096 + llen[l]] = bytes[k][i]; llen[l] = llen[l] + 1; end
      for (int z = 0; z < 32; z++) begin lanes[l*4096 + llen[l]] = ~bytes[nby - L + l][7]; llen[l] = llen[l] + 1; end
      if (llen[l] > nb) nb = llen[l];
    end
    hs = 1;
    for (int w = 0; w < nb / 8; w++) begin
      for (int l = 0; l < L; l++)
        for (int i = 0; i < 8; i++) raw[l*8 + i] = (w*8 + i < llen[l]) ? lanes[l*4096 + w*8 + i] : 1'b0;
      @(negedge clk);
    end
    hs = 0; repeat (4) @(negedge clk);
  endtask

  logic [7:0] all_sent [4096];
  int         n_sent;
  initial begin
    repeat (3) @(negedge clk); rst_n = 1;
    // CRC reference check value (CRC-16/MCRF4XX of "123456789" = 0x6F91)
    for (int k = 0; k < 9; k++) pay[k] = 8'h31 + 8'(k);
    chk(crc16(9) == 16'h6F91, "CRC-16 check value");
    n_sent = 0;
    for (int f = 0; f < 3; f++) begin
      send(6'h00, 16'(f), 0, -1);                                          // frame start
      for (int y = 0; y < 6; y++) begin
        pay_len = $urandom_range(8, 64);
        for (int k = 0; k < pay_len; k++) begin pay[k] = 8'($urandom); all_sent[n_sent] = pay[k]; n_sent = n_sent + 1; end
        send(6'h2A, 16'(pay_len), 0, -1);                                  // RAW8 line
      end
      send(6'h01, 16'(f), 0, -1);                                          // frame end
    end
    chk(frames == 3, $sformatf("3 frames received (%0d)", frames));
    chk(n_start == 24 && n_end == 18, $sformatf("24 packets, 18 long (%0d, %0d)", n_start, n_end));
    chk(n_crc == 0 && n_corr == 0 && n_eccerr == 0, "clean link: no CRC/ECC events");
    chk(got.size() == n_sent, $sformatf("payload bytes %0d / %0d", got.size(), n_sent));
    begin
      int bad;
      bad = -1;
      for (int k = 0; k < n_sent && k < got.size(); k++) if (bad < 0 && got[k] !== all_sent[k]) bad = k;
      chk(bad < 0, $sformatf("all pixels match (first mismatch %0d)", bad));
    end
    // error injection
    pay_len = 20;
    for (int k = 0; k < 20; k++) pay[k] = 8'($urandom);
    for (int b = 0; b < 24; b += 5) begin
      got.delete();
      send(6'h2A, 16'd20, 24'(1) << b, -1);
    end
    chk(n_corr == 5 && n_eccerr == 0, $sformatf("single-bit header errors corrected (%0d)", n_corr));
    chk(got.size() == 20, "packet with a corrected header still delivered");
    send(6'h2A, 16'd20, 24'h000201, -1);
    chk(n_eccerr == 1, "double-bit header error detected, packet dropped");
    send(6'h2A, 16'd20, 0, 7);
    chk(n_crc == 1, "payload bit error caught by CRC");
    $display("%0d checks, %0d failures", checks, fails);
    if (fails == 0) $display("ALL TESTS PASSED"); else $display("TESTS FAILED");
    $finish;
  end
endmodule
