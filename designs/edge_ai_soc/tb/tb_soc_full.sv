// Full-chip test: power-on -> secure boot verifies the flash image -> 4 x CVA6 run it from flash ->
// LPDDR4 (controller + trained PHY + timing-checked DRAM model) store/load -> CPU programs IOPMP and
// DMA (LPDDR4 -> ECC SRAM) -> atomics from 3 harts. Results are read back from the ECC SRAM array.
module tb_soc_full;
  logic clk = 0, por_n = 0;
  logic [255:0] otp_digest;
  logic fl_req, fl_gnt, fl_rvalid = 0, fl_err = 0; logic [31:0] fl_addr; logic [63:0] fl_rdata = 0;
  logic d_cmd_valid, d_wr_valid, d_rd_valid; logic [3:0] d_cmd; logic [2:0] d_bank; logic [13:0] d_row;
  logic [9:0] d_col; logic [15:0] d_mrw; logic [63:0] d_wr_data, d_rd_data; logic [7:0] d_wr_dm, mr2;
  logic [47:0] eye_lo;
  logic per_req, per_we, per_gnt, per_rvalid = 0; logic [31:0] per_addr; logic [63:0] per_wdata, per_rdata = 0;
  logic [3:0] pwr_en; logic [3:0] pwr_ack;
  logic sys_reset_req, ddr_ready;
  int violations, dram_refs;
  integer fails = 0, checks = 0;

  soc_full dut (.clk(clk), .por_n(por_n), .otp_digest(otp_digest), .otp_min_version(32'd5),
    .fl_req(fl_req), .fl_addr(fl_addr), .fl_gnt(fl_gnt), .fl_rvalid(fl_rvalid), .fl_rdata(fl_rdata), .fl_err(fl_err),
    .d_cmd_valid(d_cmd_valid), .d_cmd(d_cmd), .d_bank(d_bank), .d_row(d_row), .d_col(d_col), .d_mrw(d_mrw),
    .d_wr_valid(d_wr_valid), .d_wr_data(d_wr_data), .d_wr_dm(d_wr_dm), .d_rd_valid(d_rd_valid), .d_rd_data(d_rd_data),
    .eye_lo(eye_lo), .per_req(per_req), .per_we(per_we), .per_addr(per_addr), .per_wdata(per_wdata),
    .per_gnt(per_gnt), .per_rvalid(per_rvalid), .per_rdata(per_rdata),
    .pwr_ack(pwr_ack), .temp(12'd100), .pwr_en(pwr_en), .sys_reset_req(sys_reset_req), .ddr_ready(ddr_ready));
  lpddr4_dram_model u_dram (.clk(clk), .rst_n(por_n), .d_cmd_valid(d_cmd_valid), .d_cmd(d_cmd), .d_bank(d_bank),
    .d_row(d_row), .d_col(d_col), .d_mrw(d_mrw), .d_wr_valid(d_wr_valid), .d_wr_data(d_wr_data), .d_wr_dm(d_wr_dm),
    .d_rd_valid(d_rd_valid), .d_rd_data(d_rd_data), .violations(violations), .refreshes(dram_refs), .mr2(mr2));
  always #5 clk = ~clk;

  // boot flash
  logic [63:0] flash [64];
  logic g;
  always @(negedge clk) g = ($urandom_range(0, 3) != 0);
  assign fl_gnt = fl_req && g;
  always @(posedge clk) begin fl_rvalid <= fl_req && fl_gnt; fl_rdata <= flash[fl_addr[8:3]]; end
  assign per_gnt = per_req;
  always @(posedge clk) per_rvalid <= per_req;
  logic [3:0] pa;
  always @(posedge clk) pa <= pwr_en;
  assign pwr_ack = pa;

  task automatic chk(input bit ok, input string what);
    checks++; if (!ok) begin fails++; $display("FAIL %s", what); end
  endtask

  // data bits of a SECDED(72,64) codeword (no error): the non-power-of-two positions 3..71
  function automatic logic [63:0] ecc_data(input logic [71:0] cw);
    int k;
    k = 0;
    for (int p = 1; p < 72; p++) if ((p & (p - 1)) != 0) begin ecc_data[k] = cw[p]; k++; end
  endfunction
  function automatic logic [63:0] sram(input int byte_off);
    return ecc_data(dut.u_soc.u_sram.mem[byte_off >> 3]);
  endfunction

  initial begin
    int fd, c;
    $readmemh("flash.hex", flash);
    fd = $fopen("flash.digest", "r"); void'($fscanf(fd, "%h", otp_digest)); $fclose(fd);
    for (int l = 0; l < 8; l++) eye_lo[l*6 +: 6] = 6'(8 + 3 * l);
    repeat (5) @(negedge clk); por_n = 1;
    c = 0; while (!dut.cpu_rst_n && c < 20000) begin @(negedge clk); c++; end
    chk(dut.cpu_rst_n, $sformatf("secure boot verified the image and released the CPUs after %0d cycles", c));
    c = 0; while (sram(32'h110) != 64'h600D && c < 400000) begin @(negedge clk); c++; end
    repeat (2000) @(negedge clk);
    chk(ddr_ready, "LPDDR4 initialised and trained");
    chk(sram(32'h100) == 64'h123, $sformatf("hart0 SRAM store (%h)", sram(32'h100)));
    chk(sram(32'h108) == 64'hABCD, $sformatf("hart0 LPDDR4 store + load-back (%h)", sram(32'h108)));
    chk(sram(32'h200) == 64'hABCD, $sformatf("CPU-programmed DMA copied LPDDR4 -> SRAM through IOPMP (%h)", sram(32'h200)));
    chk(sram(32'h110) == 64'h600D, $sformatf("hart0 saw DMA done, wrote marker after %0d cycles", c));
    chk(sram(32'h120) == 64'd3, $sformatf("harts 1-3 amoadd.d -> 3 (%0d)", sram(32'h120)));
    chk(violations == 0, $sformatf("no LPDDR4 timing violations (%0d)", violations));
    chk(!sys_reset_req, "no fatal error / watchdog reset");
    $display("%0d checks, %0d failures", checks, fails);
    if (fails == 0) $display("ALL TESTS PASSED"); else $display("TESTS FAILED");
    $finish;
  end
endmodule
