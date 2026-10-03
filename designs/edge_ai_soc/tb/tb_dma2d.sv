// DMA -> IOPMP -> memory model: 2-D copies, sticky-error clear at start, isolation violations, lock.
module tb_dma2d;
  logic clk = 0, rst_n = 0;
  logic r_req = 0, r_we = 0; logic [7:0] r_addr = 0; logic [31:0] r_wdata = 0; logic [31:0] r_rdata;
  logic p_req = 0, p_we = 0; logic [7:0] p_addr = 0; logic [31:0] p_wdata = 0; logic [31:0] p_rdata;
  logic d_req, d_we, d_gnt, d_rvalid, d_err; logic [31:0] d_addr; logic [63:0] d_wdata, d_rdata;
  logic m_req, m_we, m_gnt, m_rvalid, m_err; logic [31:0] m_addr; logic [63:0] m_wdata, m_rdata;
  logic irq, pirq;
  logic [63:0] mem [4096];   // 32 KB at 0x0000_0000
  logic [63:0] snap [4096];
  integer fails = 0, checks = 0;
  int lat;

  dma2d dma (.clk(clk), .rst_n(rst_n), .r_req(r_req), .r_we(r_we), .r_addr(r_addr), .r_wdata(r_wdata),
             .r_rdata(r_rdata), .m_req(d_req), .m_we(d_we), .m_addr(d_addr), .m_wdata(d_wdata),
             .m_gnt(d_gnt), .m_rvalid(d_rvalid), .m_rdata(d_rdata), .m_err(d_err), .irq(irq));
  iopmp pmp (.clk(clk), .rst_n(rst_n), .r_req(p_req), .r_we(p_we), .r_addr(p_addr), .r_wdata(p_wdata),
             .r_rdata(p_rdata), .s_req(d_req), .s_we(d_we), .s_addr(d_addr), .s_wdata(d_wdata),
             .s_gnt(d_gnt), .s_rvalid(d_rvalid), .s_rdata(d_rdata), .s_err(d_err),
             .m_req(m_req), .m_we(m_we), .m_addr(m_addr), .m_wdata(m_wdata), .m_gnt(m_gnt),
             .m_rvalid(m_rvalid), .m_rdata(m_rdata), .m_err(m_err), .irq(pirq));
  always #5 clk = ~clk;

  // memory model: random grant stalls and 1-3 cycle response latency
  logic pend = 0; int cnt; logic [31:0] pa; logic gnt_ok;
  always @(negedge clk) gnt_ok = ($urandom_range(0, 2) != 0);
  assign m_gnt = m_req && !pend && gnt_ok;
  always @(posedge clk) begin
    m_rvalid <= 1'b0; m_err <= 1'b0;
    if (!rst_n) pend <= 1'b0;
    else if (m_req && m_gnt) begin
      pend <= 1'b1; cnt <= $urandom_range(0, 2); pa <= m_addr;
      if (m_we && m_addr < 32'h8000) mem[m_addr[14:3]] <= m_wdata;
    end else if (pend) begin
      if (cnt == 0) begin
        pend <= 1'b0; m_rvalid <= 1'b1; m_rdata <= mem[pa[14:3]]; m_err <= (pa >= 32'h8000);
      end else cnt <= cnt - 1;
    end
  end

  task automatic chk(input bit ok, input string what);
    checks++; if (!ok) begin fails++; $display("FAIL %s", what); end
  endtask
  task automatic wreg(input logic [7:0] a, input logic [31:0] d);
    r_req = 1; r_we = 1; r_addr = a; r_wdata = d; @(negedge clk); r_req = 0; r_we = 0;
  endtask
  task automatic preg(input logic [7:0] a, input logic [31:0] d);
    p_req = 1; p_we = 1; p_addr = a; p_wdata = d; @(negedge clk); p_req = 0; p_we = 0;
  endtask
  task automatic run(input int t_src, input int t_dst, input int t_len, input int t_rows, input int t_ss, input int t_ds);
    wreg(8'h00, 32'h2);  // irq enable, clear done
    wreg(8'h04, t_src); wreg(8'h08, t_dst); wreg(8'h0C, t_len); wreg(8'h10, t_rows);
    wreg(8'h14, t_ss); wreg(8'h18, t_ds); wreg(8'h00, 32'h3);
    lat = 0;
    while (!irq && lat < 20000) begin @(negedge clk); lat++; end
    chk(lat < 20000, "dma completes");
    r_addr = 8'h00; #1;
  endtask

  initial begin
    int t_src, t_dst, t_len, t_rows, t_ss, t_ds;
    logic [63:0] w_before;
    repeat (2) @(negedge clk); rst_n = 1;
    // region 0: 0x0000-0x4000 read-only (weights); region 1: 0x4000-0x8000 read/write (activations)
    preg(8'h00, 32'h0000); preg(8'h04, 32'h4000); preg(8'h08, 32'b0011);
    preg(8'h10, 32'h4000); preg(8'h14, 32'h8000); preg(8'h18, 32'b0111);
    for (int a = 0; a < 4096; a++) mem[a] = {$urandom, $urandom};
    for (int t = 0; t < 12; t++) begin
      t_len = $urandom_range(1, 8); t_rows = $urandom_range(1, 6);
      t_ss = 8 * (t_len + $urandom_range(0, 4)); t_ds = 8 * (t_len + $urandom_range(0, 4));
      t_src = 8 * $urandom_range(0, 1024); t_dst = 32'h4000 + 8 * $urandom_range(0, 512);
      for (int a = 0; a < 4096; a++) snap[a] = mem[a];
      run(t_src, t_dst, t_len, t_rows, t_ss, t_ds);
      chk(r_rdata[2:0] == 3'b010, $sformatf("copy %0d done without error (status %b)", t, r_rdata[2:0]));
      for (int r = 0; r < t_rows; r++)
        for (int i = 0; i < t_len; i++)
          chk(mem[(t_dst + r*t_ds + i*8) >> 3] === snap[(t_src + r*t_ss + i*8) >> 3], $sformatf("copy %0d r%0d i%0d", t, r, i));
    end
    // isolation: a DMA write into the read-only weight region is blocked and reported
    w_before = mem[16];
    run(32'h4000, 32'h0080, 1, 1, 8, 8);
    chk(r_rdata[2] == 1'b1, "write to read-only region reports error");
    chk(mem[16] === w_before, "read-only weight word unchanged");
    chk(pirq == 1'b1, "iopmp violation interrupt");
    p_addr = 8'hF0; #1; chk(p_rdata == 32'h0080, "violation address logged");
    p_addr = 8'hF4; #1; chk(p_rdata[1:0] == 2'b11, "violation is a write");
    preg(8'hF4, 1); #1; chk(pirq == 1'b0, "violation cleared");
    // the next good copy clears the sticky error
    run(32'h0, 32'h5000, 2, 1, 16, 16);
    chk(r_rdata[2:0] == 3'b010, "sticky error cleared on start");
    // lock region 0, then try to widen it
    preg(8'h08, 32'b1011); preg(8'h04, 32'hFFFF_0000);
    p_addr = 8'h04; #1; chk(p_rdata == 32'h4000, "locked region not rewritable");
    // default deny outside all regions
    run(32'h9000, 32'h4000, 1, 1, 8, 8);
    chk(r_rdata[2] == 1'b1, "default deny");
    $display("%0d checks, %0d failures", checks, fails);
    if (fails == 0) $display("ALL TESTS PASSED"); else $display("TESTS FAILED");
    $finish;
  end
endmodule
