// USB 3.0 link layer (one port), over 9-bit link symbols {k, byte} from the 8b/10b PCS.
// Header packet (HP): HPSTART(k 0xFB), 16 header bytes, CRC-16 (0x100B, init 0xFFFF) over the header,
//   link control word {hseq[2:0]}, END (k 0xFD).
// Link commands (LCMD): LCSTART (k 0x5C), {type, arg}, END:
//   LGOOD_n (type 0, arg = hseq of the good HP), LBAD (type 1), LCRD (type 2, a header buffer freed).
// TX: an HP needs a remote header-buffer credit (4 at start); unacknowledged HPs stay in a 4-entry
//   retry buffer; LGOOD_n retires them; LBAD (or a timeout) retransmits every unacknowledged HP (LRTY).
// RX: a good HP with the expected sequence is delivered and answered with LGOOD_n and, once consumed,
//   LCRD; a bad CRC is answered with LBAD; out-of-sequence HPs (lost predecessor) are dropped silently.
module usb3_link #(parameter int TIMEOUT = 600) (
  input  logic         clk,
  input  logic         rst_n,
  input  logic         h_valid,
  input  logic [127:0] h_data,
  output logic         h_ready,
  output logic         r_valid,
  output logic [127:0] r_data,
  output logic [8:0]   tx_sym,
  input  logic [8:0]   rx_sym,
  output logic [15:0]  retries,
  output logic [15:0]  lbad_sent
);
  localparam logic [7:0] HPS = 8'hFB, LCS = 8'h5C, ENDS = 8'hFD;
  function automatic logic [15:0] crc16_b(input logic [15:0] c, input logic [7:0] b);
    logic [15:0] x;
    x = c;
    for (int i = 7; i >= 0; i--) x = (x[15] ^ b[i]) ? ((x << 1) ^ 16'h100B) : (x << 1);
    crc16_b = x;
  endfunction

  // retry buffer
  logic [127:0] rb [4];
  logic [2:0]   rb_seq [4];
  logic [1:0]   head, tail;
  logic [2:0]   cnt, sendq;          // entries buffered / still to (re)send
  logic [1:0]   snext;
  logic [2:0]   tx_hseq;
  logic [2:0]   credits;
  logic [15:0]  timer;
  // pending link commands
  logic         good_p, bad_p, crd_p;
  logic [2:0]   good_seq;
  // tx engine
  localparam logic [1:0] X_IDLE = 2'd0, X_HP = 2'd1, X_LC = 2'd2;
  logic [1:0]   xst;
  logic [4:0]   xi;
  logic [1:0]   xent;
  logic [15:0]  xcrc;
  logic [7:0]   lc_byte;
  // rx
  localparam logic [1:0] R_IDLE = 2'd0, R_HP = 2'd1, R_LC = 2'd2;
  logic [1:0]   rs;
  logic [7:0]   rbuf [20];
  logic [4:0]   rn;
  logic [2:0]   rx_hseq;

  assign h_ready = (cnt < 4) && !(xst == X_IDLE && 1'b0);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      head <= '0; tail <= '0; cnt <= '0; sendq <= '0; snext <= '0; tx_hseq <= '0; credits <= 3'd4; timer <= '0;
      good_p <= 1'b0; bad_p <= 1'b0; crd_p <= 1'b0; good_seq <= '0;
      xst <= X_IDLE; xi <= '0; xent <= '0; xcrc <= '1; lc_byte <= '0; tx_sym <= {1'b1, 8'h00};
      rs <= R_IDLE; rn <= '0; rx_hseq <= '0; r_valid <= 1'b0; r_data <= '0; retries <= '0; lbad_sent <= '0;
    end else begin
      logic [2:0] cnt_n, sq_n, cr_n;
      cnt_n = cnt; sq_n = sendq; cr_n = credits;
      // accept a header packet from the protocol layer
      if (h_valid && h_ready) begin
        rb[tail] <= h_data; rb_seq[tail] <= tx_hseq; tx_hseq <= tx_hseq + 1; tail <= tail + 1;
        cnt_n = cnt_n + 1; sq_n = sq_n + 1;
      end
      if (cnt != 0) timer <= timer + 1; else timer <= '0;

      // ---------------- transmit ----------------
      tx_sym <= {1'b1, 8'h00};
      case (xst)
        X_IDLE:
          if (good_p || bad_p || crd_p) begin
            lc_byte <= good_p ? {5'd0, good_seq} : bad_p ? 8'h10 : 8'h20;
            if (good_p) good_p <= 1'b0; else if (bad_p) begin bad_p <= 1'b0; lbad_sent <= lbad_sent + 1; end
            else crd_p <= 1'b0;
            xst <= X_LC; xi <= '0;
          end else if (timer >= 16'(TIMEOUT) && cnt != 0) begin            // no response: retry all
            snext <= head; sq_n = cnt_n; cr_n = 3'd4; timer <= '0; retries <= retries + 1;
          end else if (sendq != 0 && credits != 0) begin
            xent <= snext; xst <= X_HP; xi <= '0; xcrc <= '1; cr_n = cr_n - 1;
          end
        X_HP: begin
          if (xi == 0) tx_sym <= {1'b1, HPS};
          else if (xi <= 16) begin
            logic [7:0] b;
            b = rb[xent][(xi - 1) * 8 +: 8];
            tx_sym <= {1'b0, b}; xcrc <= crc16_b(xcrc, b);
          end
          else if (xi == 17) tx_sym <= {1'b0, xcrc[15:8]};
          else if (xi == 18) tx_sym <= {1'b0, xcrc[7:0]};
          else if (xi == 19) tx_sym <= {1'b0, {5'd0, rb_seq[xent]}};
          else begin tx_sym <= {1'b1, ENDS}; snext <= xent + 1; if (sq_n != 0) sq_n = sq_n - 1; xst <= X_IDLE; end
          xi <= xi + 1;
        end
        X_LC: begin
          if (xi == 0) tx_sym <= {1'b1, LCS};
          else if (xi == 1) tx_sym <= {1'b0, lc_byte};
          else begin tx_sym <= {1'b1, ENDS}; xst <= X_IDLE; end
          xi <= xi + 1;
        end
        default: xst <= X_IDLE;
      endcase

      // ---------------- receive ----------------
      r_valid <= 1'b0;
      case (rs)
        R_IDLE: if (rx_sym[8]) begin
                  if (rx_sym[7:0] == HPS) begin rs <= R_HP; rn <= '0; end
                  else if (rx_sym[7:0] == LCS) begin rs <= R_LC; rn <= '0; end
                end
        R_HP:   if (rx_sym[8]) begin
                  rs <= R_IDLE;
                  if (rx_sym[7:0] == ENDS && rn == 19) begin
                    logic [15:0] c;
                    c = 16'hFFFF;
                    for (int k = 0; k < 16; k++) c = crc16_b(c, rbuf[k]);
                    if ({rbuf[16], rbuf[17]} != c) bad_p <= 1'b1;
                    else if (rbuf[18][2:0] == rx_hseq) begin
                      for (int k = 0; k < 16; k++) r_data[k*8 +: 8] <= rbuf[k];
                      r_valid <= 1'b1; rx_hseq <= rx_hseq + 1;
                      good_p <= 1'b1; good_seq <= rbuf[18][2:0]; crd_p <= 1'b1;   // consumed at once
                    end else if (3'(rx_hseq - rbuf[18][2:0]) <= 3'd4) begin       // already received: re-ack
                      good_p <= 1'b1; good_seq <= rx_hseq - 1;
                    end
                  end else bad_p <= 1'b1;
                end else if (rn < 5'd20) begin rbuf[rn] <= rx_sym[7:0]; rn <= rn + 1; end
        R_LC:   if (rx_sym[8]) begin
                  rs <= R_IDLE;
                  if (rx_sym[7:0] == ENDS && rn == 1) begin
                    if (rbuf[0][7:4] == 4'h0) begin                                // LGOOD_n: retire up to seq
                      int np;
                      np = 0;
                      for (int k = 0; k < 4; k++)
                        if (k < cnt_n && 3'(rbuf[0][2:0] - rb_seq[2'(head + 2'(k))]) <= 3'd3) np = k + 1;
                      head <= head + 2'(np); cnt_n = cnt_n - 3'(np);
                      if (sq_n > cnt_n) sq_n = cnt_n;
                      timer <= '0;
                    end else if (rbuf[0][7:4] == 4'h1) begin                       // LBAD: retry all
                      if (xst == X_IDLE) begin snext <= head; sq_n = cnt_n; retries <= retries + 1; end
                      cr_n = 3'd4 - (cnt_n - sq_n);                               // re-sent HPs reuse credits
                    end else if (rbuf[0][7:4] == 4'h2) begin                       // LCRD
                      if (cr_n < 4) cr_n = cr_n + 1;
                    end
                  end
                end else if (rn < 5'd2) begin rbuf[rn] <= rx_sym[7:0]; rn <= rn + 1; end
        default: rs <= R_IDLE;
      endcase
      cnt <= cnt_n; sendq <= sq_n; credits <= cr_n;
    end
  end
endmodule
