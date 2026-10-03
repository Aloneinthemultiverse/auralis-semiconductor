// Ethernet MAC TX -> RX loopback: random frames 1..120 bytes, padding, FCS, corrupted frame detection.
module tb_eth;
  logic clk = 0, rst_n = 0;
  logic s_valid = 0, s_last = 0, s_ready, tx_en, m_valid, frame_done, fcs_err;
  logic [7:0] s_data = 0, txd, m_data;
  logic [15:0] good, bad;
  logic corrupt = 0;
  logic [7:0] rxd;
  eth_mac_tx u_tx (.clk(clk), .rst_n(rst_n), .s_valid(s_valid), .s_data(s_data), .s_last(s_last), .s_ready(s_ready),
                   .tx_en(tx_en), .txd(txd));
  assign rxd = corrupt ? txd ^ 8'h04 : txd;
  eth_mac_rx u_rx (.clk(clk), .rst_n(rst_n), .rx_dv(tx_en), .rxd(rxd), .m_valid(m_valid), .m_data(m_data),
                   .frame_done(frame_done), .fcs_err(fcs_err), .good_frames(good), .bad_frames(bad));
  always #5 clk = ~clk;
  integer fails = 0, checks = 0;
  task automatic chk(input bit ok, input string what);
    checks++; if (!ok) begin fails++; $display("FAIL %s", what); end
  endtask
  logic [7:0] sent [200]; int n_sent, n_got; logic [7:0] got [200];
  always @(posedge clk) if (m_valid) begin got[n_got] = m_data; n_got = n_got + 1; end
  function automatic logic [31:0] crc32(input int n);
    logic [31:0] c;
    c = '1;
    for (int k = 0; k < n; k++) begin
      c = c ^ {24'd0, sent[k]};
      for (int i = 0; i < 8; i++) c = c[0] ? ((c >> 1) ^ 32'hEDB88320) : (c >> 1);
    end
    crc32 = ~c;
  endfunction
  task automatic frame(input int len, input bit bad_one);
    n_got = 0; n_sent = len;
    for (int k = 0; k < len; k++) sent[k] = 8'($urandom);
    for (int k = len; k < 60; k++) sent[k] = 8'h00;
    @(negedge clk);
    for (int k = 0; k < len; k++) begin
      s_valid = 1; s_data = sent[k]; s_last = (k == len - 1);
      @(posedge clk); while (!s_ready) @(posedge clk);
      #1;
      if (bad_one && k == len / 2) corrupt = 1; else corrupt = 0;
    end
    s_valid = 0; s_last = 0;
    @(negedge clk); corrupt = 0;
    while (!frame_done) @(negedge clk);
    chk(fcs_err == bad_one, $sformatf("len %0d FCS %s", len, bad_one ? "error detected" : "ok"));
    if (!bad_one) begin
      int m, bad;
      m = (len < 60) ? 60 : len; bad = 0;
      chk(n_got == m, $sformatf("len %0d delivered %0d bytes (padded %0d)", len, n_got, m));
      for (int k = 0; k < m && k < n_got; k++) if (got[k] !== sent[k]) bad = bad + 1;
      chk(bad == 0, $sformatf("len %0d payload/padding bytes match", len));
    end
    repeat (20) @(negedge clk);
  endtask
  initial begin
    for (int k = 0; k < 9; k++) sent[k] = 8'h31 + 8'(k);
    chk(crc32(9) == 32'hCBF43926, "CRC-32 check value (zlib.crc32('123456789'))");
    repeat (3) @(negedge clk); rst_n = 1;
    for (int t = 0; t < 30; t++) frame($urandom_range(1, 120), 0);
    frame(64, 1); frame(10, 1);
    chk(good == 30 && bad == 2, $sformatf("counters good %0d bad %0d", good, bad));
    $display("%0d checks, %0d failures", checks, fails);
    if (fails == 0) $display("ALL TESTS PASSED"); else $display("TESTS FAILED");
    $finish;
  end
endmodule
