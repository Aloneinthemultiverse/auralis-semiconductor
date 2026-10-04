// Single-clock 1-read / 1-write RAM, 1-cycle read latency (read-before-write on the same address).
// Every on-chip memory of the SoC (ECC SRAM banks, NPU A/W/C buffers) goes through this wrapper so a
// foundry flow can replace it with a compiled macro: define AURALIS_FOUNDRY_RAM and provide
// `foundry_ram_1r1w #(W, D)` (a thin adapter around the customer's SRAM compiler output, e.g. a
// TSMC / Samsung / GF two-port register file or SRAM). Without the define, a behavioural model is used.
module ram_1r1w #(parameter int W = 64, parameter int D = 1024, parameter int AW = $clog2(D)) (
  input  logic          clk,
  input  logic          we,
  input  logic [AW-1:0] waddr,
  input  logic [W-1:0]  wdata,
  input  logic          re,
  input  logic [AW-1:0] raddr,
  output logic [W-1:0]  rdata
);
`ifdef AURALIS_FOUNDRY_RAM
  foundry_ram_1r1w #(.W(W), .D(D)) u_macro (.clk(clk), .we(we), .waddr(waddr), .wdata(wdata),
                                            .re(re), .raddr(raddr), .rdata(rdata));
`else
  logic [W-1:0] mem [D];
  always_ff @(posedge clk) begin
    if (we) mem[waddr] <= wdata;
    if (re) rdata <= mem[raddr];
  end
`endif
endmodule
