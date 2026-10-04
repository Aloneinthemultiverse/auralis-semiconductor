// Protocol and safety assertions for soc_top, attached with `bind` (no RTL changes).
// Checked every cycle in simulation; also usable as formal properties.
module soc_sva (
  input logic        clk,
  input logic        rst_n,
  // interconnect
  input logic        cpu_gnt,
  input logic        p_gnt,
  input logic        busy,
  // isolation
  input logic        iop_m_req,
  input logic        iop_allow,
  // secure boot
  input logic        cpu_rst_n,
  input logic        boot_ok,
  input logic        boot_fail,
  // watchdog / errors
  input logic        bark,
  input logic        bite,
  input logic        sram_uncorr,
  input logic        err_fatal,
  input logic        sys_reset_req,
  // power
  input logic [3:0]  pwr_en,
  input logic [3:0]  iso_en,
  input logic [3:0]  dom_clk_en
);
  logic seen_bark, prev_cpu_rst_n, unc_d1, unc_d2;
  always_ff @(posedge clk) begin
    if (!rst_n) begin seen_bark <= 1'b0; prev_cpu_rst_n <= 1'b0; unc_d1 <= 1'b0; unc_d2 <= 1'b0; end
    else begin
      if (bark) seen_bark <= 1'b1;
      prev_cpu_rst_n <= cpu_rst_n;
      unc_d1 <= sram_uncorr; unc_d2 <= unc_d1;
    end
  end

  // A1: the interconnect never grants two masters in the same cycle
  a_one_grant: assert property (@(posedge clk) disable iff (!rst_n) !(cpu_gnt && p_gnt))
    else $error("SVA a_one_grant: CPU and DMA granted together");
  // A2: nothing is granted while a transaction is outstanding (one outstanding transaction)
  a_no_grant_busy: assert property (@(posedge clk) disable iff (!rst_n) busy |-> !(cpu_gnt || p_gnt))
    else $error("SVA a_no_grant_busy: grant while busy");
  // A3: isolation - a DMA/NPU access only reaches the fabric if an IOPMP region allows it
  a_iopmp: assert property (@(posedge clk) disable iff (!rst_n) iop_m_req |-> iop_allow)
    else $error("SVA a_iopmp: denied access forwarded");
  // A4: CPUs leave reset only after a successful secure boot, never after a failure
  a_boot_gate: assert property (@(posedge clk) disable iff (!rst_n) cpu_rst_n |-> (boot_ok && !boot_fail))
    else $error("SVA a_boot_gate: CPUs released without verified boot");
  // A5: the release is one-way until power-on reset
  a_boot_oneway: assert property (@(posedge clk) disable iff (!rst_n) prev_cpu_rst_n |-> cpu_rst_n)
    else $error("SVA a_boot_oneway: CPUs put back in reset");
  // A6: the watchdog bites only after it has barked
  a_bark_first: assert property (@(posedge clk) disable iff (!rst_n) bite |-> seen_bark)
    else $error("SVA a_bark_first: bite without bark");
  // A7: an uncorrectable ECC error becomes fatal (reset request) within 2 cycles
  a_ecc_fatal: assert property (@(posedge clk) disable iff (!rst_n) unc_d2 |-> (err_fatal && sys_reset_req))
    else $error("SVA a_ecc_fatal: uncorrectable ECC not escalated");
  // A8: a powered-off domain is always isolated and never clocked
  a_pwr_iso: assert property (@(posedge clk) disable iff (!rst_n) ((~pwr_en & ~iso_en) == 4'b0) && ((~pwr_en & dom_clk_en) == 4'b0))
    else $error("SVA a_pwr_iso: off domain not isolated or still clocked");
endmodule

bind soc_top soc_sva u_sva (
  .clk(clk), .rst_n(rst_n), .cpu_gnt(cpu_gnt), .p_gnt(p_gnt), .busy(busy),
  .iop_m_req(u_iopmp.m_req), .iop_allow(u_iopmp.allow),
  .cpu_rst_n(cpu_rst_n), .boot_ok(boot_ok), .boot_fail(boot_fail),
  .bark(bark), .bite(bite), .sram_uncorr(sr_uncorr), .err_fatal(err_fatal), .sys_reset_req(sys_reset_req),
  .pwr_en(pwr_en), .iso_en(iso_en), .dom_clk_en(dom_clk_en));
