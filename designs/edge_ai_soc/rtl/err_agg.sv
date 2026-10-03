// SoC error/fault aggregator. N fault sources (pulses or levels): ECC corrected/uncorrectable,
// IOPMP violation, DMA error, bus timeout, watchdog bark/bite, secure-boot failure, ...
// - STATUS: sticky per-source bits (W1C), MASK gates the interrupt.
// - First-fault latch: source id + timestamp of the first unmasked fault; later faults do
//   not overwrite it until cleared, preserving the root cause.
// - COUNT: per-SoC count of corrected (non-fatal) events for wear/SER monitoring.
// - fatal: any source in FATAL_MASK -> reset/safe-state request.
// Registers: 0x0 STATUS (R, W1C), 0x4 MASK, 0x8 FIRST {valid, id[7:0]}, 0xC FIRST_TIME,
//            0x10 COUNT, 0x14 CLEAR (W bit0 clears first-fault latch).
module err_agg #(parameter int N = 16, parameter logic [N-1:0] FATAL_MASK = '0) (
  input  logic         clk,
  input  logic         rst_n,
  input  logic [N-1:0] fault,
  input  logic         r_req,
  input  logic         r_we,
  input  logic [7:0]   r_addr,
  input  logic [31:0]  r_wdata,
  output logic [31:0]  r_rdata,
  output logic         irq,
  output logic         fatal
);
  logic [N-1:0] status, mask;
  logic         first_v;
  logic [7:0]   first_id;
  logic [31:0]  first_t, now, count;
  logic [7:0]   lowest;
  logic [N-1:0] unmasked;

  assign unmasked = fault & ~mask;

  always_comb begin
    lowest = '0;
    for (int k = N - 1; k >= 0; k--) if (unmasked[k]) lowest = 8'(k);
  end

  always_comb begin
    case (r_addr)
      8'h00:   r_rdata = 32'(status);
      8'h04:   r_rdata = 32'(mask);
      8'h08:   r_rdata = {23'd0, first_v, first_id};
      8'h0C:   r_rdata = first_t;
      8'h10:   r_rdata = count;
      default: r_rdata = '0;
    endcase
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      status <= '0; mask <= '0; first_v <= 1'b0; first_id <= '0; first_t <= '0; now <= '0; count <= '0;
    end else begin
      now <= now + 1;
      if (r_req && r_we && r_addr == 8'h00) status <= (status & ~r_wdata[N-1:0]) | fault;
      else status <= status | fault;
      if (r_req && r_we && r_addr == 8'h04) mask <= r_wdata[N-1:0];
      if (r_req && r_we && r_addr == 8'h14 && r_wdata[0]) first_v <= 1'b0;
      else if (!first_v && |unmasked) begin first_v <= 1'b1; first_id <= lowest; first_t <= now; end
      if (|(fault & ~FATAL_MASK)) count <= count + 1;
    end
  end

  assign irq   = |(status & ~mask);
  assign fatal = |(status & FATAL_MASK);
endmodule

// Reset synchronizer: asynchronous assert, synchronous (2-flop) de-assert.
module rst_sync (
  input  logic clk,
  input  logic arst_n,
  output logic rst_n
);
  logic s1;
  always_ff @(posedge clk or negedge arst_n)
    if (!arst_n) {rst_n, s1} <= 2'b00;
    else         {rst_n, s1} <= {s1, 1'b1};
endmodule
