// Two USB 3.0 link-layer ports over a lossy link: header packets both ways, every HP delivered once,
// in order, intact; LBAD/retry recovery; credit flow control.
module tb_usb3;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  logic a_hv = 0, a_hr, a_rv, b_hv = 0, b_hr, b_rv;
  logic [127:0] a_hd = 0, b_hd = 0, a_rd, b_rd;
  logic [8:0] a_tx, b_tx, a_rx, b_rx;
  logic [15:0] a_rt, a_lb, b_rt, b_lb;
  int err_rate = 0;
  usb3_link u_a (.clk(clk), .rst_n(rst_n), .h_valid(a_hv), .h_data(a_hd), .h_ready(a_hr), .r_valid(a_rv), .r_data(a_rd),
                 .tx_sym(a_tx), .rx_sym(a_rx), .retries(a_rt), .lbad_sent(a_lb));
  usb3_link u_b (.clk(clk), .rst_n(rst_n), .h_valid(b_hv), .h_data(b_hd), .h_ready(b_hr), .r_valid(b_rv), .r_data(b_rd),
                 .tx_sym(b_tx), .rx_sym(b_rx), .retries(b_rt), .lbad_sent(b_lb));
  always @(posedge clk) begin
    b_rx <= (!a_tx[8] && $urandom_range(0, 999) < err_rate) ? {1'b0, a_tx[7:0] ^ 8'h44} : a_tx;
    a_rx <= (!b_tx[8] && $urandom_range(0, 999) < err_rate) ? {1'b0, b_tx[7:0] ^ 8'h44} : b_tx;
  end
  integer fails = 0, checks = 0;
  task automatic chk(input bit ok, input string what);
    checks++; if (!ok) begin fails++; $display("FAIL %s", what); end
  endtask
  logic [127:0] eab [1024]; int nab = 0, rab = 0, bab = 0;
  logic [127:0] eba [1024]; int nba = 0, rba = 0, bba = 0;
  always @(posedge clk) begin
    if (b_rv) begin if (rab >= nab || eab[rab] !== b_rd) bab = bab + 1; rab = rab + 1; end
    if (a_rv) begin if (rba >= nba || eba[rba] !== a_rd) bba = bba + 1; rba = rba + 1; end
  end
  task automatic send_a(input int n);
    for (int t = 0; t < n; t++) begin
      a_hv = 1; a_hd = {$urandom, $urandom, $urandom, $urandom};
      @(posedge clk); while (!a_hr) @(posedge clk);
      eab[nab] = a_hd; nab = nab + 1; #1;
    end
    a_hv = 0;
  endtask
  task automatic send_b(input int n);
    for (int t = 0; t < n; t++) begin
      b_hv = 1; b_hd = {$urandom, $urandom, $urandom, $urandom};
      @(posedge clk); while (!b_hr) @(posedge clk);
      eba[nba] = b_hd; nba = nba + 1; #1;
    end
    b_hv = 0;
  endtask
  initial begin
    repeat (3) @(negedge clk); rst_n = 1;
    fork send_a(60); send_b(40); join
    repeat (2000) @(negedge clk);
    chk(rab == nab && bab == 0 && rba == nba && bba == 0, $sformatf("clean: %0d/%0d and %0d/%0d HPs", rab, nab, rba, nba));
    chk(a_rt == 0 && b_rt == 0, "clean link: no retries");
    err_rate = 4;
    fork send_a(200); send_b(150); join
    err_rate = 0;
    repeat (20000) @(negedge clk);
    chk(rab == nab && bab == 0, $sformatf("lossy A->B %0d/%0d HPs in order, %0d bad", rab, nab, bab));
    chk(rba == nba && bba == 0, $sformatf("lossy B->A %0d/%0d HPs in order, %0d bad", rba, nba, bba));
    chk(a_lb + b_lb > 0 && a_rt + b_rt > 0, $sformatf("recovered: LBAD %0d/%0d retries %0d/%0d", a_lb, b_lb, a_rt, b_rt));
    $display("%0d checks, %0d failures", checks, fails);
    if (fails == 0) $display("ALL TESTS PASSED"); else $display("TESTS FAILED");
    $finish;
  end
endmodule
