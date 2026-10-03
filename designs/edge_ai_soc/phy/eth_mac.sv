// Ethernet MAC (IEEE 802.3), byte-wide (GMII-style) interface to the PCS.
// TX: 7 x 0x55 preamble, 0xD5 SFD, payload (padded to 60 bytes), CRC-32 FCS (reflected 0xEDB88320,
//     init 0xFFFFFFFF, complemented, LSB byte first), then >= 12 bytes inter-packet gap.
// RX: waits for SFD, collects bytes while rx_dv, checks the FCS (CRC over data+FCS = 0x2144DF1C),
//     delivers the frame bytes without the FCS (padding is passed up, as in 802.3; the upper layer
//     uses length/type), flags fcs_err at frame end; counts good / bad frames.

module eth_mac_tx (
  input  logic       clk,
  input  logic       rst_n,
  // frame input (s_valid/s_ready stream, s_last on the final payload byte)
  input  logic       s_valid,
  input  logic [7:0] s_data,
  input  logic       s_last,
  output logic       s_ready,
  // to PCS
  output logic       tx_en,
  output logic [7:0] txd
);
  localparam logic [2:0] IDLE = 3'd0, PRE = 3'd1, DATA = 3'd2, PAD = 3'd3, FCS = 3'd4, IPG = 3'd5;
  logic [2:0]  st;
  logic [3:0]  cnt;
  logic [6:0]  len;
  logic [31:0] crc;

  function automatic logic [31:0] crc_next(input logic [31:0] c, input logic [7:0] b);
    logic [31:0] x;
    x = c ^ {24'd0, b};
    for (int i = 0; i < 8; i++) x = x[0] ? ((x >> 1) ^ 32'hEDB88320) : (x >> 1);
    crc_next = x;
  endfunction

  assign s_ready = (st == DATA);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      st <= IDLE; cnt <= '0; len <= '0; crc <= '1; tx_en <= 1'b0; txd <= '0;
    end else begin
      case (st)
        IDLE: begin
                tx_en <= 1'b0;
                if (s_valid) begin st <= PRE; cnt <= '0; end
              end
        PRE:  begin
                tx_en <= 1'b1; txd <= (cnt == 4'd7) ? 8'hD5 : 8'h55;
                cnt <= cnt + 1;
                if (cnt == 4'd7) begin st <= DATA; crc <= '1; len <= '0; end
              end
        DATA: if (s_valid) begin
                txd <= s_data; crc <= crc_next(crc, s_data);
                if (len != 7'd127) len <= len + 1;
                if (s_last) st <= (len + 1 < 60) ? PAD : FCS;
                cnt <= '0;
              end else txd <= 8'h00;               // stream must not stall mid-frame (underrun)
        PAD:  begin
                txd <= 8'h00; crc <= crc_next(crc, 8'h00); len <= len + 1;
                if (len + 1 >= 60) begin st <= FCS; cnt <= '0; end
              end
        FCS:  begin
                logic [31:0] f;
                f = ~crc;
                txd <= f[cnt[1:0]*8 +: 8];
                cnt <= cnt + 1;
                if (cnt == 4'd3) begin st <= IPG; cnt <= '0; end
              end
        IPG:  begin
                tx_en <= 1'b0; cnt <= cnt + 1;
                if (cnt == 4'd11) st <= IDLE;
              end
        default: st <= IDLE;
      endcase
    end
  end
endmodule

module eth_mac_rx (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        rx_dv,
  input  logic [7:0]  rxd,
  output logic        m_valid,
  output logic [7:0]  m_data,
  output logic        frame_done,
  output logic        fcs_err,
  output logic [15:0] good_frames,
  output logic [15:0] bad_frames
);
  logic        in_frame, dv_q;
  logic [31:0] crc;
  logic [7:0]  dl [4];         // delay line hides the 4 FCS bytes
  logic [2:0]  fill;

  function automatic logic [31:0] crc_next(input logic [31:0] c, input logic [7:0] b);
    logic [31:0] x;
    x = c ^ {24'd0, b};
    for (int i = 0; i < 8; i++) x = x[0] ? ((x >> 1) ^ 32'hEDB88320) : (x >> 1);
    crc_next = x;
  endfunction

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      in_frame <= 1'b0; dv_q <= 1'b0; crc <= '1; fill <= '0; m_valid <= 1'b0; m_data <= '0;
      frame_done <= 1'b0; fcs_err <= 1'b0; good_frames <= '0; bad_frames <= '0;
      for (int k = 0; k < 4; k++) dl[k] <= '0;
    end else begin
      m_valid <= 1'b0; frame_done <= 1'b0; fcs_err <= 1'b0;
      dv_q <= rx_dv;
      if (!in_frame) begin
        if (rx_dv && rxd == 8'hD5) begin in_frame <= 1'b1; crc <= '1; fill <= '0; end
      end else if (rx_dv) begin
        crc <= crc_next(crc, rxd);
        dl[0] <= rxd; dl[1] <= dl[0]; dl[2] <= dl[1]; dl[3] <= dl[2];
        if (fill == 3'd4) begin m_valid <= 1'b1; m_data <= dl[3]; end
        else fill <= fill + 1;
      end else begin                                 // end of frame
        in_frame <= 1'b0; frame_done <= 1'b1;
        if (crc == 32'hDEBB20E3) good_frames <= good_frames + 1;
        else begin fcs_err <= 1'b1; bad_frames <= bad_frames + 1; end
      end
    end
  end
endmodule
