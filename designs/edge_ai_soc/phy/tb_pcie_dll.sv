// Two PCIe DLL ports over a lossy link: random TLPs both ways, symbol corruption in both directions;
// every TLP must arrive exactly once, in order, intact (ACK/NAK + replay + duplicate discard).
module tb_pcie_dll;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  logic a_tv = 0, a_tl = 0, a_tr, a_rv, a_rl, b_tv = 0, b_tl = 0, b_tr, b_rv, b_rl;
  logic [7:0] a_td = 0, b_td = 0, a_rd, b_rd;
  logic [8:0] a_tx, b_tx, a_rx, b_rx;
  logic [15:0] a_rep, a_nak, a_dup, b_rep, b_nak, b_dup;
  int err_rate = 0;          // per-mille symbol corruption
  pcie_dll u_a (.clk(clk), .rst_n(rst_n), .t_valid(a_tv), .t_data(a_td), .t_last(a_tl), .t_ready(a_tr),
    .r_valid(a_rv), .r_data(a_rd), .r_last(a_rl), .tx_sym(a_tx), .rx_sym(a_rx), .replays(a_rep), .naks_sent(a_nak), .dup_dropped(a_dup));
  pcie_dll u_b (.clk(clk), .rst_n(rst_n), .t_valid(b_tv), .t_data(b_td), .t_last(b_tl), .t_ready(b_tr),
    .r_valid(b_rv), .r_data(b_rd), .r_last(b_rl), .tx_sym(b_tx), .rx_sym(b_rx), .replays(b_rep), .naks_sent(b_nak), .dup_dropped(b_dup));
  // channel: corrupt data symbols (not framing) with probability err_rate/1000
  always @(posedge clk) begin
    b_rx <= (!a_tx[8] && $urandom_range(0, 999) < err_rate) ? {1'b0, a_tx[7:0] ^ 8'h21} : a_tx;
    a_rx <= (!b_tx[8] && $urandom_range(0, 999) < err_rate) ? {1'b0, b_tx[7:0] ^ 8'h12} : b_tx;
  end
  integer fails = 0, checks = 0;
  task automatic chk(input bit ok, input string what);
    checks++; if (!ok) begin fails++; $display("FAIL %s", what); end
  endtask
  // expected streams (bytes with TLP boundaries)
  logic [8:0] exp_ab [8192]; int n_ab = 0, r_ab = 0;
  logic [8:0] exp_ba [8192]; int n_ba = 0, r_ba = 0;
  int bad_ab = 0, bad_ba = 0;
  always @(posedge clk) begin
    if (b_rv) begin if (r_ab >= n_ab || exp_ab[r_ab] !== {b_rl, b_rd}) bad_ab = bad_ab + 1; r_ab = r_ab + 1; end
    if (a_rv) begin if (r_ba >= n_ba || exp_ba[r_ba] !== {a_rl, a_rd}) bad_ba = bad_ba + 1; r_ba = r_ba + 1; end
  end
  task automatic send_a(input int len);
    for (int k = 0; k < len; k++) begin
      a_tv = 1; a_td = $urandom; a_tl = (k == len - 1);
      @(posedge clk); while (!a_tr) @(posedge clk);
      exp_ab[n_ab] = {a_tl, a_td}; n_ab = n_ab + 1;
      #1;
    end
    a_tv = 0; a_tl = 0;
  endtask
  task automatic send_b(input int len);
    for (int k = 0; k < len; k++) begin
      b_tv = 1; b_td = $urandom; b_tl = (k == len - 1);
      @(posedge clk); while (!b_tr) @(posedge clk);
      exp_ba[n_ba] = {b_tl, b_td}; n_ba = n_ba + 1;
      #1;
    end
    b_tv = 0; b_tl = 0;
  endtask
  initial begin
    repeat (3) @(negedge clk); rst_n = 1;
    // clean link
    fork
      for (int t = 0; t < 40; t++) send_a($urandom_range(1, 32));
      for (int t = 0; t < 30; t++) send_b($urandom_range(1, 32));
    join
    repeat (3000) @(negedge clk);
    chk(r_ab == n_ab && bad_ab == 0 && r_ba == n_ba && bad_ba == 0, $sformatf("clean: A->B %0d/%0d B->A %0d/%0d bytes", r_ab, n_ab, r_ba, n_ba));
    chk(a_rep == 0 && b_rep == 0, "clean link: no replays");
    // lossy link: 0.5 % symbol corruption both ways
    err_rate = 5;
    fork
      for (int t = 0; t < 120; t++) send_a($urandom_range(1, 32));
      for (int t = 0; t < 100; t++) send_b($urandom_range(1, 32));
    join
    err_rate = 0;
    repeat (20000) @(negedge clk);
    chk(r_ab == n_ab && bad_ab == 0, $sformatf("lossy A->B: %0d/%0d bytes delivered in order, %0d bad", r_ab, n_ab, bad_ab));
    chk(r_ba == n_ba && bad_ba == 0, $sformatf("lossy B->A: %0d/%0d bytes delivered in order, %0d bad", r_ba, n_ba, bad_ba));
    chk(b_nak + a_nak > 0 && a_rep + b_rep > 0, $sformatf("errors recovered: NAKs %0d/%0d replays %0d/%0d dup-dropped %0d/%0d", a_nak, b_nak, a_rep, b_rep, a_dup, b_dup));
    $display("%0d checks, %0d failures", checks, fails);
    if (fails == 0) $display("ALL TESTS PASSED"); else $display("TESTS FAILED");
    $finish;
  end
endmodule
