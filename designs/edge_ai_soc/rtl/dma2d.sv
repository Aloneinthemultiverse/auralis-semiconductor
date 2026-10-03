// 2-D strided DMA (tile mover between LPDDR4 / SRAM / NPU buffers).
// Copies ROWS x LEN 64-bit words: src + r*SSTRIDE + i*8 -> dst + r*DSTRIDE + i*8.
// Registers (32-bit, byte offsets): 0x00 CTRL (W: bit0 start, bit1 irq_en) / STATUS (R: bit0 busy,
// bit1 done, bit2 err), 0x04 SRC, 0x08 DST, 0x0C LEN, 0x10 ROWS, 0x14 SSTRIDE, 0x18 DSTRIDE.
// Bus master: one outstanding request (m_req held until m_gnt, then wait for m_rvalid).
// The sticky error is cleared when an operation starts.
module dma2d (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        r_req,
  input  logic        r_we,
  input  logic [7:0]  r_addr,
  input  logic [31:0] r_wdata,
  output logic [31:0] r_rdata,
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
  localparam logic [1:0] IDLE = 2'd0, RD = 2'd1, WR = 2'd2;
  logic [31:0] src, dst, len, rows, sstr, dstr;
  logic        busy, done, err, irq_en;
  logic [31:0] i, r;
  logic [63:0] buf_q;
  logic [1:0]  st;
  logic        wait_r;
  logic        start;

  always_comb begin
    case (r_addr)
      8'h00:   r_rdata = {29'd0, err, done, busy};
      8'h04:   r_rdata = src;
      8'h08:   r_rdata = dst;
      8'h0C:   r_rdata = len;
      8'h10:   r_rdata = rows;
      8'h14:   r_rdata = sstr;
      8'h18:   r_rdata = dstr;
      default: r_rdata = '0;
    endcase
  end

  assign start = r_req && r_we && r_addr == 8'h00 && r_wdata[0] && !busy;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      src <= '0; dst <= '0; len <= '0; rows <= '0; sstr <= '0; dstr <= '0;
      busy <= 1'b0; done <= 1'b0; err <= 1'b0; irq_en <= 1'b0;
      st <= IDLE; i <= '0; r <= '0; buf_q <= '0; wait_r <= 1'b0;
    end else begin
      if (r_req && r_we && !busy)
        case (r_addr)
          8'h00: begin irq_en <= r_wdata[1]; if (!r_wdata[0]) done <= 1'b0; end
          8'h04: src  <= r_wdata;
          8'h08: dst  <= r_wdata;
          8'h0C: len  <= r_wdata;
          8'h10: rows <= r_wdata;
          8'h14: sstr <= r_wdata;
          8'h18: dstr <= r_wdata;
          default: ;
        endcase
      if (start) begin
        err <= 1'b0; done <= 1'b0; i <= '0; r <= '0; wait_r <= 1'b0;
        if (len == 0 || rows == 0) done <= 1'b1;
        else begin busy <= 1'b1; st <= RD; end
      end else if (st != IDLE) begin
        if (!wait_r) begin
          if (m_gnt) wait_r <= 1'b1;
        end else if (m_rvalid) begin
          wait_r <= 1'b0;
          if (m_err) begin
            err <= 1'b1; busy <= 1'b0; done <= 1'b1; st <= IDLE;
          end else if (st == RD) begin
            buf_q <= m_rdata; st <= WR;
          end else if (i + 1 < len) begin
            i <= i + 1; st <= RD;
          end else if (r + 1 < rows) begin
            i <= '0; r <= r + 1; st <= RD;
          end else begin
            busy <= 1'b0; done <= 1'b1; st <= IDLE;
          end
        end
      end
    end
  end

  assign m_req   = (st != IDLE) && !wait_r;
  assign m_we    = (st == WR);
  assign m_addr  = (st == WR) ? dst + r * dstr + (i << 3) : src + r * sstr + (i << 3);
  assign m_wdata = buf_q;
  assign irq     = irq_en & done;
endmodule
