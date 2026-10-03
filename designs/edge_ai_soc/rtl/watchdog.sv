// Windowed watchdog. Software kicks by writing KEY 0x5AFE to KICK while the counter is inside
// the window (count <= WINDOW). A kick outside the window or with the wrong key is a fault
// (immediate bark). Expiry (count reaches 0) raises bark (interrupt) and reloads; a second
// expiry without a valid kick raises bite (SoC reset request). Once LOCK is set the watchdog
// cannot be disabled or reprogrammed until reset.
// Registers: 0x0 CTRL {lock, en}, 0x4 LOAD, 0x8 WINDOW, 0xC KICK (W) / COUNT (R), 0x10 STATUS {bite, bark} (W1C bark).
module watchdog (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        r_req,
  input  logic        r_we,
  input  logic [7:0]  r_addr,
  input  logic [31:0] r_wdata,
  output logic [31:0] r_rdata,
  output logic        bark,
  output logic        bite
);
  logic        en, lock;
  logic [31:0] load, window, count;

  always_comb begin
    case (r_addr)
      8'h00:   r_rdata = {30'd0, lock, en};
      8'h04:   r_rdata = load;
      8'h08:   r_rdata = window;
      8'h0C:   r_rdata = count;
      8'h10:   r_rdata = {30'd0, bite, bark};
      default: r_rdata = '0;
    endcase
  end

  wire kick_wr   = r_req && r_we && r_addr == 8'h0C;
  wire kick_good = kick_wr && r_wdata == 32'h5AFE && count <= window;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      en <= 1'b0; lock <= 1'b0; load <= 32'hFFFF; window <= 32'hFFFF; count <= 32'hFFFF;
      bark <= 1'b0; bite <= 1'b0;
    end else begin
      if (r_req && r_we && !lock)
        case (r_addr)
          8'h00: begin en <= r_wdata[0]; lock <= r_wdata[1]; count <= load; end
          8'h04: load <= r_wdata;
          8'h08: window <= r_wdata;
          default: ;
        endcase
      if (r_req && r_we && r_addr == 8'h10 && r_wdata[0]) bark <= 1'b0;
      if (en) begin
        if (kick_good) begin
          count <= load;
          bark  <= 1'b0;
        end else if (kick_wr) begin
          bark <= 1'b1;                           // bad key or kick outside the window
        end else if (count == 0) begin
          if (bark) bite <= 1'b1;                 // second expiry: reset request
          bark  <= 1'b1;
          count <= load;
        end else begin
          count <= count - 1;
        end
      end
    end
  end
endmodule
