// LPDDR4 subsystem: controller + PHY (training) + timing-checking DRAM model.
module tb_lpddr4;
  logic clk = 0, rst_n = 0;
  logic req = 0, we = 0, gnt, rvalid; logic [31:0] addr = 0; logic [63:0] wdata = 0, rdata;
  logic dfi_cmd_valid, dfi_train_req, dfi_train_done, dfi_rddata_valid, init_done;
  logic [2:0] dfi_cmd, dfi_bank; logic [13:0] dfi_row; logic [9:0] dfi_col; logic [15:0] dfi_mrw;
  logic [63:0] dfi_wrdata, dfi_rddata; logic [3:0] dfi_wrbeat;
  logic [31:0] hits, misses, refs;
  logic d_cmd_valid, d_wr_valid, d_rd_valid; logic [3:0] d_cmd; logic [2:0] d_bank; logic [13:0] d_row;
  logic [9:0] d_col; logic [15:0] d_mrw; logic [63:0] d_wr_data, d_rd_data; logic [7:0] d_wr_dm;
  logic [47:0] eye_lo, taps; logic [7:0] lane_ok, mr2;
  int violations, dram_refs;
  integer fails = 0, checks = 0;

  lpddr4_ctrl u_ctrl (.clk(clk), .rst_n(rst_n), .req(req), .we(we), .addr(addr), .wdata(wdata), .gnt(gnt),
    .rvalid(rvalid), .rdata(rdata), .dfi_cmd_valid(dfi_cmd_valid), .dfi_cmd(dfi_cmd), .dfi_bank(dfi_bank),
    .dfi_row(dfi_row), .dfi_col(dfi_col), .dfi_mrw(dfi_mrw), .dfi_wrdata(dfi_wrdata), .dfi_wrbeat(dfi_wrbeat),
    .dfi_train_req(dfi_train_req), .dfi_train_done(dfi_train_done), .dfi_rddata_valid(dfi_rddata_valid),
    .dfi_rddata(dfi_rddata), .init_done(init_done), .stat_hits(hits), .stat_misses(misses), .stat_refreshes(refs));
  lpddr4_phy u_phy (.clk(clk), .rst_n(rst_n), .dfi_cmd_valid(dfi_cmd_valid), .dfi_cmd(dfi_cmd), .dfi_bank(dfi_bank),
    .dfi_row(dfi_row), .dfi_col(dfi_col), .dfi_mrw(dfi_mrw), .dfi_wrdata(dfi_wrdata), .dfi_wrbeat(dfi_wrbeat),
    .dfi_train_req(dfi_train_req), .dfi_train_done(dfi_train_done), .dfi_rddata_valid(dfi_rddata_valid),
    .dfi_rddata(dfi_rddata), .d_cmd_valid(d_cmd_valid), .d_cmd(d_cmd), .d_bank(d_bank), .d_row(d_row),
    .d_col(d_col), .d_mrw(d_mrw), .d_wr_valid(d_wr_valid), .d_wr_data(d_wr_data), .d_wr_dm(d_wr_dm),
    .d_rd_valid(d_rd_valid), .d_rd_data(d_rd_data), .eye_lo(eye_lo), .taps(taps), .lane_ok(lane_ok));
  lpddr4_dram_model u_dram (.clk(clk), .rst_n(rst_n), .d_cmd_valid(d_cmd_valid), .d_cmd(d_cmd), .d_bank(d_bank),
    .d_row(d_row), .d_col(d_col), .d_mrw(d_mrw), .d_wr_valid(d_wr_valid), .d_wr_data(d_wr_data), .d_wr_dm(d_wr_dm),
    .d_rd_valid(d_rd_valid), .d_rd_data(d_rd_data), .violations(violations), .refreshes(dram_refs), .mr2(mr2));
  always #5 clk = ~clk;

  task automatic chk(input bit ok, input string what);
    checks++; if (!ok) begin fails++; $display("FAIL %s", what); end
  endtask

  logic [63:0] ref_mem [1024];
  logic [9:0]  used [1024];
  function automatic logic [31:0] mkaddr(input int k);   // k: {row[3:0], bank[2:0], col[2:0]} + beat
    return 32'h8000_0000 | (32'(k[9:6]) << 20) | (32'(k[5:3]) << 17) | (32'(k[2:0]) << 7) | (32'(k % 16) << 3);
  endfunction
  task automatic access(input bit w, input int k, input logic [63:0] d, output logic [63:0] q);
    req = 1; we = w; addr = mkaddr(k); wdata = d;
    @(posedge clk); while (!gnt) @(posedge clk);
    #1 req = 0;
    while (!rvalid) begin @(posedge clk); #1; end
    q = rdata;
    @(negedge clk);
  endtask

  initial begin
    logic [63:0] q;
    int cycles0;
    for (int l = 0; l < 8; l++) eye_lo[l*6 +: 6] = 6'($urandom_range(4, 40));
    for (int k = 0; k < 1024; k++) ref_mem[k] = '0;
    repeat (3) @(negedge clk); rst_n = 1;
    while (!init_done) @(negedge clk);
    chk(mr2 == 8'd12, "MR2 programmed with RL");
    for (int l = 0; l < 8; l++) begin
      int lo, t;
      lo = eye_lo[l*6 +: 6]; t = taps[l*6 +: 6];
      chk(lane_ok[l] && t >= lo + 6 && t <= lo + 12,
          $sformatf("lane %0d trained: eye [%0d,%0d) tap %0d (centred)", l, lo, lo + 18, t));
    end
    cycles0 = $time / 10;
    // random traffic against a reference
    for (int n = 0; n < 1500; n++) begin
      int k;
      k = $urandom_range(0, 1023);
      if ($urandom_range(0, 1)) begin
        logic [63:0] d;
        d = {$urandom, $urandom};
        access(1, k, d, q); ref_mem[k] = d;
      end else begin
        access(0, k, 0, q);
        chk(q === ref_mem[k], $sformatf("read k=%0d got %h exp %h", k, q, ref_mem[k]));
      end
    end
    chk(violations == 0, $sformatf("no LPDDR4 timing violations (%0d)", violations));
    chk(refs > 0 && refs == dram_refs, $sformatf("refreshes issued %0d / seen %0d", refs, dram_refs));
    chk(int'(refs) >= (($time / 10 - cycles0) / 1560) - 1, "refresh cadence kept up with tREFI");
    $display("row hits %0d, misses %0d, refreshes %0d, %0d cycles", hits, misses, refs, $time / 10 - cycles0);
    $display("%0d checks, %0d failures", checks, fails);
    if (fails == 0) $display("ALL TESTS PASSED"); else $display("TESTS FAILED");
    $finish;
  end
endmodule
