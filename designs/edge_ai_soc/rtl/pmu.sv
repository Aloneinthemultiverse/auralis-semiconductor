// Power management unit for the < 3 W budget. D power domains (e.g. NPU, CPU0..3, DMA, PERIPH).
// Per domain, power-down: clock off -> isolation on -> retention save -> switch off (wait ack low).
// Power-up: switch on (wait ack high) -> retention restore -> isolation off -> clock on -> reset release.
// A missing switch acknowledge times out -> domain error (to err_agg), domain left isolated.
// Auto-idle: a domain whose idle input stays high for IDLE_TH cycles is powered down (if enabled).
// Thermal: temp >= TEMP_TH raises throttle (interrupt) and gates the NPU clock enable 1 cycle in 2.
// Registers: 0x00 REQ (bit d: 1 = domain on), 0x04 AUTO (bit d: auto-idle enable),
//            0x08 STATE (R: bit d on), 0x0C ERR (R/W1C), 0x10 IDLE_TH, 0x14 TEMP_TH, 0x18 TIMEOUT.
module pmu #(parameter int D = 4, parameter int NPU_DOM = 0) (
  input  logic         clk,
  input  logic         rst_n,
  input  logic         r_req,
  input  logic         r_we,
  input  logic [7:0]   r_addr,
  input  logic [31:0]  r_wdata,
  output logic [31:0]  r_rdata,
  input  logic [D-1:0] idle,
  input  logic [D-1:0] pwr_ack,
  input  logic [11:0]  temp,        // junction temperature sensor code
  output logic [D-1:0] clk_en,
  output logic [D-1:0] iso_en,
  output logic [D-1:0] ret_save,    // retention: 1 = state held in retention flops
  output logic [D-1:0] pwr_en,
  output logic [D-1:0] dom_rst_n,
  output logic [D-1:0] dom_err,
  output logic         throttle
);
  localparam logic [3:0] ON = 4'd0, CLKOFF = 4'd1, ISO = 4'd2, SAVE = 4'd3, SWOFF = 4'd4, OFF = 4'd5,
                         SWON = 4'd6, RESTORE = 4'd7, ISOOFF = 4'd8, CLKON = 4'd9, ERR = 4'd10;
  logic [D-1:0]  req, auto_en, err;
  logic [31:0]   idle_th, timeout;
  logic [11:0]  temp_th;
  logic [D*4-1:0]  st;
  logic [D*32-1:0] icnt, tcnt;
  logic          tog;

  always_comb begin
    r_rdata = '0;
    case (r_addr)
      8'h00: r_rdata = 32'(req);
      8'h04: r_rdata = 32'(auto_en);
      8'h08: for (int d = 0; d < D; d++) r_rdata[d] = (st[d*4 +: 4] == ON);
      8'h0C: r_rdata = 32'(err);
      8'h10: r_rdata = idle_th;
      8'h14: r_rdata = {20'd0, temp_th};
      8'h18: r_rdata = timeout;
      default: ;
    endcase
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      req <= '1; auto_en <= '0; err <= '0; idle_th <= 32'd1000; temp_th <= 12'd3000; timeout <= 32'd256;
      st <= '0; icnt <= '0; tcnt <= '0; throttle <= 1'b0; tog <= 1'b0;
    end else begin
      tog <= ~tog;
      throttle <= (temp >= temp_th);
      if (r_req && r_we)
        case (r_addr)
          8'h00: req <= r_wdata[D-1:0];
          8'h04: auto_en <= r_wdata[D-1:0];
          8'h0C: err <= err & ~r_wdata[D-1:0];
          8'h10: idle_th <= r_wdata;
          8'h14: temp_th <= r_wdata[11:0];
          8'h18: timeout <= r_wdata;
          default: ;
        endcase
      for (int d = 0; d < D; d++) begin
        // auto-idle: count idle cycles while on
        if (st[d*4 +: 4] == ON && idle[d] && auto_en[d]) begin
          icnt[d*32 +: 32] <= icnt[d*32 +: 32] + 1;
          if (icnt[d*32 +: 32] + 1 >= idle_th) req[d] <= 1'b0;
        end else icnt[d*32 +: 32] <= '0;
        case (st[d*4 +: 4])
          ON:      if (!req[d]) st[d*4 +: 4] <= CLKOFF;
          CLKOFF:  st[d*4 +: 4] <= ISO;
          ISO:     st[d*4 +: 4] <= SAVE;
          SAVE:    begin st[d*4 +: 4] <= SWOFF; tcnt[d*32 +: 32] <= '0; end
          SWOFF:   if (!pwr_ack[d]) st[d*4 +: 4] <= OFF;
                   else if (tcnt[d*32 +: 32] >= timeout) begin st[d*4 +: 4] <= ERR; err[d] <= 1'b1; end
                   else tcnt[d*32 +: 32] <= tcnt[d*32 +: 32] + 1;
          OFF:     if (req[d]) begin st[d*4 +: 4] <= SWON; tcnt[d*32 +: 32] <= '0; end
          SWON:    if (pwr_ack[d]) st[d*4 +: 4] <= RESTORE;
                   else if (tcnt[d*32 +: 32] >= timeout) begin st[d*4 +: 4] <= ERR; err[d] <= 1'b1; end
                   else tcnt[d*32 +: 32] <= tcnt[d*32 +: 32] + 1;
          RESTORE: st[d*4 +: 4] <= ISOOFF;
          ISOOFF:  st[d*4 +: 4] <= CLKON;
          CLKON:   st[d*4 +: 4] <= ON;
          ERR:     if (!err[d]) st[d*4 +: 4] <= OFF;   // software clears the error, then may retry
          default: st[d*4 +: 4] <= ERR;                 // recovery arm
        endcase
      end
    end
  end

  always_comb begin
    for (int d = 0; d < D; d++) begin
      logic [3:0] s;
      s = st[d*4 +: 4];
      clk_en[d]    = (s == ON) || (s == CLKON);
      iso_en[d]    = !(s == ON || s == CLKON || s == ISOOFF || s == CLKOFF);
      ret_save[d]  = (s == SAVE || s == SWOFF || s == OFF || s == SWON || s == ERR);
      pwr_en[d]    = !(s == SWOFF || s == OFF || s == ERR);
      dom_rst_n[d] = (s == ON) || (s == CLKON) || (s == CLKOFF);
      dom_err[d]   = err[d];
    end
    if (throttle) clk_en[NPU_DOM] = clk_en[NPU_DOM] & tog;
  end
endmodule

// Integrated clock-gating cell (latch-based, glitch-free). Replaced by the library ICG in synthesis.
module icg (
  input  logic clk,
  input  logic en,
  input  logic test_en,
  output logic gclk
);
  logic en_l;
  always_latch if (!clk) en_l = en | test_en;
  assign gclk = clk & en_l;
endmodule
