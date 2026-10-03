// AXI4 slave -> Auralis SoC bus master (req/gnt, 64-bit words, one outstanding).
// Handles INCR/FIXED/WRAP bursts beat by beat (64-bit beats; narrower sizes are single-beat).
// The SoC bus has no byte strobes: a partial write (strb != 'hFF) is a read-modify-write.
// AW is served before AR when both are pending; responses are SLVERR on bus errors.
// Atomics (ATOP) must be resolved upstream (axi_riscv_atomics) - this bridge sees plain AXI.
module axi2sbus #(parameter int IW = 4, parameter int AW = 64) (
  input  logic          clk,
  input  logic          rst_n,
  // AXI slave
  input  logic          aw_valid,
  output logic          aw_ready,
  input  logic [IW-1:0] aw_id,
  input  logic [AW-1:0] aw_addr,
  input  logic [7:0]    aw_len,
  input  logic [2:0]    aw_size,
  input  logic [1:0]    aw_burst,
  input  logic          w_valid,
  output logic          w_ready,
  input  logic [63:0]   w_data,
  input  logic [7:0]    w_strb,
  input  logic          w_last,
  output logic          b_valid,
  input  logic          b_ready,
  output logic [IW-1:0] b_id,
  output logic [1:0]    b_resp,
  input  logic          ar_valid,
  output logic          ar_ready,
  input  logic [IW-1:0] ar_id,
  input  logic [AW-1:0] ar_addr,
  input  logic [7:0]    ar_len,
  input  logic [2:0]    ar_size,
  input  logic [1:0]    ar_burst,
  output logic          r_valid,
  input  logic          r_ready,
  output logic [IW-1:0] r_id,
  output logic [63:0]   r_data,
  output logic [1:0]    r_resp,
  output logic          r_last,
  // SoC bus master
  output logic          m_req,
  output logic          m_we,
  output logic [31:0]   m_addr,
  output logic [63:0]   m_wdata,
  input  logic          m_gnt,
  input  logic          m_rvalid,
  input  logic [63:0]   m_rdata,
  input  logic          m_err,
  output logic          m_lock      // hold the arbiter across a read-modify-write (atomic byte stores)
);
  localparam logic [2:0] IDLE = 3'd0, WDATA = 3'd1, RMW_RD = 3'd2, WRITE = 3'd3, BRESP = 3'd4,
                         READ = 3'd5, RDATA = 3'd6;
  logic [2:0]    st;
  logic [IW-1:0] id;
  logic [AW-1:0] addr;
  logic [7:0]    len, beat;
  logic [2:0]    size;
  logic [1:0]    burst;
  logic [63:0]   wd;
  logic [7:0]    ws;
  logic          wl, err, waiting;
  logic [63:0]   rd_q;
  logic          wl_rmw;   // current WRITE completes an RMW

  // next beat address (AXI burst rules; 64-bit bus)
  function automatic logic [AW-1:0] next_addr(input logic [AW-1:0] a, input logic [2:0] sz,
                                              input logic [1:0] bt, input logic [7:0] ln);
    logic [AW-1:0] step, wrap_mask, n;
    step = AW'(1) << sz;
    n = a + step;
    if (bt == 2'b00) n = a;                                   // FIXED
    else if (bt == 2'b10) begin                               // WRAP
      wrap_mask = (AW'(ln) + 1) * step - 1;
      n = (a & ~wrap_mask) | ((a + step) & wrap_mask);
    end
    next_addr = n;
  endfunction

  function automatic logic [63:0] merge(input logic [63:0] old, input logic [63:0] nw, input logic [7:0] s);
    for (int i = 0; i < 8; i++) merge[i*8 +: 8] = s[i] ? nw[i*8 +: 8] : old[i*8 +: 8];
  endfunction

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      st <= IDLE; id <= '0; addr <= '0; len <= '0; beat <= '0; size <= '0; burst <= '0;
      wd <= '0; ws <= '0; wl <= 1'b0; err <= 1'b0; waiting <= 1'b0; rd_q <= '0; wl_rmw <= 1'b0;
    end else begin
      case (st)
        IDLE:
          if (aw_valid) begin
            st <= WDATA; id <= aw_id; addr <= aw_addr; len <= aw_len; size <= aw_size; burst <= aw_burst;
            beat <= '0; err <= 1'b0;
          end else if (ar_valid) begin
            st <= READ; id <= ar_id; addr <= ar_addr; len <= ar_len; size <= ar_size; burst <= ar_burst;
            beat <= '0; err <= 1'b0; waiting <= 1'b0;
          end
        WDATA:
          if (w_valid) begin
            wd <= w_data; ws <= w_strb; wl <= w_last; waiting <= 1'b0; wl_rmw <= 1'b0;
            st <= (w_strb == 8'hFF) ? WRITE : (w_strb == 8'h00 ? WRITE : RMW_RD);
          end
        RMW_RD:
          if (!waiting) begin
            if (m_gnt) waiting <= 1'b1;
          end else if (m_rvalid) begin
            waiting <= 1'b0;
            if (m_err) err <= 1'b1;
            wd <= merge(m_rdata, wd, ws);
            ws <= 8'hFF;
            wl_rmw <= 1'b1;
            st <= WRITE;
          end
        WRITE:
          if (ws == 8'h00) begin                                   // no bytes enabled: nothing to write
            if (wl) st <= BRESP; else begin addr <= next_addr(addr, size, burst, len); st <= WDATA; end
          end else if (!waiting) begin
            if (m_gnt) waiting <= 1'b1;
          end else if (m_rvalid) begin
            waiting <= 1'b0;
            if (m_err) err <= 1'b1;
            if (wl) st <= BRESP;
            else begin addr <= next_addr(addr, size, burst, len); st <= WDATA; end
          end
        BRESP: if (b_ready) st <= IDLE;
        READ:
          if (!waiting) begin
            if (m_gnt) waiting <= 1'b1;
          end else if (m_rvalid) begin
            waiting <= 1'b0;
            rd_q <= m_rdata;
            if (m_err) err <= 1'b1;
            st <= RDATA;
          end
        RDATA:
          if (r_ready) begin
            if (beat == len) st <= IDLE;
            else begin beat <= beat + 1; addr <= next_addr(addr, size, burst, len); st <= READ; err <= 1'b0; end
          end
        default: st <= IDLE;
      endcase
    end
  end

  assign aw_ready = (st == IDLE) && aw_valid;
  assign ar_ready = (st == IDLE) && !aw_valid && ar_valid;
  assign w_ready  = (st == WDATA);
  assign m_lock   = (st == RMW_RD) || (st == WRITE && wl_rmw);
  assign m_req    = !waiting && (st == RMW_RD || st == READ || (st == WRITE && ws != 8'h00));
  assign m_we     = (st == WRITE);
  assign m_addr   = {addr[31:3], 3'b000};
  assign m_wdata  = wd;
  assign b_valid  = (st == BRESP);
  assign b_id     = id;
  assign b_resp   = err ? 2'b10 : 2'b00;
  assign r_valid  = (st == RDATA);
  assign r_id     = id;
  assign r_data   = rd_q;
  assign r_resp   = err ? 2'b10 : 2'b00;
  assign r_last   = (beat == len);
endmodule
