// PCIe data link layer (one port). Symbols on the link are 9 bits {k, byte}: k=1 marks framing
// (STP 0xFB starts a TLP, SDP 0x5C starts a DLLP, END 0xFD ends a packet), as K-codes do in 8b/10b.
// TX: TLPs from the transaction layer get a 12-bit sequence number and LCRC-32 (reflected 0xEDB88320
//     over {seq, payload}), are kept in an 8-entry replay buffer until ACKed; a NAK or the replay
//     timer replays every unacknowledged TLP in order.
// RX: checks LCRC and sequence; the next expected TLP is delivered and ACKed, a bad TLP is NAKed
//     (with the last good sequence), a duplicate is discarded and re-ACKed.
// DLLP: {type (0x00 ACK / 0x10 NAK), 0, seq[11:8], seq[7:0]} + CRC-16 (0x100B, init 0xFFFF).
module pcie_dll #(parameter int MAXB = 32,
                  // replay timer must exceed a full replay buffer on the wire (8 x (MAXB + 8) symbols)
                  // plus the ACK round trip, as the PCIe spec derives it from payload, width and latency
                  parameter int REPLAY_TIMEOUT = 8 * (MAXB + 8) + 400) (
  input  logic       clk,
  input  logic       rst_n,
  // transaction layer TX (one TLP = bytes with t_last)
  input  logic       t_valid,
  input  logic [7:0] t_data,
  input  logic       t_last,
  output logic       t_ready,
  // transaction layer RX
  output logic       r_valid,
  output logic [7:0] r_data,
  output logic       r_last,
  // link symbols
  output logic [8:0] tx_sym,
  input  logic [8:0] rx_sym,
  // statistics
  output logic [15:0] replays,
  output logic [15:0] naks_sent,
  output logic [15:0] dup_dropped
);
  localparam logic [7:0] STP = 8'hFB, SDP = 8'h5C, ENDS = 8'hFD;

  function automatic logic [31:0] crc32_b(input logic [31:0] c, input logic [7:0] b);
    logic [31:0] x;
    x = c ^ {24'd0, b};
    for (int i = 0; i < 8; i++) x = x[0] ? ((x >> 1) ^ 32'hEDB88320) : (x >> 1);
    crc32_b = x;
  endfunction
  function automatic logic [15:0] crc16_b(input logic [15:0] c, input logic [7:0] b);
    logic [15:0] x;
    x = c;
    for (int i = 7; i >= 0; i--) x = (x[15] ^ b[i]) ? ((x << 1) ^ 16'h100B) : (x << 1);
    crc16_b = x;
  endfunction

  // ---------------- replay buffer ----------------
  logic [7:0]  rb_data [8*MAXB];
  logic [5:0]  rb_len  [8];
  logic [11:0] rb_seq  [8];
  logic [2:0]  rb_head, rb_tail;          // head = oldest unacked, tail = next free
  logic [3:0]  rb_count;
  logic [11:0] next_tx_seq;
  // accepting a new TLP from the TL
  logic [5:0]  in_len;
  logic        in_busy;

  logic in_commit;
  assign t_ready = (rb_count < 8) && !in_commit;

  // ---------------- receive state ----------------
  logic [11:0] next_rcv_seq;
  logic        ack_pend, nak_pend, nak_sched;
  logic [11:0] ack_seq;

  // ---------------- transmit scheduler ----------------
  localparam logic [2:0] X_IDLE = 3'd0, X_TLP = 3'd1, X_DLLP = 3'd2;
  logic [2:0]  xst;
  logic [6:0]  xi;                        // symbol index within the packet
  logic [2:0]  x_ent;                     // replay entry being sent
  logic [2:0]  x_next;                    // next entry to (re)send
  logic [3:0]  x_left;                    // entries still to send in this pass
  logic [31:0] x_crc;
  logic [7:0]  x_dllp [4];
  logic [15:0] x_dcrc;
  logic [15:0] timer;

  // ---------------- receive parser ----------------
  localparam logic [1:0] R_IDLE = 2'd0, R_TLP = 2'd1, R_DLLP = 2'd2;
  logic [1:0]  rst_;
  logic [7:0]  rbuf [MAXB + 6];
  logic [6:0]  rn;
  // delivery FIFO (every accepted TLP fits: ACKed TLPs are never dropped for lack of space)
  logic [8:0]  ofifo [256];          // {last, byte}
  logic [7:0]  owp, orp;
  logic [8:0]  ocnt;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      rb_head <= '0; rb_tail <= '0; rb_count <= '0; next_tx_seq <= '0; in_len <= '0; in_busy <= 1'b0;
      in_commit <= 1'b0;
      next_rcv_seq <= '0; ack_pend <= 1'b0; nak_pend <= 1'b0; nak_sched <= 1'b0; ack_seq <= 12'hFFF;
      xst <= X_IDLE; xi <= '0; x_ent <= '0; x_next <= '0; x_left <= '0; x_crc <= '1; x_dcrc <= '1;
      timer <= '0; tx_sym <= {1'b1, 8'h00};
      rst_ <= R_IDLE; rn <= '0; owp <= '0; orp <= '0; ocnt <= '0;
      r_valid <= 1'b0; r_data <= '0; r_last <= 1'b0;
      replays <= '0; naks_sent <= '0; dup_dropped <= '0;
      for (int k = 0; k < 4; k++) x_dllp[k] <= '0;
    end else begin
      logic [3:0] cnt_n, xl_n;
      cnt_n = rb_count; xl_n = x_left;
      // ---- accept TLP bytes into the replay buffer ----
      in_commit <= 1'b0;
      if (t_valid && t_ready) begin
        rb_data[{rb_tail, 5'(in_len)}] <= t_data;
        in_len <= in_len + 1;
        if (t_last) begin
          rb_len[rb_tail] <= in_len + 1; rb_seq[rb_tail] <= next_tx_seq;
          next_tx_seq <= next_tx_seq + 1; rb_tail <= rb_tail + 1; cnt_n = cnt_n + 1;
          in_len <= '0; in_commit <= 1'b1;
          xl_n = xl_n + 1;                            // one more to send
        end
      end

      // ---- transmit ----
      tx_sym <= {1'b1, 8'h00};                         // idle (k-symbol 0)
      if (rb_count != 0) timer <= timer + 1; else timer <= '0;
      case (xst)
        X_IDLE: begin
          if (ack_pend || nak_pend) begin
            logic [11:0] sq;
            sq = ack_seq;
            x_dllp[0] <= nak_pend ? 8'h10 : 8'h00; x_dllp[1] <= 8'h00;
            x_dllp[2] <= {4'h0, sq[11:8]}; x_dllp[3] <= sq[7:0];
            if (nak_pend) naks_sent <= naks_sent + 1;
            ack_pend <= 1'b0; nak_pend <= 1'b0;
            xst <= X_DLLP; xi <= '0; x_dcrc <= 16'hFFFF;
          end else if (timer >= 16'(REPLAY_TIMEOUT) && rb_count != 0) begin
            x_next <= rb_head; xl_n = cnt_n; timer <= '0; replays <= replays + 1;
          end else if (x_left != 0) begin
            x_ent <= x_next; xst <= X_TLP; xi <= '0; x_crc <= '1;
          end
        end
        X_TLP: begin
          logic [6:0] n;
          n = 7'(rb_len[x_ent]);
          if (xi == 0) tx_sym <= {1'b1, STP};
          else if (xi == 1) begin tx_sym <= {1'b0, 4'h0, rb_seq[x_ent][11:8]}; x_crc <= crc32_b(x_crc, {4'h0, rb_seq[x_ent][11:8]}); end
          else if (xi == 2) begin tx_sym <= {1'b0, rb_seq[x_ent][7:0]}; x_crc <= crc32_b(x_crc, rb_seq[x_ent][7:0]); end
          else if (xi < n + 3) begin
            logic [7:0] b;
            b = rb_data[{x_ent, 5'(32'(xi) - 3)}];
            tx_sym <= {1'b0, b}; x_crc <= crc32_b(x_crc, b);
          end else if (xi < n + 7) begin
            logic [31:0] f;
            f = ~x_crc;
            tx_sym <= {1'b0, f[(xi - n - 3) * 8 +: 8]};
          end else begin
            tx_sym <= {1'b1, ENDS};
            x_next <= x_ent + 1; if (xl_n != 0) xl_n = xl_n - 1; xst <= X_IDLE;
          end
          xi <= xi + 1;
        end
        X_DLLP: begin
          if (xi == 0) tx_sym <= {1'b1, SDP};
          else if (xi < 5) begin tx_sym <= {1'b0, x_dllp[xi - 1]}; x_dcrc <= crc16_b(x_dcrc, x_dllp[xi - 1]); end
          else if (xi == 5) tx_sym <= {1'b0, x_dcrc[15:8]};
          else if (xi == 6) tx_sym <= {1'b0, x_dcrc[7:0]};
          else begin tx_sym <= {1'b1, ENDS}; xst <= X_IDLE; end
          xi <= xi + 1;
        end
        default: xst <= X_IDLE;
      endcase

      // ---- receive ----
      r_valid <= 1'b0; r_last <= 1'b0;
      begin
        logic [8:0] oc;
        oc = ocnt;
        if (ocnt != 0) begin                          // drain delivered TLPs to the TL
          r_valid <= 1'b1; r_data <= ofifo[orp][7:0]; r_last <= ofifo[orp][8];
          orp <= orp + 1; oc = oc - 1;
        end
        ocnt <= oc;
      end
      case (rst_)
        R_IDLE: if (rx_sym[8]) begin
                  if (rx_sym[7:0] == STP) begin rst_ <= R_TLP; rn <= '0; end
                  else if (rx_sym[7:0] == SDP) begin rst_ <= R_DLLP; rn <= '0; end
                end
        R_TLP:  if (rx_sym[8]) begin
                  rst_ <= R_IDLE;
                  if (rx_sym[7:0] == ENDS && rn >= 7) begin
                    logic [31:0] c;
                    logic [11:0] sq;
                    int plen;
                    c = '1;
                    for (int k = 0; k < MAXB + 6; k++) if (k < 32'(rn) - 4) c = crc32_b(c, rbuf[k]);
                    sq = {rbuf[0][3:0], rbuf[1]};
                    plen = 32'(rn) - 6;
                    if ({rbuf[rn-1], rbuf[rn-2], rbuf[rn-3], rbuf[rn-4]} != ~c) begin
                      if (!nak_sched) begin nak_pend <= 1'b1; nak_sched <= 1'b1; ack_seq <= next_rcv_seq - 1; end
                    end else if (sq == next_rcv_seq && 32'(ocnt) + 32'(plen) <= 256) begin
                      for (int k = 0; k < MAXB; k++)
                        if (k < plen) ofifo[8'(owp + 8'(k))] <= {(k == plen - 1), rbuf[k + 2]};
                      owp <= owp + 8'(plen);
                      ocnt <= ocnt + 9'(plen) - ((ocnt != 0) ? 9'd1 : 9'd0);
                      next_rcv_seq <= next_rcv_seq + 1; ack_seq <= sq; ack_pend <= 1'b1; nak_sched <= 1'b0;
                    end else if (12'(sq - next_rcv_seq) >= 12'h800) begin   // already received
                      dup_dropped <= dup_dropped + 1; ack_pend <= 1'b1; ack_seq <= next_rcv_seq - 1;
                    end
                    // a future sequence (lost TLP before it) is dropped; the sender replays
                  end
                end else if (rn < 7'(MAXB + 6)) begin rbuf[6'(rn)] <= rx_sym[7:0]; rn <= rn + 1; end
        R_DLLP: if (rx_sym[8]) begin
                  rst_ <= R_IDLE;
                  if (rx_sym[7:0] == ENDS && rn == 6) begin
                    logic [15:0] c;
                    c = 16'hFFFF;
                    for (int k = 0; k < 4; k++) c = crc16_b(c, rbuf[k]);
                    if ({rbuf[4], rbuf[5]} == c) begin
                      logic [11:0] sq;
                      int npurge;
                      sq = {rbuf[2][3:0], rbuf[3]};
                      // purge every buffered TLP with seq <= sq (modulo 4096)
                      npurge = 0;
                      for (int k = 0; k < 8; k++)
                        if (k < rb_count && 12'(sq - rb_seq[3'(rb_head + 3'(k))]) < 12'h800) npurge = k + 1;
                      rb_head <= rb_head + 3'(npurge);
                      cnt_n = cnt_n - 4'(npurge);
                      if (xl_n > cnt_n) xl_n = cnt_n;         // purged entries need no sending
                      timer <= '0;
                      if (rbuf[0] == 8'h10 && xst == X_IDLE) begin   // NAK: replay what is left
                        x_next <= rb_head + 3'(npurge);
                        xl_n = cnt_n;
                        replays <= replays + 1;
                      end
                    end
                  end
                end else if (rn < 7'd8) begin rbuf[6'(rn)] <= rx_sym[7:0]; rn <= rn + 1; end
        default: rst_ <= R_IDLE;
      endcase
      rb_count <= cnt_n;
      x_left   <= xl_n;
    end
  end
endmodule
