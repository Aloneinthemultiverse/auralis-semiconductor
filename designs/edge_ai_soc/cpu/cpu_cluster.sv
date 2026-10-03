`include "axi/typedef.svh"
// Application CPU cluster: N x CVA6 (RV64GC, Sv39, Linux-capable; config cv64a6_auralis),
// cores merged by axi_mux -> one axi_riscv_atomics (AMOs and LR/SC atomic across harts) ->
// axi2sbus -> the SoC CPU port. Local devices intercepted before the SoC bus:
//   CLINT 0x0200_0000: msip[h] @ +4h, mtimecmp[h] @ +0x4000+8h, mtime @ +0xBFF8 (ticks every clk / TIME_DIV)
//   PLIC  0x0C00_0000: pending @ +0x1000 (R), enable[h] @ +0x2000+0x80h, claim/complete[h] @ +0x20_0004+0x1000h
//         (sources 1..NSRC = SoC irq[0..NSRC-1]; M-mode external interrupt per hart; no priorities)
module cpu_cluster #(parameter int N = 4, parameter int NSRC = 8, parameter int TIME_DIV = 100,
                     parameter logic [63:0] BOOT_ADDR = 64'h0000_0008) (
  input  logic            clk,
  input  logic            rst_n,
  input  logic [NSRC-1:0] irq_src,
  // SoC CPU port
  output logic            cpu_req,
  output logic            cpu_we,
  output logic [31:0]     cpu_addr,
  output logic [63:0]     cpu_wdata,
  input  logic            cpu_gnt,
  input  logic            cpu_rvalid,
  input  logic [63:0]     cpu_rdata,
  input  logic            cpu_err
);
  localparam int IW = ariane_axi::IdWidth;
  localparam int UW = ariane_axi::UserWidth;

  // Cores -> axi_mux (core index prepended to the AXI ID) -> ONE axi_riscv_atomics -> ONE bridge.
  // A single atomics adapter at the merge point makes AMOs and LR/SC atomic across all harts.
  localparam int MW = IW + $clog2(N);
  typedef logic [63:0]   addr_t;
  typedef logic [63:0]   data_t;
  typedef logic [7:0]    strb_t;
  typedef logic [UW-1:0] user_t;
  typedef logic [IW-1:0] sid_t;
  typedef logic [MW-1:0] mid_t;
  `AXI_TYPEDEF_ALL(slv, addr_t, sid_t, data_t, strb_t, user_t)
  `AXI_TYPEDEF_ALL(mst, addr_t, mid_t, data_t, strb_t, user_t)

  ariane_axi::req_t  [N-1:0] creq;
  ariane_axi::resp_t [N-1:0] cresp;
  slv_req_t          [N-1:0] sreq;
  slv_resp_t         [N-1:0] sresp;
  mst_req_t                  mreq, areq;
  mst_resp_t                 mresp, aresp;
  logic [N-1:0]              msip, mtip, meip;
  logic                      s_req, s_we, s_gnt, s_rvalid, s_err, s_lock;
  logic [31:0]               s_addr;
  logic [63:0]               s_wdata;
  logic [63:0]               local_rdata, cpu_rdata_mux;

  for (genvar h = 0; h < N; h++) begin : g_core
    cva6 #(.noc_req_t(ariane_axi::req_t), .noc_resp_t(ariane_axi::resp_t)) u_cva6 (
      .clk_i(clk), .rst_ni(rst_n), .boot_addr_i(BOOT_ADDR), .hart_id_i(64'(h)),
      .irq_i({1'b0, meip[h]}), .ipi_i(msip[h]), .time_irq_i(mtip[h]), .debug_req_i(1'b0),
      .rvfi_probes_o(), .cvxif_req_o(), .cvxif_resp_i('0),
      .noc_req_o(creq[h]), .noc_resp_i(cresp[h]));
    assign sreq[h]  = creq[h];      // identical packed layouts
    assign cresp[h] = sresp[h];
  end

  axi_mux #(.SlvAxiIDWidth(IW), .slv_aw_chan_t(slv_aw_chan_t), .mst_aw_chan_t(mst_aw_chan_t),
            .w_chan_t(slv_w_chan_t), .slv_b_chan_t(slv_b_chan_t), .mst_b_chan_t(mst_b_chan_t),
            .slv_ar_chan_t(slv_ar_chan_t), .mst_ar_chan_t(mst_ar_chan_t), .slv_r_chan_t(slv_r_chan_t),
            .mst_r_chan_t(mst_r_chan_t), .slv_req_t(slv_req_t), .slv_resp_t(slv_resp_t),
            .mst_req_t(mst_req_t), .mst_resp_t(mst_resp_t), .NoSlvPorts(N), .MaxWTrans(4)) u_mux (
    .clk_i(clk), .rst_ni(rst_n), .test_i(1'b0), .slv_reqs_i(sreq), .slv_resps_o(sresp),
    .mst_req_o(mreq), .mst_resp_i(mresp));

  axi_riscv_atomics #(.AXI_ADDR_WIDTH(64), .AXI_DATA_WIDTH(64), .AXI_ID_WIDTH(MW), .AXI_USER_WIDTH(UW),
                      .AXI_MAX_WRITE_TXNS(4), .RISCV_WORD_WIDTH(64)) u_amo (
    .clk_i(clk), .rst_ni(rst_n),
    .slv_aw_addr_i(mreq.aw.addr), .slv_aw_prot_i(mreq.aw.prot), .slv_aw_region_i(mreq.aw.region),
    .slv_aw_atop_i(mreq.aw.atop), .slv_aw_len_i(mreq.aw.len), .slv_aw_size_i(mreq.aw.size),
    .slv_aw_burst_i(mreq.aw.burst), .slv_aw_lock_i(mreq.aw.lock), .slv_aw_cache_i(mreq.aw.cache),
    .slv_aw_qos_i(mreq.aw.qos), .slv_aw_id_i(mreq.aw.id), .slv_aw_user_i(mreq.aw.user),
    .slv_aw_ready_o(mresp.aw_ready), .slv_aw_valid_i(mreq.aw_valid),
    .slv_ar_addr_i(mreq.ar.addr), .slv_ar_prot_i(mreq.ar.prot), .slv_ar_region_i(mreq.ar.region),
    .slv_ar_len_i(mreq.ar.len), .slv_ar_size_i(mreq.ar.size), .slv_ar_burst_i(mreq.ar.burst),
    .slv_ar_lock_i(mreq.ar.lock), .slv_ar_cache_i(mreq.ar.cache), .slv_ar_qos_i(mreq.ar.qos),
    .slv_ar_id_i(mreq.ar.id), .slv_ar_user_i(mreq.ar.user),
    .slv_ar_ready_o(mresp.ar_ready), .slv_ar_valid_i(mreq.ar_valid),
    .slv_w_data_i(mreq.w.data), .slv_w_strb_i(mreq.w.strb), .slv_w_user_i(mreq.w.user),
    .slv_w_last_i(mreq.w.last), .slv_w_ready_o(mresp.w_ready), .slv_w_valid_i(mreq.w_valid),
    .slv_r_data_o(mresp.r.data), .slv_r_resp_o(mresp.r.resp), .slv_r_last_o(mresp.r.last),
    .slv_r_id_o(mresp.r.id), .slv_r_user_o(mresp.r.user), .slv_r_ready_i(mreq.r_ready),
    .slv_r_valid_o(mresp.r_valid),
    .slv_b_resp_o(mresp.b.resp), .slv_b_id_o(mresp.b.id), .slv_b_user_o(mresp.b.user),
    .slv_b_ready_i(mreq.b_ready), .slv_b_valid_o(mresp.b_valid),
    .mst_aw_addr_o(areq.aw.addr), .mst_aw_prot_o(areq.aw.prot), .mst_aw_region_o(areq.aw.region),
    .mst_aw_atop_o(areq.aw.atop), .mst_aw_len_o(areq.aw.len), .mst_aw_size_o(areq.aw.size),
    .mst_aw_burst_o(areq.aw.burst), .mst_aw_lock_o(areq.aw.lock), .mst_aw_cache_o(areq.aw.cache),
    .mst_aw_qos_o(areq.aw.qos), .mst_aw_id_o(areq.aw.id), .mst_aw_user_o(areq.aw.user),
    .mst_aw_ready_i(aresp.aw_ready), .mst_aw_valid_o(areq.aw_valid),
    .mst_ar_addr_o(areq.ar.addr), .mst_ar_prot_o(areq.ar.prot), .mst_ar_region_o(areq.ar.region),
    .mst_ar_len_o(areq.ar.len), .mst_ar_size_o(areq.ar.size), .mst_ar_burst_o(areq.ar.burst),
    .mst_ar_lock_o(areq.ar.lock), .mst_ar_cache_o(areq.ar.cache), .mst_ar_qos_o(areq.ar.qos),
    .mst_ar_id_o(areq.ar.id), .mst_ar_user_o(areq.ar.user),
    .mst_ar_ready_i(aresp.ar_ready), .mst_ar_valid_o(areq.ar_valid),
    .mst_w_data_o(areq.w.data), .mst_w_strb_o(areq.w.strb), .mst_w_user_o(areq.w.user),
    .mst_w_last_o(areq.w.last), .mst_w_ready_i(aresp.w_ready), .mst_w_valid_o(areq.w_valid),
    .mst_r_data_i(aresp.r.data), .mst_r_resp_i(aresp.r.resp), .mst_r_last_i(aresp.r.last),
    .mst_r_id_i(aresp.r.id), .mst_r_user_i(aresp.r.user), .mst_r_ready_o(areq.r_ready),
    .mst_r_valid_i(aresp.r_valid),
    .mst_b_resp_i(aresp.b.resp), .mst_b_id_i(aresp.b.id), .mst_b_user_i(aresp.b.user),
    .mst_b_ready_o(areq.b_ready), .mst_b_valid_i(aresp.b_valid));

  assign aresp.r.user = '0;
  assign aresp.b.user = '0;

  axi2sbus #(.IW(MW), .AW(64)) u_bridge (
    .clk(clk), .rst_n(rst_n),
    .aw_valid(areq.aw_valid), .aw_ready(aresp.aw_ready), .aw_id(areq.aw.id), .aw_addr(areq.aw.addr),
    .aw_len(areq.aw.len), .aw_size(areq.aw.size), .aw_burst(areq.aw.burst),
    .w_valid(areq.w_valid), .w_ready(aresp.w_ready), .w_data(areq.w.data), .w_strb(areq.w.strb),
    .w_last(areq.w.last), .b_valid(aresp.b_valid), .b_ready(areq.b_ready), .b_id(aresp.b.id),
    .b_resp(aresp.b.resp), .ar_valid(areq.ar_valid), .ar_ready(aresp.ar_ready), .ar_id(areq.ar.id),
    .ar_addr(areq.ar.addr), .ar_len(areq.ar.len), .ar_size(areq.ar.size), .ar_burst(areq.ar.burst),
    .r_valid(aresp.r_valid), .r_ready(areq.r_ready), .r_id(aresp.r.id), .r_data(aresp.r.data),
    .r_resp(aresp.r.resp), .r_last(aresp.r.last),
    .m_req(s_req), .m_we(s_we), .m_addr(s_addr), .m_wdata(s_wdata),
    .m_gnt(s_gnt), .m_rvalid(s_rvalid), .m_rdata(cpu_rdata_mux), .m_err(s_err), .m_lock(s_lock));

  // ---------------- one master port; local CLINT/PLIC intercepted ----------------
  logic        busy, local_q;
  logic [31:0] a;
  logic        is_local, accept, we_sel;
  logic [63:0] wd_sel;
  assign a        = s_addr;
  assign we_sel   = s_we;
  assign wd_sel   = s_wdata;
  assign is_local = (a[31:24] == 8'h02) || (a[31:24] == 8'h0C);
  assign cpu_req   = !busy && s_req && !is_local;
  assign cpu_we    = s_we;
  assign cpu_addr  = s_addr;
  assign cpu_wdata = s_wdata;
  assign accept    = !busy && s_req && (is_local || cpu_gnt);
  assign s_gnt     = accept;
  assign s_rvalid  = busy && (local_q ? 1'b1 : cpu_rvalid);
  assign s_err     = busy && !local_q && cpu_err;
  assign cpu_rdata_mux = local_q ? local_rdata : cpu_rdata;

  // CLINT + PLIC state
  logic [63:0]       mtime;
  logic [N*64-1:0]   mtimecmp;
  logic [31:0]       tdiv;
  logic [NSRC:1]     pend;
  logic [N*32-1:0]   pl_en;
  logic [NSRC:1]     claimed;
  logic [31:0]       claim_id [N];

  always_comb begin
    for (int h = 0; h < N; h++) begin
      claim_id[h] = '0;
      for (int s = NSRC; s >= 1; s--) if (pend[s] && !claimed[s] && pl_en[h*32 + s]) claim_id[h] = s;
      meip[h] = claim_id[h] != 0;
      mtip[h] = mtime >= mtimecmp[h*64 +: 64];
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      busy <= 1'b0; local_q <= 1'b0; local_rdata <= '0;
      mtime <= '0; mtimecmp <= '1; tdiv <= '0; msip <= '0; pend <= '0; pl_en <= '0; claimed <= '0;
    end else begin
      // timebase
      if (tdiv + 1 == TIME_DIV) begin tdiv <= '0; mtime <= mtime + 1; end else tdiv <= tdiv + 1;
      // level-sensitive sources latch pending until claimed
      for (int s = 1; s <= NSRC; s++) if (irq_src[s-1] && !claimed[s]) pend[s] <= 1'b1;
      if (accept) begin
        busy <= 1'b1; local_q <= is_local;
        if (is_local) begin
          local_rdata <= '0;
          if (a[31:24] == 8'h02) begin                                       // CLINT
            for (int h = 0; h < N; h++) begin
              if (a[23:0] == 24'(4*h)) begin
                local_rdata <= {63'd0, msip[h]};
                if (we_sel) msip[h] <= wd_sel[0];
              end
              if (a[23:0] == 24'(32'h4000 + 8*h)) begin
                local_rdata <= mtimecmp[h*64 +: 64];
                if (we_sel) mtimecmp[h*64 +: 64] <= wd_sel;
              end
            end
            if (a[23:0] == 24'hBFF8) begin local_rdata <= mtime; if (we_sel) mtime <= wd_sel; end
          end else begin                                                      // PLIC
            if (a[23:0] == 24'h1000) local_rdata <= 64'(pend);
            for (int h = 0; h < N; h++) begin
              if (a[23:0] == 24'(32'h2000 + 32'h80 * h)) begin
                local_rdata <= 64'(pl_en[h*32 +: 32]);
                if (we_sel) pl_en[h*32 +: 32] <= wd_sel[31:0];
              end
              if (a[23:0] == 24'(32'h20_0004 + 32'h1000 * h)) begin
                if (we_sel) begin                                             // complete
                  if (wd_sel[31:0] >= 1 && wd_sel[31:0] <= NSRC) claimed[wd_sel[31:0]] <= 1'b0;
                end else begin                                                // claim
                  local_rdata <= {32'd0, claim_id[h]};
                  if (claim_id[h] != 0) begin claimed[claim_id[h]] <= 1'b1; pend[claim_id[h]] <= 1'b0; end
                end
              end
            end
          end
        end
      end else if (busy && (local_q || cpu_rvalid)) busy <= 1'b0;
    end
  end
endmodule
