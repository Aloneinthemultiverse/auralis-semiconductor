// SerDes PCS layers (digital, synthesizable) for USB 3.0 / 1000BASE-X (8b/10b) and
// 10GBASE-R Ethernet (64b/66b) / PCIe Gen3 (128b/130b). The analog SerDes (driver, CTLE, CDR, PLL)
// is the PMA below these blocks; serdes_model.sv provides its behavioural stand-in.

// ---------------- 8b/10b: comma alignment ----------------
// Raw 10-bit words from the deserializer arrive with an unknown bit offset. The aligner scans a
// 20-bit window for the comma (0011111 / 1100000), locks that offset and re-aligns the stream.
module comma_align (
  input  logic       clk,
  input  logic       rst_n,
  input  logic [9:0] raw,          // bit 9 = earliest bit
  output logic [9:0] word,
  output logic       locked
);
  logic [19:0] win;
  logic [3:0]  off;
  logic [3:0]  hit;
  logic        found;
  always_comb begin
    found = 1'b0; hit = '0;
    for (int o = 0; o < 10; o++) begin
      logic [6:0] w7;
      w7 = win[19 - o -: 7];
      if (!found && (w7 == 7'b0011111 || w7 == 7'b1100000)) begin found = 1'b1; hit = 4'(o); end
    end
  end
  always_ff @(posedge clk) begin
    if (!rst_n) begin win <= '0; off <= '0; locked <= 1'b0; end
    else begin
      win <= {win[9:0], raw};
      if (found && (!locked || hit == off)) begin off <= hit; locked <= 1'b1; end
    end
  end
  assign word = win[19 - off -: 10];
endmodule

// ---------------- 8b/10b link layer with training (USB3 / PCIe Gen1-2 style LTSSM subset) ----------------
// Ordered sets (4 symbols): TS1 = K28.5 D10.2 D10.2 D10.2, TS2 = K28.5 D5.2 D5.2 D5.2,
// SKP = K28.5 K28.0 K28.0 K28.0. States: POLLING (send TS1 until 8 TS1/TS2 received) ->
// CONFIG (send TS2 until 8 TS2 received and >= 16 sent) -> L0 (data; a SKP set every SKP_INT symbols,
// removed on receive). Received symbol errors in L0 are counted.
module link8b10b #(parameter int SKP_INT = 64) (
  input  logic       clk,
  input  logic       rst_n,
  // user data (L0)
  input  logic       tx_valid,
  input  logic [7:0] tx_data,
  output logic       tx_ready,
  output logic       rx_valid,
  output logic [7:0] rx_data,
  // to/from PMA (10-bit words)
  output logic [9:0] tx_code,
  input  logic [9:0] rx_raw,
  output logic [1:0] state,          // 0 POLLING 1 CONFIG 2 L0
  output logic [15:0] err_count
);
  localparam logic [7:0] K28_5 = 8'hBC, K28_0 = 8'h1C, D10_2 = 8'h4A, D5_2 = 8'h45;
  localparam logic [1:0] POLL = 2'd0, CONF = 2'd1, L0 = 2'd2;
  // ---- transmit ----
  logic [1:0]  sym;           // position inside an ordered set
  logic [7:0]  sent_ts2, os_cnt;
  logic [15:0] since_skp;
  logic        in_skp;
  logic        tk, trd, trd_n, k_err;
  logic [7:0]  td;
  always_comb begin
    tx_ready = 1'b0; tk = 1'b0; td = 8'h00;
    if (state != L0 || in_skp) begin
      tk = (sym == 0) || (in_skp && state == L0);
      td = (sym == 0) ? K28_5 : (state == L0) ? K28_0 : (state == POLL) ? D10_2 : D5_2;
    end else begin
      tx_ready = 1'b1;
      tk = 1'b0; td = tx_valid ? tx_data : 8'h00;      // idle data = D0.0 (scrambled in real links)
    end
  end
  enc8b10b u_enc (.k(tk), .d(td), .rd(trd), .code(tx_code), .rd_out(trd_n), .k_err(k_err));

  // ---- receive ----
  logic [9:0] rword;
  logic       aligned, rk, rrd, rrd_n, cerr, derr;
  logic [7:0] rd8;
  logic [1:0] rsym;
  logic [7:0] ts1_seen, ts2_seen;
  logic       os_is_ts1, os_is_ts2, os_ok;
  comma_align u_al (.clk(clk), .rst_n(rst_n), .raw(rx_raw), .word(rword), .locked(aligned));
  dec8b10b u_dec (.code(rword), .rd(rrd), .d(rd8), .k(rk), .rd_out(rrd_n), .code_err(cerr), .disp_err(derr));

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state <= POLL; sym <= '0; sent_ts2 <= '0; since_skp <= '0; in_skp <= 1'b0; trd <= 1'b0; os_cnt <= '0;
      rrd <= 1'b0; rsym <= '0; ts1_seen <= '0; ts2_seen <= '0; os_is_ts1 <= 1'b0; os_is_ts2 <= 1'b0;
      os_ok <= 1'b0; rx_valid <= 1'b0; rx_data <= '0; err_count <= '0;
    end else begin
      trd <= trd_n;
      // transmit framing
      if (state != L0) begin
        sym <= sym + 1;
        if (sym == 2'd3 && state == CONF && sent_ts2 != 8'hFF) sent_ts2 <= sent_ts2 + 1;
      end else if (in_skp) begin
        sym <= sym + 1;
        if (sym == 2'd3) begin in_skp <= 1'b0; since_skp <= '0; end
      end else begin
        since_skp <= since_skp + 1;
        if (since_skp + 1 >= 16'(SKP_INT)) begin in_skp <= 1'b1; sym <= '0; end
      end
      // receive
      rx_valid <= 1'b0;
      if (aligned) begin
        rrd <= rrd_n;
        if (rk && rd8 == K28_5) begin                    // start of an ordered set
          rsym <= 2'd1; os_is_ts1 <= 1'b1; os_is_ts2 <= 1'b1; os_ok <= 1'b1;
        end else if (rsym != 0) begin
          rsym <= rsym + 1;
          if (rk && rd8 == K28_0) begin os_is_ts1 <= 1'b0; os_is_ts2 <= 1'b0; end   // SKP
          else begin
            if (rk || rd8 != D10_2) os_is_ts1 <= 1'b0;
            if (rk || rd8 != D5_2)  os_is_ts2 <= 1'b0;
          end
          if (rsym == 2'd3) begin
            logic t1, t2;
            t1 = os_is_ts1 && !rk && rd8 == D10_2;
            t2 = os_is_ts2 && !rk && rd8 == D5_2;
            ts1_seen <= t1 ? ((ts1_seen == 8'hFF) ? ts1_seen : ts1_seen + 1) : (t2 ? ts1_seen : '0);
            ts2_seen <= t2 ? ((ts2_seen == 8'hFF) ? ts2_seen : ts2_seen + 1) : (t1 ? '0 : ts2_seen);
            rsym <= '0;
          end
        end else if (state == L0) begin
          if (cerr || derr) err_count <= err_count + 1;
          else if (!rk) begin rx_valid <= 1'b1; rx_data <= rd8; end
        end
      end
      // LTSSM
      case (state)
        POLL: if (ts1_seen + ts2_seen >= 8 && sym == 2'd3) state <= CONF;
        CONF: if (ts2_seen >= 8 && sent_ts2 >= 16 && sym == 2'd3) begin state <= L0; since_skp <= '0; end
        default: ;
      endcase
    end
  end
endmodule

// ---------------- block-code PCS: 64b/66b (10GBASE-R) and 128b/130b (PCIe Gen3) ----------------
// TX: 2-bit sync header (01 = data, 10 = control) + scrambled payload, serialised MSB first.
// RX: block lock per IEEE 802.3 cl.49 (lock after 64 consecutive valid headers, slip on an invalid
// header while unlocked, drop lock after 16 invalid headers within 64 blocks), then descramble.
// SCR = 0: self-synchronous x^58 + x^39 + 1 (Ethernet). SCR = 1: additive LFSR
// x^23 + x^21 + x^16 + x^8 + x^5 + x^2 + 1 seeded per lane (PCIe Gen3); control (ordered-set) blocks
// are sent unscrambled and reseed the LFSR on both sides, as EIEOS does.
module blk_pcs_tx #(parameter int N = 64, parameter int SCR = 0) (
  input  logic         clk,
  input  logic         rst_n,
  input  logic         valid,
  input  logic         ctrl,
  input  logic [N-1:0] data,
  output logic [N+1:0] block       // {header, payload}, bit N+1 first on the wire
);
  logic [57:0] s;   // self-sync state
  logic [22:0] l;   // additive LFSR
  logic [N-1:0] scr;
  always_comb begin
    logic [57:0] st;
    logic [22:0] lf;
    st = s; lf = l;
    for (int i = N - 1; i >= 0; i--) begin
      logic b;
      if (SCR == 0) begin
        b = data[i] ^ st[38] ^ st[57];
        st = {st[56:0], b};
      end else begin
        b = data[i] ^ lf[22];
        lf = {lf[21:0], lf[22] ^ lf[20] ^ lf[15] ^ lf[7] ^ lf[4] ^ lf[1]};
      end
      scr[i] = b;
    end
  end
  always_ff @(posedge clk) begin
    if (!rst_n) begin s <= '1; l <= 23'h1DBFBC; block <= '0; end
    else if (valid) begin
      logic [57:0] st;
      logic [22:0] lf;
      st = s; lf = l;
      for (int i = N - 1; i >= 0; i--) begin
        if (SCR == 0) st = {st[56:0], data[i] ^ st[38] ^ st[57]};
        else lf = {lf[21:0], lf[22] ^ lf[20] ^ lf[15] ^ lf[7] ^ lf[4] ^ lf[1]};
      end
      s <= st; l <= lf;
      block <= {ctrl ? 2'b10 : 2'b01, scr};
      if (SCR == 1 && ctrl) begin block <= {2'b10, data}; l <= 23'h1DBFBC; end   // ordered set: unscrambled, reseed
    end
  end
endmodule

module blk_pcs_rx #(parameter int N = 64, parameter int SCR = 0) (
  input  logic         clk,
  input  logic         rst_n,
  input  logic [N+1:0] raw,        // N+2 raw bits per cycle from the deserializer, unknown offset
  output logic         locked,
  output logic         valid,
  output logic         ctrl,
  output logic [N-1:0] data,
  output logic [15:0]  slips
);
  localparam int W = N + 2;
  logic [2*W-1:0] win;
  logic [$clog2(W)-1:0] off;
  logic [6:0]  good_cnt, blk_cnt;
  logic [4:0]  bad_cnt;
  logic [W-1:0] blk;
  logic        hdr_ok;
  logic [57:0] s;
  logic [22:0] l;
  logic [N-1:0] dsc;
  assign blk    = win[2*W-1 - 32'(off) -: W];
  assign hdr_ok = blk[W-1] ^ blk[W-2];
  always_comb begin
    logic [57:0] st;
    logic [22:0] lf;
    st = s; lf = l;
    for (int i = N - 1; i >= 0; i--) begin
      if (SCR == 0) begin
        dsc[i] = blk[i] ^ st[38] ^ st[57];
        st = {st[56:0], blk[i]};
      end else begin
        dsc[i] = blk[i] ^ lf[22];
        lf = {lf[21:0], lf[22] ^ lf[20] ^ lf[15] ^ lf[7] ^ lf[4] ^ lf[1]};
      end
    end
  end
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      win <= '0; off <= '0; good_cnt <= '0; blk_cnt <= '0; bad_cnt <= '0; locked <= 1'b0;
      valid <= 1'b0; ctrl <= 1'b0; data <= '0; s <= '1; l <= 23'h1DBFBC; slips <= '0;
    end else begin
      win <= {win[W-1:0], raw};
      valid <= 1'b0;
      // descrambler state advances on every block once locked
      if (locked) begin
        logic [57:0] st;
        logic [22:0] lf;
        st = s; lf = l;
        for (int i = N - 1; i >= 0; i--) begin
          if (SCR == 0) st = {st[56:0], blk[i]};
          else lf = {lf[21:0], lf[22] ^ lf[20] ^ lf[15] ^ lf[7] ^ lf[4] ^ lf[1]};
        end
        s <= st; l <= lf;
        valid <= 1'b1; ctrl <= (blk[W-1:W-2] == 2'b10); data <= dsc;
        if (SCR == 1 && blk[W-1:W-2] == 2'b10) begin data <= blk[N-1:0]; l <= 23'h1DBFBC; end
      end
      if (!locked) begin
        if (hdr_ok) begin
          good_cnt <= good_cnt + 1;
          if (good_cnt == 7'd63) begin
            locked <= 1'b1; blk_cnt <= '0; bad_cnt <= '0;
            if (SCR == 1) l <= 23'h1DBFBC;                 // additive scrambler restarts at lock
          end
        end else begin
          good_cnt <= '0; slips <= slips + 1;
          off <= (32'(off) == W - 1) ? '0 : off + 1;
        end
      end else begin
        blk_cnt <= blk_cnt + 1;
        if (!hdr_ok) bad_cnt <= bad_cnt + 1;
        if (!hdr_ok && bad_cnt == 5'd15) begin locked <= 1'b0; good_cnt <= '0; end
        if (blk_cnt == 7'd63) begin blk_cnt <= '0; bad_cnt <= '0; end
      end
    end
  end
endmodule
