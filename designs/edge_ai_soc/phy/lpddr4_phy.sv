// LPDDR4 PHY: digital part + behavioural model of the analog receiver.
// Digital (synthesizable): DFI command/write pipeline to the DRAM pins, write-data beat placement
// with data mask, read capture through a per-byte-lane programmable delay line (64 taps), and the
// read-DQ training engine: it owns the bus during training, issues DQ-calibration reads of the
// known pattern, sweeps each lane's tap 0..63, finds the widest passing window and centres the tap.
// Behavioural (`ifdef / clearly separated): the per-lane eye seen by the sampler. A sample taken with
// the lane tap outside [eye_lo, eye_lo + EYE_W) returns corrupted data, as a mis-timed DQS strobe would.
module lpddr4_phy #(parameter int EYE_W = 18) (
  input  logic        clk,
  input  logic        rst_n,
  // DFI from controller
  input  logic        dfi_cmd_valid,
  input  logic [2:0]  dfi_cmd,
  input  logic [2:0]  dfi_bank,
  input  logic [13:0] dfi_row,
  input  logic [9:0]  dfi_col,
  input  logic [15:0] dfi_mrw,
  input  logic [63:0] dfi_wrdata,
  input  logic [3:0]  dfi_wrbeat,
  input  logic        dfi_train_req,
  output logic        dfi_train_done,
  output logic        dfi_rddata_valid,
  output logic [63:0] dfi_rddata,
  // DRAM pins (modelled at command/beat level)
  output logic        d_cmd_valid,
  output logic [3:0]  d_cmd,          // controller codes + 8 = MPC read DQ calibration
  output logic [2:0]  d_bank,
  output logic [13:0] d_row,
  output logic [9:0]  d_col,
  output logic [15:0] d_mrw,
  output logic        d_wr_valid,
  output logic [63:0] d_wr_data,
  output logic [7:0]  d_wr_dm,        // 1 = byte masked
  input  logic        d_rd_valid,
  input  logic [63:0] d_rd_data,
  // behavioural channel: where each lane's eye opens (tap units)
  input  logic [47:0] eye_lo,         // 8 lanes x 6 bits
  // status
  output logic [47:0] taps,
  output logic [7:0]  lane_ok
);
  localparam logic [63:0] PATTERN = 64'h55AA_33CC_0FF0_A55A;   // MR32/MR40-style calibration pattern

  // ---------------- write path: WL is handled by the controller; beats leave here ----------------
  logic        wr_act;
  logic [3:0]  wr_cnt, wr_beat;
  logic [63:0] wr_data_q;
  // ---------------- training ----------------
  localparam logic [2:0] T_IDLE = 3'd0, T_ISSUE = 3'd1, T_WAIT = 3'd2, T_NEXT = 3'd3, T_DONE = 3'd4;
  logic [2:0]  tst;
  logic [5:0]  sweep;
  logic [3:0]  beat_cnt;
  logic [7:0]  beat_ok;
  logic [63:0] pass_map [8];
  // ---------------- receiver ----------------
  logic [63:0] sampled;

  // behavioural sampler: lane l is correct only when taps[l] lies inside its eye
  always_comb begin
    for (int l = 0; l < 8; l++) begin
      logic [5:0] lo, t;
      lo = eye_lo[l*6 +: 6];
      t  = taps[l*6 +: 6];
      sampled[l*8 +: 8] = (t >= lo && 32'(t) < 32'(lo) + EYE_W) ? d_rd_data[l*8 +: 8] : ~d_rd_data[l*8 +: 8] ^ 8'h5A;
    end
  end

  // centre of the widest run of passing taps
  function automatic logic [5:0] centre(input logic [63:0] m);
    int best_s, best_l, s, l;
    logic [31:0] c;
    best_s = 0; best_l = 0; s = 0; l = 0;
    for (int t = 0; t < 64; t++) begin
      if (m[t]) begin
        if (l == 0) s = t;
        l++;
        if (l > best_l) begin best_l = l; best_s = s; end
      end else l = 0;
    end
    c = best_s + best_l / 2;
    centre = c[5:0];
  endfunction

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      wr_act <= 1'b0; wr_cnt <= '0; wr_beat <= '0; wr_data_q <= '0;
      tst <= T_IDLE; sweep <= '0; beat_cnt <= '0; beat_ok <= '1; taps <= '0; lane_ok <= '0;
      dfi_train_done <= 1'b0;
      for (int l = 0; l < 8; l++) pass_map[l] <= '0;
    end else begin
      // write burst: 16 beats, only the addressed beat is unmasked
      if (dfi_cmd_valid && dfi_cmd == 3'd3) begin
        wr_act <= 1'b1; wr_cnt <= '0; wr_beat <= dfi_wrbeat; wr_data_q <= dfi_wrdata;
      end else if (wr_act) begin
        wr_cnt <= wr_cnt + 1;
        if (wr_cnt == 4'd15) wr_act <= 1'b0;
      end
      // read-DQ training
      case (tst)
        T_IDLE:  if (dfi_train_req && !dfi_train_done) begin tst <= T_ISSUE; sweep <= '0; end
        T_ISSUE: begin
                   for (int l = 0; l < 8; l++) taps[l*6 +: 6] <= sweep;
                   beat_cnt <= '0; beat_ok <= '1; tst <= T_WAIT;
                 end
        T_WAIT:  if (d_rd_valid) begin
                   for (int l = 0; l < 8; l++)
                     if (sampled[l*8 +: 8] != PATTERN[l*8 +: 8]) beat_ok[l] <= 1'b0;
                   beat_cnt <= beat_cnt + 1;
                   if (beat_cnt == 4'd15) tst <= T_NEXT;
                 end
        T_NEXT:  begin
                   for (int l = 0; l < 8; l++) pass_map[l][sweep] <= beat_ok[l];
                   if (sweep == 6'd63) tst <= T_DONE;
                   else begin sweep <= sweep + 1; tst <= T_ISSUE; end
                 end
        T_DONE:  begin
                   for (int l = 0; l < 8; l++) begin
                     taps[l*6 +: 6] <= centre(pass_map[l]);
                     lane_ok[l] <= |pass_map[l];
                   end
                   dfi_train_done <= 1'b1; tst <= T_IDLE;
                 end
        default: tst <= T_IDLE;
      endcase
    end
  end

  // pins: during training the PHY issues MPC DQ-calibration reads; otherwise the controller's commands
  always_comb begin
    if (tst == T_ISSUE) begin
      d_cmd_valid = 1'b1; d_cmd = 4'd8;
    end else begin
      d_cmd_valid = dfi_cmd_valid; d_cmd = {1'b0, dfi_cmd};
    end
    d_bank = dfi_bank; d_row = dfi_row; d_col = dfi_col; d_mrw = dfi_mrw;
    d_wr_valid = wr_act;
    d_wr_data  = wr_data_q;
    d_wr_dm    = (wr_act && wr_cnt == wr_beat) ? 8'h00 : 8'hFF;
  end

  assign dfi_rddata_valid = d_rd_valid && dfi_train_done;
  assign dfi_rddata       = sampled;
endmodule
