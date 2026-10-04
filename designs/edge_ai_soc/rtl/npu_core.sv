// Programmable NPU core: tiling controller + scratch buffers + R x C systolic array (OS dataflow)
// + requantization. Computes C[MT*R x NT*C] = A[MT*R x K] * W[K x NT*C].
// OS dataflow: the large K dimension is the inner loop, fill/drain R+C-2 cycles per tile.
// Buffer layouts (written by DMA / host through the h_* port):
//   ABUF[mi*K + k] = A[mi*R + 0..R-1][k]  (R x 16-bit, INT8 sign-extended or INT16)
//   WBUF[nj*K + k] = W[k][nj*C + 0..C-1]  (C x 8-bit)
//   CBUF[(mi*NT + nj)*R + i] = row i of tile (mi, nj)  (C x 32-bit)
// Output: RAW32 (acc) or INT8 y = sat8(rnd(acc * MULT, SHIFT) + ZP), ReLU clamps at ZP.
// Registers: 0x00 CTRL (W bit0 start) / STATUS {err, done, busy}, 0x04 MT, 0x08 NT, 0x0C K,
//   0x10 CFG {relu, quant, prec16}, 0x14 MULT, 0x18 SHIFT, 0x1C ZP, 0x20 CYCLES, 0x24 TILES.
module npu_core #(parameter int R = 4, parameter int C = 4, parameter int ADEPTH = 256,
                  parameter int WDEPTH = 256, parameter int CDEPTH = 256) (
  input  logic              clk,
  input  logic              rst_n,
  input  logic              r_req,
  input  logic              r_we,
  input  logic [7:0]        r_addr,
  input  logic [31:0]       r_wdata,
  output logic [31:0]       r_rdata,
  // buffer access port (sel 0 = ABUF, 1 = WBUF, 2 = CBUF); 1-cycle read latency
  input  logic              h_req,
  input  logic              h_we,
  input  logic [1:0]        h_sel,
  input  logic [15:0]       h_addr,
  input  logic [C*32-1:0]   h_wdata,
  output logic [C*32-1:0]   h_rdata,
  output logic              irq
);
  // ---------------- registers ----------------
  logic [15:0] mt, nt, kk;
  logic        prec16, quant, relu;
  logic signed [31:0] mult;
  logic [5:0]  shift;
  logic signed [7:0] zp;
  logic        busy, done, err;
  logic [31:0] cycles, tiles;

  always_comb begin
    case (r_addr)
      8'h00:   r_rdata = {29'd0, err, done, busy};
      8'h04:   r_rdata = {16'd0, mt};
      8'h08:   r_rdata = {16'd0, nt};
      8'h0C:   r_rdata = {16'd0, kk};
      8'h10:   r_rdata = {29'd0, relu, quant, prec16};
      8'h14:   r_rdata = mult;
      8'h18:   r_rdata = {26'd0, shift};
      8'h1C:   r_rdata = {{24{zp[7]}}, zp};
      8'h20:   r_rdata = cycles;
      8'h24:   r_rdata = tiles;
      default: r_rdata = '0;
    endcase
  end

  // ---------------- buffers ----------------

  logic [R*16-1:0] a_q;
  logic [C*8-1:0]  w_q;
  logic [15:0]     a_ra, w_ra;
  logic            c_we;
  logic [15:0]     c_wa;
  logic [C*32-1:0] c_wd;

  // buffers through the foundry-mappable RAM wrapper
  localparam int AA = $clog2(ADEPTH), WA = $clog2(WDEPTH), CA = $clog2(CDEPTH);
  ram_1r1w #(.W(R*16), .D(ADEPTH)) u_abuf (.clk(clk), .we(h_req && h_we && h_sel == 2'd0),
    .waddr(h_addr[AA-1:0]), .wdata(h_wdata[R*16-1:0]), .re(1'b1), .raddr(a_ra[AA-1:0]), .rdata(a_q));
  ram_1r1w #(.W(C*8), .D(WDEPTH)) u_wbuf (.clk(clk), .we(h_req && h_we && h_sel == 2'd1),
    .waddr(h_addr[WA-1:0]), .wdata(h_wdata[C*8-1:0]), .re(1'b1), .raddr(w_ra[WA-1:0]), .rdata(w_q));
  ram_1r1w #(.W(C*32), .D(CDEPTH)) u_cbuf (.clk(clk), .we(c_we || (h_req && h_we && h_sel == 2'd2)),
    .waddr(c_we ? c_wa[CA-1:0] : h_addr[CA-1:0]), .wdata(c_we ? c_wd : h_wdata), .re(1'b1),
    .raddr(h_addr[CA-1:0]), .rdata(h_rdata));

  // ---------------- array ----------------
  logic            feed, feed_first;      // registered alongside a_q / w_q
  logic [R*C*32-1:0] acc_flat;
  logic            c_valid_unused;
  logic [C*32-1:0] c_row_unused;
  npu_array #(.R(R), .C(C)) u_arr (
    .clk(clk), .rst_n(rst_n), .en(1'b1), .mode(1'b1), .prec16(prec16), .w_load(1'b0),
    .w_row(feed ? w_q : '0), .a_valid(1'b0), .a_row(feed ? a_q : '0), .os_first(feed & feed_first),
    .c_valid(c_valid_unused), .c_row(c_row_unused), .acc_flat(acc_flat));

  // ---------------- requantization (pipelined: row register -> multiply -> round/clamp) ----------------
  // stage 2 of the write-back pipeline: rounding shift, zero point, ReLU, saturation of acc*MULT
  function automatic logic [31:0] requant_tail(input logic signed [63:0] p);
    logic signed [63:0] rr;
    logic signed [63:0] y;
    rr = (shift == 0) ? p : ((p + (64'sd1 <<< (shift - 1))) >>> shift);
    y  = rr + 64'(zp);
    if (relu && y < 64'(zp)) y = 64'(zp);
    if (y > 127) y = 127;
    if (y < -128) y = -128;
    requant_tail = 32'(y);
  endfunction

  // ---------------- tiling controller ----------------
  localparam logic [2:0] S_IDLE = 3'd0, S_STREAM = 3'd1, S_DRAIN = 3'd2, S_WRITE = 3'd3, S_FLUSH = 3'd4;
  logic [2:0]  st;
  // write-back pipeline: stage A = selected row, stage B = products; cbuf written from stage B
  logic              va, vb;
  logic [15:0]       wa_a, wa_b;
  logic [C*32-1:0]   row_a, raw_b;
  logic [C*64-1:0]   prod_b;
  logic [1:0]        fl;
  logic [15:0] mi, nj, k, i_row;
  logic [7:0]  dcnt;
  logic        streaming;
  logic [R*C*32-1:0] cap;

  wire start = r_req && r_we && r_addr == 8'h00 && r_wdata[0] && !busy;

  always_comb begin
    a_ra = mi * kk + k;
    w_ra = nj * kk + k;
    c_we = vb;
    c_wa = wa_b;
    for (int j = 0; j < C; j++)
      c_wd[j*32 +: 32] = quant ? requant_tail($signed(prod_b[j*64 +: 64])) : raw_b[j*32 +: 32];
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      mt <= 16'd1; nt <= 16'd1; kk <= 16'd1; prec16 <= 1'b0; quant <= 1'b0; relu <= 1'b0;
      mult <= 32'sd1; shift <= '0; zp <= '0;
      busy <= 1'b0; done <= 1'b0; err <= 1'b0; cycles <= '0; tiles <= '0;
      st <= S_IDLE; mi <= '0; nj <= '0; k <= '0; i_row <= '0; dcnt <= '0;
      streaming <= 1'b0; feed <= 1'b0; feed_first <= 1'b0; cap <= '0;
      va <= 1'b0; vb <= 1'b0; wa_a <= '0; wa_b <= '0; row_a <= '0; raw_b <= '0; prod_b <= '0; fl <= '0;
    end else begin
      if (r_req && r_we && !busy)
        case (r_addr)
          8'h04: mt <= r_wdata[15:0];
          8'h08: nt <= r_wdata[15:0];
          8'h0C: kk <= r_wdata[15:0];
          8'h10: {relu, quant, prec16} <= r_wdata[2:0];
          8'h14: mult <= r_wdata;
          8'h18: shift <= r_wdata[5:0];
          8'h1C: zp <= r_wdata[7:0];
          default: ;
        endcase
      // write-back pipeline
      va   <= (st == S_WRITE);
      wa_a <= (mi * nt + nj) * 16'(R) + i_row;
      for (int j = 0; j < C; j++) row_a[j*32 +: 32] <= cap[(i_row*C + j)*32 +: 32];
      vb    <= va;
      wa_b  <= wa_a;
      raw_b <= row_a;
      for (int j = 0; j < C; j++) prod_b[j*64 +: 64] <= 64'($signed(row_a[j*32 +: 32])) * 64'(mult);
      // operands read this cycle arrive next cycle together with feed
      feed       <= streaming;
      feed_first <= streaming && k == 0;
      if (busy) cycles <= cycles + 1;
      if (start) begin
        done <= 1'b0; err <= 1'b0; cycles <= '0; tiles <= '0;
        if (mt == 0 || nt == 0 || kk == 0 ||
            32'(mt) * 32'(kk) > ADEPTH || 32'(nt) * 32'(kk) > WDEPTH || 32'(mt) * 32'(nt) * R > CDEPTH) begin
          err <= 1'b1; done <= 1'b1;               // layer does not fit the buffers: tile in software
        end else begin
          busy <= 1'b1; st <= S_STREAM; mi <= '0; nj <= '0; k <= '0; streaming <= 1'b1;
        end
      end
      case (st)
        S_STREAM: if (k + 1 == kk) begin streaming <= 1'b0; st <= S_DRAIN; dcnt <= '0; end
                  else k <= k + 1;
        S_DRAIN:  if (dcnt == 8'(R + C + 1)) begin cap <= acc_flat; st <= S_WRITE; i_row <= '0; end  // + PE pipeline stages
                  else dcnt <= dcnt + 1;
        S_WRITE:  if (i_row + 1 == 16'(R)) begin st <= S_FLUSH; fl <= '0; end
                  else i_row <= i_row + 1;
        S_FLUSH:  if (fl != 2'd2) fl <= fl + 1;       // let the last rows leave the write-back pipeline
                  else begin
                    tiles <= tiles + 1;
                    k <= '0;
                    if (nj + 1 < nt) begin nj <= nj + 1; st <= S_STREAM; streaming <= 1'b1; end
                    else if (mi + 1 < mt) begin nj <= '0; mi <= mi + 1; st <= S_STREAM; streaming <= 1'b1; end
                    else begin st <= S_IDLE; busy <= 1'b0; done <= 1'b1; end
                  end
        default: ;
      endcase
    end
  end

  assign irq = done;
endmodule
