`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name:  counter  (seven-segment display driver)
// Project:      FPGA Geometry Dash (EE354, Nexys A7-100T)
// Description:  Extended from the EE354 example counter.v: same refresh-counter
//               scanning and active-low segment table, but it now drives all
//               8 digits and shows letters as well as numbers.
//
//   digits = 8 character codes of 5 bits, digits[39:35] is the LEFTMOST digit
//   (An7) and digits[4:0] is the rightmost (An0).
//
//   Codes: 0-9 digits, 10 A, 11 b, 12 C, 13 d, 14 E, 15 F, 16 H, 17 L, 18 n,
//          19 o, 20 P, 21 r, 22 S, 23 t, 24 U, 25 y, 26 '-', 31 blank
//////////////////////////////////////////////////////////////////////////////////
module counter(
	input clk,
	input [39:0] digits,
	output reg [7:0] anode,     // {An7..An0}, active low
	output reg [6:0] ssdOut     // {Ca..Cg},  active low
	);

	reg [19:0] refresh;          // 100 MHz / 2^17 = 763 Hz per digit, ~95 Hz per sweep
	reg [4:0]  ch;
	wire [2:0] sel = refresh[19:17];

	initial refresh = 20'd0;

	always @(posedge clk)
		refresh <= refresh + 20'd1;

	always @(*) begin
		anode = 8'b1111_1111;
		anode[sel] = 1'b0;
		case (sel)
			3'd0: ch = digits[4:0];
			3'd1: ch = digits[9:5];
			3'd2: ch = digits[14:10];
			3'd3: ch = digits[19:15];
			3'd4: ch = digits[24:20];
			3'd5: ch = digits[29:25];
			3'd6: ch = digits[34:30];
			default: ch = digits[39:35];
		endcase
	end

	always @(*) begin
		case (ch)          //  abcdefg  (0 = segment on)
			5'd0:  ssdOut = 7'b0000001;
			5'd1:  ssdOut = 7'b1001111;
			5'd2:  ssdOut = 7'b0010010;
			5'd3:  ssdOut = 7'b0000110;
			5'd4:  ssdOut = 7'b1001100;
			5'd5:  ssdOut = 7'b0100100;
			5'd6:  ssdOut = 7'b0100000;
			5'd7:  ssdOut = 7'b0001111;
			5'd8:  ssdOut = 7'b0000000;
			5'd9:  ssdOut = 7'b0000100;
			5'd10: ssdOut = 7'b0001000;  // A
			5'd11: ssdOut = 7'b1100000;  // b
			5'd12: ssdOut = 7'b0110001;  // C
			5'd13: ssdOut = 7'b1000010;  // d
			5'd14: ssdOut = 7'b0110000;  // E
			5'd15: ssdOut = 7'b0111000;  // F
			5'd16: ssdOut = 7'b1001000;  // H
			5'd17: ssdOut = 7'b1110001;  // L
			5'd18: ssdOut = 7'b1101010;  // n
			5'd19: ssdOut = 7'b1100010;  // o
			5'd20: ssdOut = 7'b0011000;  // P
			5'd21: ssdOut = 7'b1111010;  // r
			5'd22: ssdOut = 7'b0100100;  // S
			5'd23: ssdOut = 7'b1110000;  // t
			5'd24: ssdOut = 7'b1000001;  // U
			5'd25: ssdOut = 7'b1000100;  // y
			5'd26: ssdOut = 7'b1111110;  // -
			default: ssdOut = 7'b1111111; // blank
		endcase
	end

endmodule
