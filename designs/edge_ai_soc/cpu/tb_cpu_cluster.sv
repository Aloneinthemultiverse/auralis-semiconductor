// 4 x CVA6 cluster bring-up: harts boot from LPDDR4 (cached: I-cache refill bursts through the
// bridge), store to uncached SRAM, amoadd.d a shared counter, race byte stores into one word.
module tb_cpu_cluster;
  logic clk = 0, rst_n = 0;
  logic cpu_req, cpu_we, cpu_gnt, cpu_rvalid, cpu_err;
  logic [31:0] cpu_addr;
  logic [63:0] cpu_wdata, cpu_rdata;
  logic [7:0] irq = 0;
  integer fails = 0, checks = 0;

  cpu_cluster #(.N(4), .BOOT_ADDR(64'h8000_0000)) dut (
    .clk(clk), .rst_n(rst_n), .irq_src(irq), .cpu_req(cpu_req), .cpu_we(cpu_we), .cpu_addr(cpu_addr),
    .cpu_wdata(cpu_wdata), .cpu_gnt(cpu_gnt), .cpu_rvalid(cpu_rvalid), .cpu_rdata(cpu_rdata), .cpu_err(cpu_err));
  always #5 clk = ~clk;

  // SoC-side memory model: 64 KB LPDDR4 window at 0x8000_0000, 64 KB SRAM at 0x1000_0000
  logic [63:0] ddr  [8192];
  logic [63:0] sram [8192];
  logic        g;
  int          writes = 0;
  always @(negedge clk) g = ($urandom_range(0, 3) != 0);   // random stalls
  assign cpu_gnt = cpu_req && g;
  always @(posedge clk) begin
    cpu_rvalid <= cpu_req && cpu_gnt;
    cpu_err    <= 1'b0;
    if (cpu_req && cpu_gnt) begin
      if (cpu_addr[31:28] == 4'h8) begin
        cpu_rdata <= ddr[cpu_addr[15:3]];
        if (cpu_we) ddr[cpu_addr[15:3]] <= cpu_wdata;
      end else if (cpu_addr[31:28] == 4'h1) begin
        cpu_rdata <= sram[cpu_addr[15:3]];
        if (cpu_we) begin sram[cpu_addr[15:3]] <= cpu_wdata; writes++; end
      end else begin
        cpu_rdata <= '0; cpu_err <= 1'b1;
      end
    end
  end


  // transaction trace (atomics debug)
  always @(posedge clk) if (rst_n) begin
    if (dut.creq[0].aw_valid && dut.cresp[0].aw_ready)
      $display("%0t core0 AW addr=%h atop=%h len=%0d size=%0d id=%0d", $time, dut.creq[0].aw.addr, dut.creq[0].aw.atop, dut.creq[0].aw.len, dut.creq[0].aw.size, dut.creq[0].aw.id);
    if (dut.cresp[0].b_valid && dut.creq[0].b_ready) $display("%0t core0 B id=%0d resp=%0d", $time, dut.cresp[0].b.id, dut.cresp[0].b.resp);
    if (dut.cresp[0].r_valid && dut.creq[0].r_ready && dut.cresp[0].r.id != 0) $display("%0t core0 R id=%0d data=%h last=%0d", $time, dut.cresp[0].r.id, dut.cresp[0].r.data, dut.cresp[0].r.last);
    if (dut.areq.aw_valid && dut.aresp.aw_ready) $display("%0t   amo->bridge AW addr=%h id=%0d", $time, dut.areq.aw.addr, dut.areq.aw.id);
    if (dut.areq.ar_valid && dut.aresp.ar_ready && dut.areq.ar.addr[31:28]==1) $display("%0t   amo->bridge AR addr=%h id=%0d", $time, dut.areq.ar.addr, dut.areq.ar.id);
  end

  task automatic chk(input bit ok, input string what);
    checks++; if (!ok) begin fails++; $display("FAIL %s", what); end
  endtask

  initial begin
    for (int k = 0; k < 8192; k++) begin ddr[k] = 64'h0000_0013_0000_0013; sram[k] = '0; end
    $readmemh("multicore.hex", ddr);
    repeat (5) @(negedge clk); rst_n = 1;
    for (int c = 0; c < 200000 && sram[(32'h2008 >> 3)] != 4; c++) @(negedge clk);
    repeat (50) @(negedge clk);
    for (int h = 0; h < 4; h++)
      chk(sram[(32'h1000 >> 3) + h] == 64'(h + 32'h11), $sformatf("hart %0d 64-bit store (got %h)", h, sram[(32'h1000 >> 3) + h]));
    chk(sram[32'h2000 >> 3] == 4, $sformatf("amoadd.d shared counter == 4 (got %0d)", sram[32'h2000 >> 3]));
    chk(sram[32'h2100 >> 3][31:0] == 32'hA3A2A1A0,
        $sformatf("4 racing byte stores into one word all kept (got %h)", sram[32'h2100 >> 3]));
    chk(sram[32'h2008 >> 3] == 4, "all 4 harts finished");
    $display("%0d checks, %0d failures (SRAM writes seen: %0d)", checks, fails, writes);
    if (fails == 0) $display("ALL TESTS PASSED"); else $display("TESTS FAILED");
    $finish;
  end
endmodule
