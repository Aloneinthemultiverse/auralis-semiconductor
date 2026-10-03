// LPDDR4 memory controller (digital). Front end = the soc_top ddr_* port (64-bit words).
// Back end = DFI-style command/data interface to lpddr4_phy.
//  - 8 banks, open-page policy: row hit -> RD/WR; miss -> PRE (if open) -> ACT -> RD/WR
//  - per-bank tRCD / tRP / tRAS / tWR counters, global tRFC, all-bank refresh every tREFI
//    (all banks precharged first), refresh postponement not used
//  - BL16 bursts on a 64-bit data path (4 x16 channels operated in lock-step = 25.6 GB/s at 3200 MT/s);
//    a 64-bit SoC access uses one beat of the burst (data mask on the other beats for writes)
//  - init: wait tINIT, mode-register writes (RL/WL/BL), then requests PHY read training and waits
// Timing parameters are in controller clocks (defaults: LPDDR4-3200, 400 MHz controller clock =
// DFI 1:4 ratio; tRCD = tRP = 18 ns, tRAS = 42 ns, tWR = 18 ns, tRFCab = 280 ns, tREFI = 3.9 us).
// Address map (byte address in the 0x8000_0000 window): [2:0] byte, [6:3] beat, [16:7] column
// group, [19:17] bank, [33:20] row.
module lpddr4_ctrl #(
  parameter int T_RCD = 8, parameter int T_RP = 8, parameter int T_RAS = 17, parameter int T_WR = 8,
  parameter int T_RFC = 112, parameter int T_REFI = 1560, parameter int T_INIT = 64,
  parameter int RL = 12, parameter int WL = 6
) (
  input  logic        clk,
  input  logic        rst_n,
  // SoC side
  input  logic        req,
  input  logic        we,
  input  logic [31:0] addr,
  input  logic [63:0] wdata,
  output logic        gnt,
  output logic        rvalid,
  output logic [63:0] rdata,
  // DFI-style PHY side
  output logic        dfi_cmd_valid,
  output logic [2:0]  dfi_cmd,        // 0 NOP 1 ACT 2 RD 3 WR 4 PRE 5 PREA 6 REF 7 MRW
  output logic [2:0]  dfi_bank,
  output logic [13:0] dfi_row,
  output logic [9:0]  dfi_col,
  output logic [15:0] dfi_mrw,        // {MR address, value}
  output logic [63:0] dfi_wrdata,     // beat data (one beat used; others masked)
  output logic [3:0]  dfi_wrbeat,
  output logic        dfi_train_req,
  input  logic        dfi_train_done,
  input  logic        dfi_rddata_valid,
  input  logic [63:0] dfi_rddata,
  output logic        init_done,
  output logic [31:0] stat_hits,
  output logic [31:0] stat_misses,
  output logic [31:0] stat_refreshes
);
  localparam logic [2:0] C_NOP = 3'd0, C_ACT = 3'd1, C_RD = 3'd2, C_WR = 3'd3, C_PRE = 3'd4,
                         C_PREA = 3'd5, C_REF = 3'd6, C_MRW = 3'd7;
  localparam logic [3:0] S_INIT = 4'd0, S_MRW = 4'd1, S_TRAIN = 4'd2, S_IDLE = 4'd3, S_PRE = 4'd4,
                         S_ACT = 4'd5, S_RW = 4'd6, S_WAITRD = 4'd7, S_REF_PRE = 4'd8, S_REF = 4'd9,
                         S_WAITWR = 4'd10;
  logic [3:0]  st;
  logic [15:0] cnt;
  logic [1:0]  mrw_i;
  logic [7:0]  open_v;
  logic [13:0] open_row [8];
  logic [15:0] t_act_ok [8];   // cycles until the bank may take RD/WR (tRCD)
  logic [15:0] t_pre_ok [8];   // cycles until the bank may be precharged (tRAS / tWR)
  logic [15:0] t_rp;           // cycles until ACT allowed after PRE
  logic [31:0] refi;
  logic        ref_due;
  // latched request
  logic        q_we;
  logic [31:0] q_addr;
  logic [63:0] q_wdata;
  wire  [2:0]  q_bank = q_addr[19:17];
  wire  [13:0] q_row  = {2'b00, q_addr[31:20]};
  wire  [9:0]  q_col  = q_addr[16:7];
  wire  [3:0]  q_beat = q_addr[6:3];
  logic [3:0]  rd_beat;

  assign gnt = (st == S_IDLE) && req && !ref_due && cnt == 0;   // blocked during tRFC

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      st <= S_INIT; cnt <= '0; mrw_i <= '0; open_v <= '0; t_rp <= '0; refi <= '0; ref_due <= 1'b0;
      for (int b = 0; b < 8; b++) begin open_row[b] <= '0; t_act_ok[b] <= '0; t_pre_ok[b] <= '0; end
      q_we <= 1'b0; q_addr <= '0; q_wdata <= '0; rd_beat <= '0;
      dfi_cmd_valid <= 1'b0; dfi_cmd <= C_NOP; dfi_bank <= '0; dfi_row <= '0; dfi_col <= '0; dfi_mrw <= '0;
      dfi_wrdata <= '0; dfi_wrbeat <= '0; dfi_train_req <= 1'b0; init_done <= 1'b0;
      rvalid <= 1'b0; rdata <= '0; stat_hits <= '0; stat_misses <= '0; stat_refreshes <= '0;
    end else begin
      dfi_cmd_valid <= 1'b0;
      dfi_cmd <= C_NOP;
      rvalid <= 1'b0;
      for (int b = 0; b < 8; b++) begin
        if (t_act_ok[b] != 0) t_act_ok[b] <= t_act_ok[b] - 1;
        if (t_pre_ok[b] != 0) t_pre_ok[b] <= t_pre_ok[b] - 1;
      end
      if (t_rp != 0) t_rp <= t_rp - 1;
      if (cnt != 0) cnt <= cnt - 1;
      if (init_done) begin
        if (refi + 1 >= T_REFI) begin refi <= '0; ref_due <= 1'b1; end else refi <= refi + 1;
      end
      case (st)
        S_INIT:  if (cnt == 0) begin
                   if (T_INIT != 0 && mrw_i == 0 && !dfi_train_req) begin cnt <= 16'(T_INIT); mrw_i <= 2'd0; st <= S_MRW; end
                 end
        S_MRW:   if (cnt == 0) begin                      // MR1 (BL16), MR2 (RL/WL), MR3
                   dfi_cmd_valid <= 1'b1; dfi_cmd <= C_MRW;
                   case (mrw_i)
                     2'd0: dfi_mrw <= {8'd1, 8'h04};
                     2'd1: dfi_mrw <= {8'd2, 8'(RL)};
                     default: dfi_mrw <= {8'd3, 8'h31};
                   endcase
                   cnt <= 16'd10;
                   if (mrw_i == 2'd2) begin st <= S_TRAIN; dfi_train_req <= 1'b1; end
                   mrw_i <= mrw_i + 1;
                 end
        S_TRAIN: if (dfi_train_done) begin dfi_train_req <= 1'b0; init_done <= 1'b1; st <= S_IDLE; end
        S_IDLE:  if (ref_due) begin
                   st <= S_REF_PRE;
                 end else if (req && cnt == 0) begin
                   q_we <= we; q_addr <= addr; q_wdata <= wdata;
                   if (open_v[addr[19:17]] && open_row[addr[19:17]] == {2'b00, addr[31:20]}) begin
                     st <= S_RW; stat_hits <= stat_hits + 1;
                   end else begin
                     st <= open_v[addr[19:17]] ? S_PRE : S_ACT; stat_misses <= stat_misses + 1;
                   end
                 end
        S_PRE:   if (t_pre_ok[q_bank] == 0) begin
                   dfi_cmd_valid <= 1'b1; dfi_cmd <= C_PRE; dfi_bank <= q_bank;
                   open_v[q_bank] <= 1'b0; t_rp <= 16'(T_RP); st <= S_ACT;
                 end
        S_ACT:   if (t_rp == 0) begin
                   dfi_cmd_valid <= 1'b1; dfi_cmd <= C_ACT; dfi_bank <= q_bank; dfi_row <= q_row;
                   open_v[q_bank] <= 1'b1; open_row[q_bank] <= q_row;
                   t_act_ok[q_bank] <= 16'(T_RCD); t_pre_ok[q_bank] <= 16'(T_RAS); st <= S_RW;
                 end
        S_RW:    if (t_act_ok[q_bank] == 0) begin
                   dfi_cmd_valid <= 1'b1; dfi_bank <= q_bank; dfi_col <= q_col;
                   if (q_we) begin
                     dfi_cmd <= C_WR; dfi_wrdata <= q_wdata; dfi_wrbeat <= q_beat;
                     // the BL16 burst occupies the data bus for 16 beats (tCCD); tWR counts from its end
                     if (t_pre_ok[q_bank] < 16'(WL + 16 + T_WR)) t_pre_ok[q_bank] <= 16'(WL + 16 + T_WR);
                     cnt <= 16'(WL + 16); st <= S_WAITWR;
                   end else begin
                     dfi_cmd <= C_RD; rd_beat <= '0; st <= S_WAITRD;
                   end
                 end
        S_WAITWR: if (cnt == 0) begin rvalid <= 1'b1; st <= S_IDLE; end        // write acknowledged
        S_WAITRD: if (dfi_rddata_valid) begin
                    if (rd_beat == q_beat) begin rvalid <= 1'b1; rdata <= dfi_rddata; end
                    if (rd_beat == 4'd15) st <= S_IDLE;
                    rd_beat <= rd_beat + 1;
                  end
        S_REF_PRE: if (t_rp == 0) begin
                     logic busy_b;
                     busy_b = 1'b0;
                     for (int b = 0; b < 8; b++) if (open_v[b] && t_pre_ok[b] != 0) busy_b = 1'b1;
                     if (!busy_b) begin
                       if (|open_v) begin
                         dfi_cmd_valid <= 1'b1; dfi_cmd <= C_PREA; open_v <= '0; t_rp <= 16'(T_RP);
                       end
                       st <= S_REF;
                     end
                   end
        S_REF:   if (t_rp == 0 && cnt == 0) begin
                   dfi_cmd_valid <= 1'b1; dfi_cmd <= C_REF; cnt <= 16'(T_RFC);
                   ref_due <= 1'b0; stat_refreshes <= stat_refreshes + 1; st <= S_IDLE;
                 end
        default: st <= S_IDLE;
      endcase
    end
  end
endmodule
