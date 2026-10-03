// Full edge-AI SoC: soc_top (NPU, ECC SRAM, DMA + IOPMP, secure boot, safety, PMU, interconnect)
// + 4 x CVA6 RV64GC cluster on the CPU port + LPDDR4 controller and PHY on the DDR port.
// The cores stay in reset until secure boot has verified the stage-1 image; they then execute that
// same verified image from boot flash (BOOT_ADDR = 0x8, just after the image header).
// External: boot flash, DRAM device pins (d_*), peripheral subsystem, power switches, OTP.
module soc_full #(parameter int R = 4, parameter int C = 4, parameter int SRAM_DEPTH = 1024) (
  input  logic         clk,
  input  logic         por_n,
  input  logic [255:0] otp_digest,
  input  logic [31:0]  otp_min_version,
  // boot flash
  output logic         fl_req,
  output logic [31:0]  fl_addr,
  input  logic         fl_gnt,
  input  logic         fl_rvalid,
  input  logic [63:0]  fl_rdata,
  input  logic         fl_err,
  // LPDDR4 device (command / beat level)
  output logic         d_cmd_valid,
  output logic [3:0]   d_cmd,
  output logic [2:0]   d_bank,
  output logic [13:0]  d_row,
  output logic [9:0]   d_col,
  output logic [15:0]  d_mrw,
  output logic         d_wr_valid,
  output logic [63:0]  d_wr_data,
  output logic [7:0]   d_wr_dm,
  input  logic         d_rd_valid,
  input  logic [63:0]  d_rd_data,
  input  logic [47:0]  eye_lo,          // behavioural channel (PHY training target)
  // peripherals
  output logic         per_req,
  output logic         per_we,
  output logic [31:0]  per_addr,
  output logic [63:0]  per_wdata,
  input  logic         per_gnt,
  input  logic         per_rvalid,
  input  logic [63:0]  per_rdata,
  // power / sensors
  input  logic [3:0]   pwr_ack,
  input  logic [11:0]  temp,
  output logic [3:0]   pwr_en,
  output logic         sys_reset_req,
  output logic         ddr_ready
);
  logic        cpu_rst_n, cpu_req, cpu_we, cpu_gnt, cpu_rvalid, cpu_err;
  logic [31:0] cpu_addr;
  logic [63:0] cpu_wdata, cpu_rdata;
  logic [7:0]  irq;
  logic        ddr_req, ddr_we, ddr_gnt, ddr_rvalid;
  logic [31:0] ddr_addr;
  logic [63:0] ddr_wdata, ddr_rdata;
  logic        rst_n;
  logic [3:0]  iso_en, ret_save, dom_clk_en;

  soc_top #(.R(R), .C(C), .SRAM_DEPTH(SRAM_DEPTH)) u_soc (
    .clk(clk), .por_n(por_n), .otp_digest(otp_digest), .otp_min_version(otp_min_version),
    .cpu_rst_n(cpu_rst_n), .cpu_req(cpu_req), .cpu_we(cpu_we), .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata),
    .cpu_gnt(cpu_gnt), .cpu_rvalid(cpu_rvalid), .cpu_rdata(cpu_rdata), .cpu_err(cpu_err), .irq(irq),
    .ddr_req(ddr_req), .ddr_we(ddr_we), .ddr_addr(ddr_addr), .ddr_wdata(ddr_wdata), .ddr_gnt(ddr_gnt),
    .ddr_rvalid(ddr_rvalid), .ddr_rdata(ddr_rdata),
    .fl_req(fl_req), .fl_addr(fl_addr), .fl_gnt(fl_gnt), .fl_rvalid(fl_rvalid), .fl_rdata(fl_rdata), .fl_err(fl_err),
    .per_req(per_req), .per_we(per_we), .per_addr(per_addr), .per_wdata(per_wdata), .per_gnt(per_gnt),
    .per_rvalid(per_rvalid), .per_rdata(per_rdata),
    .pwr_ack(pwr_ack), .temp(temp), .pwr_en(pwr_en), .iso_en(iso_en), .ret_save(ret_save),
    .dom_clk_en(dom_clk_en), .sys_reset_req(sys_reset_req));

  assign rst_n = u_soc.rst_n;

  cpu_cluster #(.N(4), .NSRC(8), .BOOT_ADDR(64'h0000_0000_0000_0008)) u_cpu (
    .clk(clk), .rst_n(rst_n & cpu_rst_n), .irq_src(irq),
    .cpu_req(cpu_req), .cpu_we(cpu_we), .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata),
    .cpu_gnt(cpu_gnt), .cpu_rvalid(cpu_rvalid), .cpu_rdata(cpu_rdata), .cpu_err(cpu_err));

  // LPDDR4: controller + PHY
  logic        dfi_cmd_valid, dfi_train_req, dfi_train_done, dfi_rddata_valid;
  logic [2:0]  dfi_cmd, dfi_bank;
  logic [13:0] dfi_row;
  logic [9:0]  dfi_col;
  logic [15:0] dfi_mrw;
  logic [63:0] dfi_wrdata, dfi_rddata;
  logic [3:0]  dfi_wrbeat;
  logic [47:0] taps;
  logic [7:0]  lane_ok;
  lpddr4_ctrl u_ddrc (.clk(clk), .rst_n(rst_n), .req(ddr_req), .we(ddr_we), .addr(ddr_addr), .wdata(ddr_wdata),
    .gnt(ddr_gnt), .rvalid(ddr_rvalid), .rdata(ddr_rdata), .dfi_cmd_valid(dfi_cmd_valid), .dfi_cmd(dfi_cmd),
    .dfi_bank(dfi_bank), .dfi_row(dfi_row), .dfi_col(dfi_col), .dfi_mrw(dfi_mrw), .dfi_wrdata(dfi_wrdata),
    .dfi_wrbeat(dfi_wrbeat), .dfi_train_req(dfi_train_req), .dfi_train_done(dfi_train_done),
    .dfi_rddata_valid(dfi_rddata_valid), .dfi_rddata(dfi_rddata), .init_done(ddr_ready),
    .stat_hits(), .stat_misses(), .stat_refreshes());
  lpddr4_phy u_ddrphy (.clk(clk), .rst_n(rst_n), .dfi_cmd_valid(dfi_cmd_valid), .dfi_cmd(dfi_cmd),
    .dfi_bank(dfi_bank), .dfi_row(dfi_row), .dfi_col(dfi_col), .dfi_mrw(dfi_mrw), .dfi_wrdata(dfi_wrdata),
    .dfi_wrbeat(dfi_wrbeat), .dfi_train_req(dfi_train_req), .dfi_train_done(dfi_train_done),
    .dfi_rddata_valid(dfi_rddata_valid), .dfi_rddata(dfi_rddata), .d_cmd_valid(d_cmd_valid), .d_cmd(d_cmd),
    .d_bank(d_bank), .d_row(d_row), .d_col(d_col), .d_mrw(d_mrw), .d_wr_valid(d_wr_valid), .d_wr_data(d_wr_data),
    .d_wr_dm(d_wr_dm), .d_rd_valid(d_rd_valid), .d_rd_data(d_rd_data), .eye_lo(eye_lo), .taps(taps),
    .lane_ok(lane_ok));
endmodule
