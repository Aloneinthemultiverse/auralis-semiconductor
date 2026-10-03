// I/O physical memory protection for bus masters (NPU, DMA): accelerator isolation.
// N regions [base, limit) with R/W permission; default deny. A locked region cannot be
// rewritten until reset (Smepmp-style lock). Denied accesses are not forwarded: the master
// gets an error response, the first violation's address/type is logged and an interrupt raised.
// Registers: region k at 0x10*k: +0 BASE, +4 LIMIT, +8 CFG {lock, w, r, en};
// 0xF0 VIOL_ADDR, 0xF4 VIOL_INFO {write, valid} (write 1 to bit0 clears).
module iopmp #(parameter int N = 8) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        r_req,
  input  logic        r_we,
  input  logic [7:0]  r_addr,
  input  logic [31:0] r_wdata,
  output logic [31:0] r_rdata,
  input  logic        s_req,
  input  logic        s_we,
  input  logic [31:0] s_addr,
  input  logic [63:0] s_wdata,
  output logic        s_gnt,
  output logic        s_rvalid,
  output logic [63:0] s_rdata,
  output logic        s_err,
  output logic        m_req,
  output logic        m_we,
  output logic [31:0] m_addr,
  output logic [63:0] m_wdata,
  input  logic        m_gnt,
  input  logic        m_rvalid,
  input  logic [63:0] m_rdata,
  input  logic        m_err,
  output logic        irq
);
  logic [N*32-1:0] base, lim;
  logic [N*4-1:0]  cfg;
  logic [31:0]     viol_addr;
  logic            viol_v, viol_w;
  logic            allow;
  logic            deny_resp;

  always_comb begin
    allow = 1'b0;
    for (int k = 0; k < N; k++)
      if (cfg[k*4] && s_addr >= base[k*32 +: 32] && s_addr < lim[k*32 +: 32] &&
          (s_we ? cfg[k*4+2] : cfg[k*4+1]))
        allow = 1'b1;
  end

  always_comb begin
    r_rdata = '0;
    if (r_addr == 8'hF0) r_rdata = viol_addr;
    else if (r_addr == 8'hF4) r_rdata = {30'd0, viol_w, viol_v};
    else
      for (int k = 0; k < N; k++)
        if (r_addr[7:4] == 4'(k)) begin
          if (r_addr[3:0] == 4'h0) r_rdata = base[k*32 +: 32];
          if (r_addr[3:0] == 4'h4) r_rdata = lim[k*32 +: 32];
          if (r_addr[3:0] == 4'h8) r_rdata = {28'd0, cfg[k*4 +: 4]};
        end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      base <= '0; lim <= '0; cfg <= '0;
      viol_addr <= '0; viol_v <= 1'b0; viol_w <= 1'b0; deny_resp <= 1'b0;
    end else begin
      if (r_req && r_we) begin
        if (r_addr == 8'hF4 && r_wdata[0]) viol_v <= 1'b0;
        for (int k = 0; k < N; k++)
          if (r_addr[7:4] == 4'(k) && !cfg[k*4+3]) begin
            if (r_addr[3:0] == 4'h0) base[k*32 +: 32] <= r_wdata;
            if (r_addr[3:0] == 4'h4) lim[k*32 +: 32]  <= r_wdata;
            if (r_addr[3:0] == 4'h8) cfg[k*4 +: 4]    <= r_wdata[3:0];
          end
      end
      deny_resp <= s_req && !allow;
      if (s_req && !allow && !viol_v) begin viol_v <= 1'b1; viol_addr <= s_addr; viol_w <= s_we; end
    end
  end

  assign m_req    = s_req && allow;
  assign m_we     = s_we;
  assign m_addr   = s_addr;
  assign m_wdata  = s_wdata;
  assign s_gnt    = allow ? m_gnt : s_req;
  assign s_rvalid = deny_resp | m_rvalid;
  assign s_rdata  = deny_resp ? '0 : m_rdata;
  assign s_err    = deny_resp | m_err;
  assign irq      = viol_v;
endmodule
