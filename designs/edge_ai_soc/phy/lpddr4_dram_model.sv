// Behavioural LPDDR4 device model (verification only): bank state, BL16 data storage, RL read
// latency, DQ-calibration pattern for MPC reads, and timing-rule checking. Every violated rule
// increments `violations` and prints the rule.
module lpddr4_dram_model #(
  parameter int T_RCD = 8, parameter int T_RP = 8, parameter int T_RAS = 17, parameter int T_RFC = 112,
  parameter int T_REFI = 1560, parameter int RL = 12
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        d_cmd_valid,
  input  logic [3:0]  d_cmd,
  input  logic [2:0]  d_bank,
  input  logic [13:0] d_row,
  input  logic [9:0]  d_col,
  input  logic [15:0] d_mrw,
  input  logic        d_wr_valid,
  input  logic [63:0] d_wr_data,
  input  logic [7:0]  d_wr_dm,
  output logic        d_rd_valid,
  output logic [63:0] d_rd_data,
  output int          violations,
  output int          refreshes,
  output logic [7:0]  mr2
);
  localparam logic [63:0] PATTERN = 64'h55AA_33CC_0FF0_A55A;
  logic [63:0] mem [65536];                 // index {bank, row[3:0], col[4:0], beat}
  logic [7:0]  open_v;
  logic [13:0] open_row [8];
  longint      t_act [8], t_pre [8];
  longint      now, t_ref, t_last_ref;
  // read pipeline
  logic [RL+16:0] rq;                       // read issue shift register
  logic [15:0]    rd_base_q [RL+17];
  logic           rd_mpc_q  [RL+17];
  int             rd_beat;
  logic [15:0]    rd_base;
  logic           rd_mpc;
  // write burst
  int             wr_beat;
  logic [15:0]    wr_base;

  function automatic logic [15:0] idx(input logic [2:0] b, input logic [13:0] r, input logic [9:0] c);
    return {b, r[3:0], c[4:0], 4'd0};
  endfunction

  task automatic viol(input string rule);
    violations++;
    $display("LPDDR4 TIMING VIOLATION @%0d: %s", now, rule);
  endtask

  initial begin
    for (int k = 0; k < 65536; k++) mem[k] = '0;
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      open_v <= '0; now = 0; t_ref = -1000000; t_last_ref = 0; violations = 0; refreshes = 0;
      for (int b = 0; b < 8; b++) begin t_act[b] = -1000000; t_pre[b] = -1000000; end
      rq <= '0; wr_beat = -1; rd_beat = -1; d_rd_valid <= 1'b0; mr2 <= '0;
    end else begin
      now++;
      d_rd_valid <= 1'b0;
      if (d_cmd_valid) begin
        if (now - t_ref < T_RFC && d_cmd != 4'd0) viol("command during tRFC");
        case (d_cmd)
          4'd1: begin // ACT
                  if (open_v[d_bank]) viol("ACT to an open bank");
                  if (now - t_pre[d_bank] < T_RP) viol("tRP: ACT too soon after PRE");
                  open_v[d_bank] <= 1'b1; open_row[d_bank] <= d_row; t_act[d_bank] = now;
                end
          4'd2, 4'd3: begin // RD / WR
                  if (!open_v[d_bank]) viol("RD/WR to a closed bank");
                  if (now - t_act[d_bank] < T_RCD) viol("tRCD: RD/WR too soon after ACT");
                  if (d_cmd == 4'd3) begin wr_beat = 0; wr_base = idx(d_bank, open_row[d_bank], d_col); end
                  else begin rq[0] <= 1'b1; rd_base_q[0] <= idx(d_bank, open_row[d_bank], d_col); rd_mpc_q[0] <= 1'b0; end
                end
          4'd4: begin // PRE
                  if (open_v[d_bank] && now - t_act[d_bank] < T_RAS) viol("tRAS: PRE too soon after ACT");
                  open_v[d_bank] <= 1'b0; t_pre[d_bank] = now;
                end
          4'd5: begin // PREA
                  for (int b = 0; b < 8; b++) begin
                    if (open_v[b] && now - t_act[b] < T_RAS) viol("tRAS: PREA too soon after ACT");
                    t_pre[b] = now;
                  end
                  open_v <= '0;
                end
          4'd6: begin // REF (all bank)
                  if (|open_v) viol("REF with open banks");
                  for (int b = 0; b < 8; b++) if (now - t_pre[b] < T_RP) viol("tRP: REF too soon after PRE");
                  if (refreshes > 0 && now - t_last_ref > (T_REFI * 9) / 8 + T_RFC) viol("refresh interval exceeded");
                  t_ref = now; t_last_ref = now; refreshes++;
                end
          4'd7: if (d_mrw[15:8] == 8'd2) mr2 <= d_mrw[7:0];
          4'd8: begin rq[0] <= 1'b1; rd_mpc_q[0] <= 1'b1; rd_base_q[0] <= '0; end   // MPC read DQ calibration
          default: ;
        endcase
      end
      if (!(d_cmd_valid && (d_cmd == 4'd2 || d_cmd == 4'd8))) rq[0] <= 1'b0;
      // read latency pipeline
      for (int k = 1; k <= RL; k++) begin rq[k] <= rq[k-1]; rd_base_q[k] <= rd_base_q[k-1]; rd_mpc_q[k] <= rd_mpc_q[k-1]; end
      if (rq[RL]) begin rd_beat = 0; rd_base = rd_base_q[RL]; rd_mpc = rd_mpc_q[RL]; end
      if (rd_beat >= 0) begin
        d_rd_valid <= 1'b1;
        d_rd_data  <= rd_mpc ? PATTERN : mem[rd_base + 16'(rd_beat)];
        rd_beat = (rd_beat == 15) ? -1 : rd_beat + 1;
      end
      // write burst capture
      if (wr_beat >= 0 && d_wr_valid) begin
        for (int l = 0; l < 8; l++)
          if (!d_wr_dm[l]) mem[wr_base + 16'(wr_beat)][l*8 +: 8] = d_wr_data[l*8 +: 8];
        wr_beat = (wr_beat == 15) ? -1 : wr_beat + 1;
      end
    end
  end
endmodule
