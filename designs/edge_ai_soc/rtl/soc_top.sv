// Edge-AI SoC top (28 nm target, 1 GHz). Integrates the verified Auralis blocks:
//   NPU (npu_core: R x C systolic array, 64 x 64 in silicon = 8.19 TOPS INT8), ECC SRAM, 2-D DMA behind
//   IOPMP (accelerator isolation), secure boot (SHA-256 root of trust), watchdog, error aggregator,
//   PMU (clock/power domains, thermal throttle), and the interconnect.
// Integration IP connected through ports (dropped in from open/licensed IP, not generated here):
//   cpu_*  : 4 x RV64GC cluster (e.g. CVA6) with L1/L2, PLIC/CLINT; Linux capable; held in reset by secure boot
//   ddr_*  : LPDDR4 controller + PHY (64-bit LPDDR4-3200 = 25.6 GB/s), window 0x8000_0000
//   fl_*   : boot flash (QSPI controller), window 0x0000_0000
//   per_*  : peripheral subsystem: MIPI CSI-2, PCIe Gen3, USB 3.0, Ethernet controllers + PHYs, 0x4000_0000
// Memory map: 0x0000_0000 flash | 0x1000_0000 SRAM | 0x2000_0000 NPU buffers | 0x3000_0000 registers
//   (0x0xxx NPU, 0x1xxx DMA, 0x2xxx IOPMP, 0x3xxx WDT, 0x4xxx ERR, 0x5xxx PMU, 0x6xxx SYS)
//   | 0x4000_0000 peripherals | 0x8000_0000 LPDDR4. Anything else: decode error.
module soc_top #(parameter int R = 4, parameter int C = 4, parameter int SRAM_DEPTH = 1024,
                 parameter int D = 4, parameter int NPU_BUF_DEPTH = 256) (
  input  logic         clk,
  input  logic         por_n,
  // OTP fuses
  input  logic [255:0] otp_digest,
  input  logic [31:0]  otp_min_version,
  // CPU cluster master port
  output logic         cpu_rst_n,
  input  logic         cpu_req,
  input  logic         cpu_we,
  input  logic [31:0]  cpu_addr,
  input  logic [63:0]  cpu_wdata,
  output logic         cpu_gnt,
  output logic         cpu_rvalid,
  output logic [63:0]  cpu_rdata,
  output logic         cpu_err,
  output logic [7:0]   irq,         // to PLIC: {pmu_throttle, err_fatal, err, wdt_bark, iopmp, dma, npu, boot_fail}
  // LPDDR4 controller port
  output logic         ddr_req,
  output logic         ddr_we,
  output logic [31:0]  ddr_addr,
  output logic [63:0]  ddr_wdata,
  input  logic         ddr_gnt,
  input  logic         ddr_rvalid,
  input  logic [63:0]  ddr_rdata,
  // boot flash port
  output logic         fl_req,
  output logic [31:0]  fl_addr,
  input  logic         fl_gnt,
  input  logic         fl_rvalid,
  input  logic [63:0]  fl_rdata,
  input  logic         fl_err,
  // peripheral subsystem port
  output logic         per_req,
  output logic         per_we,
  output logic [31:0]  per_addr,
  output logic [63:0]  per_wdata,
  input  logic         per_gnt,
  input  logic         per_rvalid,
  input  logic [63:0]  per_rdata,
  // power switches / sensors
  input  logic [D-1:0] pwr_ack,
  input  logic [11:0]  temp,
  output logic [D-1:0] pwr_en,
  output logic [D-1:0] iso_en,
  output logic [D-1:0] ret_save,
  output logic [D-1:0] dom_clk_en,
  output logic         sys_reset_req
);
  logic rst_n;
  rst_sync u_rst (.clk(clk), .arst_n(por_n), .rst_n(rst_n));

  // ---------------- secure boot ----------------
  logic         sb_req, sb_gnt, sb_rvalid, boot_ok, boot_fail;
  logic [31:0]  sb_addr;
  logic [255:0] measured;
  secure_boot #(.MAX_WORDS(1 << 20)) u_boot (
    .clk(clk), .rst_n(rst_n), .img_base(32'h0000_0000), .otp_digest(otp_digest),
    .otp_min_version(otp_min_version), .m_req(sb_req), .m_addr(sb_addr), .m_gnt(sb_gnt),
    .m_rvalid(sb_rvalid), .m_rdata(fl_rdata), .m_err(fl_err), .cpu_rst_n(cpu_rst_n),
    .boot_ok(boot_ok), .boot_fail(boot_fail), .measured(measured));

  // ---------------- DMA behind IOPMP ----------------
  logic        dma_rreq, dma_rwe, iop_rreq, iop_rwe;
  logic [7:0]  reg_off;
  logic [31:0] reg_wdata, dma_rdata, iop_rdata;
  logic        d_req, d_we, d_gnt, d_rvalid, d_err, dma_irq, iop_irq;
  logic [31:0] d_addr;
  logic [63:0] d_wdata, d_rdata;
  logic        p_req, p_we, p_gnt, p_rvalid, p_err;
  logic [31:0] p_addr;
  logic [63:0] p_wdata, p_rdata;
  dma2d u_dma (.clk(clk), .rst_n(rst_n), .r_req(dma_rreq), .r_we(dma_rwe), .r_addr(reg_off), .r_wdata(reg_wdata),
               .r_rdata(dma_rdata), .m_req(d_req), .m_we(d_we), .m_addr(d_addr), .m_wdata(d_wdata),
               .m_gnt(d_gnt), .m_rvalid(d_rvalid), .m_rdata(d_rdata), .m_err(d_err), .irq(dma_irq));
  iopmp #(.N(8)) u_iopmp (.clk(clk), .rst_n(rst_n), .r_req(iop_rreq), .r_we(iop_rwe), .r_addr(reg_off),
               .r_wdata(reg_wdata), .r_rdata(iop_rdata), .s_req(d_req), .s_we(d_we), .s_addr(d_addr),
               .s_wdata(d_wdata), .s_gnt(d_gnt), .s_rvalid(d_rvalid), .s_rdata(d_rdata), .s_err(d_err),
               .m_req(p_req), .m_we(p_we), .m_addr(p_addr), .m_wdata(p_wdata), .m_gnt(p_gnt),
               .m_rvalid(p_rvalid), .m_rdata(p_rdata), .m_err(p_err), .irq(iop_irq));

  // ---------------- interconnect: 2 masters (CPU, DMA), round-robin, one outstanding ----------------
  localparam logic [2:0] T_FLASH = 3'd0, T_SRAM = 3'd1, T_NPU = 3'd2, T_REG = 3'd3, T_PER = 3'd4,
                         T_DDR = 3'd5, T_NONE = 3'd7;
  logic        busy, owner, pick, rr_last;
  logic [2:0]  tgt, cur_tgt;
  logic        m_req, m_we, s_gnt, s_rvalid, s_err;
  logic [31:0] m_addr;
  logic [63:0] m_wdata, s_rdata;
  logic        cpu_ok;

  assign cpu_ok = cpu_req && cpu_rst_n;
  // round robin: alternate when both request
  assign pick   = (cpu_ok && p_req) ? ~rr_last : p_req;  // 1 = DMA
  assign m_req  = !busy && (cpu_ok || p_req);
  assign m_we   = pick ? p_we : cpu_we;
  assign m_addr = pick ? p_addr : cpu_addr;
  assign m_wdata = pick ? p_wdata : cpu_wdata;

  always_comb begin
    case (m_addr[31:28])
      4'h0:    tgt = T_FLASH;
      4'h1:    tgt = T_SRAM;
      4'h2:    tgt = T_NPU;
      4'h3:    tgt = T_REG;
      4'h4:    tgt = T_PER;
      4'h8, 4'h9, 4'hA, 4'hB, 4'hC, 4'hD, 4'hE, 4'hF: tgt = T_DDR;
      default: tgt = T_NONE;
    endcase
    if (tgt == T_FLASH && m_we) tgt = T_NONE;        // flash is read-only on the bus
    if (tgt == T_FLASH && !boot_ok) tgt = T_NONE;    // flash belongs to secure boot until it is done
  end

  // ---- slaves ----
  // SRAM
  logic        sr_rvalid, sr_corr, sr_uncorr;
  logic [63:0] sr_rdata;
  logic [$clog2(SRAM_DEPTH)-1:0] sr_eaddr;
  logic        sr_req;
  assign sr_req = m_req && tgt == T_SRAM;
  sram_ecc #(.DEPTH(SRAM_DEPTH)) u_sram (.clk(clk), .rst_n(rst_n), .req(sr_req), .we(m_we),
               .addr(m_addr[$clog2(SRAM_DEPTH)+2:3]), .wdata(m_wdata), .inj_mask('0), .rvalid(sr_rvalid),
               .rdata(sr_rdata), .err_corr(sr_corr), .err_uncorr(sr_uncorr), .err_addr(sr_eaddr));

  // NPU: buffers at 0x2000_0000 (sel = addr[21:20]; ABUF/WBUF word = addr[18:3]; CBUF row = addr[19:4], half = addr[3])
  logic             npu_rreq, npu_rwe, npu_irq;
  logic [31:0]      npu_rdata;
  logic             h_req;
  logic [1:0]       h_sel;
  logic [15:0]      h_addr;
  logic [C*32-1:0]  h_wdata, h_rdata;
  logic             npu_half_q;
  assign h_req   = m_req && tgt == T_NPU;
  assign h_sel   = m_addr[21:20];
  assign h_addr  = (h_sel == 2'd2) ? m_addr[19:4] : m_addr[18:3];
  assign h_wdata = (C*32)'(m_wdata);
  npu_core #(.R(R), .C(C), .ADEPTH(NPU_BUF_DEPTH), .WDEPTH(NPU_BUF_DEPTH), .CDEPTH(NPU_BUF_DEPTH)) u_npu (.clk(clk), .rst_n(rst_n), .r_req(npu_rreq), .r_we(npu_rwe), .r_addr(reg_off),
               .r_wdata(reg_wdata), .r_rdata(npu_rdata), .h_req(h_req), .h_we(m_we), .h_sel(h_sel),
               .h_addr(h_addr), .h_wdata(h_wdata), .h_rdata(h_rdata), .irq(npu_irq));

  // register slaves (32-bit, decoded by addr[15:12])
  logic        wdt_rreq, wdt_rwe, err_rreq, err_rwe, pmu_rreq, pmu_rwe;
  logic [31:0] wdt_rdata, err_rdata, pmu_rdata, sys_rdata, reg_rdata;
  logic        bark, bite, err_irq, err_fatal, throttle;
  logic [D-1:0] dom_err;
  logic [D-1:0] dom_rst_n;   // per-domain resets (to domain reset trees)
  logic        reg_sel;
  assign reg_sel   = m_req && tgt == T_REG;
  assign reg_off   = m_addr[7:0];
  assign reg_wdata = m_wdata[31:0];
  assign npu_rreq  = reg_sel && m_addr[15:12] == 4'h0;  assign npu_rwe = npu_rreq && m_we;
  assign dma_rreq  = reg_sel && m_addr[15:12] == 4'h1;  assign dma_rwe = dma_rreq && m_we;
  assign iop_rreq  = reg_sel && m_addr[15:12] == 4'h2;  assign iop_rwe = iop_rreq && m_we;
  assign wdt_rreq  = reg_sel && m_addr[15:12] == 4'h3;  assign wdt_rwe = wdt_rreq && m_we;
  assign err_rreq  = reg_sel && m_addr[15:12] == 4'h4;  assign err_rwe = err_rreq && m_we;
  assign pmu_rreq  = reg_sel && m_addr[15:12] == 4'h5;  assign pmu_rwe = pmu_rreq && m_we;

  watchdog u_wdt (.clk(clk), .rst_n(rst_n), .r_req(wdt_rreq), .r_we(wdt_rwe), .r_addr(reg_off),
                  .r_wdata(reg_wdata), .r_rdata(wdt_rdata), .bark(bark), .bite(bite));

  logic [15:0] faults;
  logic        dec_err_pulse;
  // bit: 0 ecc_corr, 1 ecc_uncorr (fatal), 2 iopmp, 3 dma_err, 4 wdt_bark, 5 boot_fail, 6 pmu_dom_err,
  //      7 decode_err, 15 wdt_bite (fatal)
  assign faults = {bite, 7'd0, dec_err_pulse, |dom_err, boot_fail, bark, d_err & d_rvalid, iop_irq,
                   sr_uncorr, sr_corr};
  err_agg #(.N(16), .FATAL_MASK(16'h8002)) u_err (.clk(clk), .rst_n(rst_n), .fault(faults), .r_req(err_rreq),
                  .r_we(err_rwe), .r_addr(reg_off), .r_wdata(reg_wdata), .r_rdata(err_rdata),
                  .irq(err_irq), .fatal(err_fatal));

  pmu #(.D(D), .NPU_DOM(0)) u_pmu (.clk(clk), .rst_n(rst_n), .r_req(pmu_rreq), .r_we(pmu_rwe), .r_addr(reg_off),
                  .r_wdata(reg_wdata), .r_rdata(pmu_rdata), .idle({{(D-1){1'b0}}, ~npu_rdata[0]}),
                  .pwr_ack(pwr_ack), .temp(temp), .clk_en(dom_clk_en), .iso_en(iso_en), .ret_save(ret_save),
                  .pwr_en(pwr_en), .dom_rst_n(dom_rst_n), .dom_err(dom_err), .throttle(throttle));

  // SYS registers: 0x00 boot status {fail, ok}, 0x20..0x3C measured digest words (H0 first)
  always_comb begin
    sys_rdata = '0;
    if (reg_off == 8'h00) sys_rdata = {30'd0, boot_fail, boot_ok};
    else if (reg_off >= 8'h20 && reg_off < 8'h40) sys_rdata = 32'(measured >> (32 * (32'd7 - 32'(reg_off[4:2]))));
  end
  always_comb begin
    case (m_addr[15:12])
      4'h0: reg_rdata = npu_rdata;
      4'h1: reg_rdata = dma_rdata;
      4'h2: reg_rdata = iop_rdata;
      4'h3: reg_rdata = wdt_rdata;
      4'h4: reg_rdata = err_rdata;
      4'h5: reg_rdata = pmu_rdata;
      4'h6: reg_rdata = sys_rdata;
      default: reg_rdata = '0;
    endcase
  end

  // external slaves
  assign ddr_req   = m_req && tgt == T_DDR;
  assign ddr_we    = m_we;
  assign ddr_addr  = m_addr;
  assign ddr_wdata = m_wdata;
  assign per_req   = m_req && tgt == T_PER;
  assign per_we    = m_we;
  assign per_addr  = m_addr;
  assign per_wdata = m_wdata;

  // flash: secure boot until boot_ok, then the bus (read-only)
  logic bus_fl;
  assign bus_fl  = m_req && tgt == T_FLASH;
  assign fl_req  = boot_ok ? bus_fl : sb_req;
  assign fl_addr = boot_ok ? m_addr : sb_addr;
  assign sb_gnt    = !boot_ok && fl_gnt;
  assign sb_rvalid = !boot_ok && fl_rvalid;

  // slave grant (accept) for the current request
  always_comb begin
    case (tgt)
      T_FLASH: s_gnt = fl_gnt;
      T_DDR:   s_gnt = ddr_gnt;
      T_PER:   s_gnt = per_gnt;
      default: s_gnt = 1'b1;   // on-chip slaves and decode errors accept immediately
    endcase
  end

  // response path
  logic [31:0] reg_q;
  logic        int_v, dec_q;
  logic        npu_sel_c, npu_half;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      busy <= 1'b0; owner <= 1'b0; rr_last <= 1'b0; cur_tgt <= T_NONE; reg_q <= '0; int_v <= 1'b0;
      dec_q <= 1'b0; npu_half_q <= 1'b0; npu_sel_c <= 1'b0;
    end else begin
      int_v <= 1'b0;
      dec_q <= 1'b0;
      if (m_req && s_gnt) begin
        busy <= 1'b1; owner <= pick; rr_last <= pick; cur_tgt <= tgt;
        reg_q <= reg_rdata;
        npu_half_q <= m_addr[3];
        npu_sel_c <= (h_sel == 2'd2);
        if (tgt == T_REG || tgt == T_NPU || (tgt == T_SRAM && m_we)) int_v <= 1'b1;
        if (tgt == T_NONE) dec_q <= 1'b1;
      end else if (busy && s_rvalid) busy <= 1'b0;
    end
  end
  assign dec_err_pulse = dec_q;
  assign npu_half = npu_half_q;

  always_comb begin
    s_rvalid = 1'b0; s_rdata = '0; s_err = 1'b0;
    case (cur_tgt)
      T_SRAM:  begin s_rvalid = sr_rvalid | int_v; s_rdata = sr_rdata; s_err = sr_rvalid & sr_uncorr; end
      T_NPU:   begin s_rvalid = int_v; s_rdata = npu_sel_c ? h_rdata[(npu_half ? 64 : 0) +: 64] : '0; end
      T_REG:   begin s_rvalid = int_v; s_rdata = {32'd0, reg_q}; end
      T_FLASH: begin s_rvalid = fl_rvalid; s_rdata = fl_rdata; s_err = fl_err; end
      T_DDR:   begin s_rvalid = ddr_rvalid; s_rdata = ddr_rdata; end
      T_PER:   begin s_rvalid = per_rvalid; s_rdata = per_rdata; end
      default: begin s_rvalid = dec_q; s_err = 1'b1; end
    endcase
    if (!busy) s_rvalid = 1'b0;
  end

  assign cpu_gnt    = m_req && !pick && s_gnt;
  assign p_gnt      = m_req && pick && s_gnt;
  assign cpu_rvalid = busy && !owner && s_rvalid;
  assign p_rvalid   = busy && owner && s_rvalid;
  assign cpu_rdata  = s_rdata;
  assign p_rdata    = s_rdata;
  assign cpu_err    = s_err;
  assign p_err      = s_err;

  assign irq = {throttle, err_fatal, err_irq, bark, iop_irq, dma_irq, npu_irq, boot_fail};
  assign sys_reset_req = bite | err_fatal;
endmodule
