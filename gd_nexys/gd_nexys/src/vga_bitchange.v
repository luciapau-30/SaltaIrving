`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name:  vga_bitchange  (renderer)
// Project:      FPGA Geometry Dash (EE354, Nexys A7-100T)
// Description:  Same role as the EE354 example: turns (hCount, vCount) into a
//               12-bit colour every pixel. The game logic now lives in game_sm;
//               this module only draws its state.
//
//   Draw order, front to back:
//     text  >  HUD progress bar  >  runner  >  finish line  >  spikes/blocks
//     >  lava floor  >  starry sky
//   On MENU / PAUSE / CRASH / GAME_OVER / WIN the scene is dimmed under the text.
//
//   Screen: x = hCount-145 (0..639), y = vCount-35 (0..479). Floor top at y = 400.
//////////////////////////////////////////////////////////////////////////////////
module vga_bitchange(
	input bright,
	input [9:0]  hCount, vCount,
	input [3:0]  state,
	input [1:0]  level,
	input [3:0]  lives,
	input        practice,
	input [12:0] scroll,
	input [8:0]  runner_h,
	input [5:0]  timer,
	input [15:0] crash_bcd,      // 4 BCD digits of the crash counter
	output reg [11:0] rgb
	);

	// states (same encoding as game_sm)
	localparam INIT = 4'd0, MENU = 4'd1, LOAD = 4'd2, PLAY = 4'd3, PAUSE = 4'd4,
	           CRASH = 4'd5, LEVEL_CLEAR = 4'd6, GAME_OVER = 4'd7, WIN = 4'd8;

	localparam [9:0]  FLOOR_Y  = 10'd400;
	localparam [12:0] FINISH_X = 13'd7328;    // FINISH_SCROLL + runner x + runner width

	// colours {R,G,B}
	localparam [11:0] BLACK     = 12'h000, WHITE = 12'hFFF;
	localparam [11:0] STAR      = 12'hFE9;
	localparam [11:0] RUNNER    = 12'hFE0, RUNNER_HIT = 12'hF22;
	localparam [11:0] BRICK     = 12'hE41, BRICK_LINE = 12'h810, BRICK_SHADOW = 12'hB20;
	localparam [11:0] BRICK_EDGE= 12'h200;
	localparam [11:0] SPIKE_IN  = 12'h112, SPIKE_EDGE = 12'hEEF;
	localparam [11:0] LAVA_TOP  = 12'hFD3, LAVA = 12'hD30, LAVA_HOT = 12'hF90, LAVA_DEEP = 12'h910;
	localparam [11:0] BAR_FILL  = 12'h2E4, BAR_BG = 12'h223;

	// display_controller registers 'bright' one pixel after hCount, so the visible
	// pixels are hCount 145..784; subtracting 145 makes them exactly x = 0..639.
	wire [9:0] x = hCount - 10'd145;
	wire [9:0] y = vCount - 10'd35;

	wire hud_on = (state == LOAD) || (state == PLAY) || (state == PAUSE) ||
	              (state == CRASH) || (state == LEVEL_CLEAR);
	wire dim    = (state == MENU) || (state == PAUSE) || (state == CRASH) ||
	              (state == GAME_OVER) || (state == WIN);

	// =====================================================================
	// World tiles
	// =====================================================================
	wire [12:0] wx = scroll + {3'b000, x};     // world x of this pixel
	wire [4:0]  lx = wx[4:0];                  // x inside the tile
	wire [2:0]  kind;
	level_rom rom(.level(level), .tile(wx[12:5]), .kind(kind));

	wire       above = (y < FLOOR_Y);
	wire [8:0] hy    = 9'd399 - y[8:0];        // pixel height above floor (valid if above)

	wire k_spike = (kind == 3'd1);
	wire k_b32   = (kind == 3'd2);
	wire k_b64   = (kind == 3'd3);
	wire k_spb   = (kind == 3'd4);             // 32 block with a spike on top
	wire [8:0] ttop = k_b64 ? 9'd64 : (k_b32 | k_spb) ? 9'd32 : 9'd0;

	// blocks: red bricks with a dark edge (style of the original game)
	wire       in_block   = above && (hy < ttop);
	wire [4:0] by         = ~hy[4:0];          // rows down from the block top
	wire       blk_edge   = (lx < 5'd2) || (lx > 5'd29) || (hy + 9'd2 >= ttop) || (hy < 9'd2);
	wire       brick_line = (by[3:0] == 4'd0) || (by[3:0] == 4'd15) ||
	                        (!by[4] && lx[3:0] == 4'd0) || (by[4] && lx[3:0] == 4'd8);
	wire       brick_shad = (lx[2:0] >= 3'd6) && (by[2:0] >= 3'd6);

	// spikes: triangle 32 wide x 32 tall, dark fill with a light outline
	wire [3:0] dx     = lx[4] ? lx[3:0] : (4'd15 - lx[3:0]);    // distance from centre
	wire [8:0] sh     = k_spb ? (hy - 9'd32) : hy;               // height inside the spike
	wire       s_rows = above && ((k_spike && hy < 9'd32) || (k_spb && hy >= 9'd32 && hy < 9'd64));
	wire [6:0] sdist  = {2'b00, dx, 1'b0} + {1'b0, sh[5:0]};
	wire       in_spike   = s_rows && (sdist <= 7'd31);
	wire       spike_edge = (sdist >= 7'd28) || (sh < 9'd2);

	// finish line: 16-px checkered strip
	wire in_finish = (wx >= FINISH_X) && (wx < FINISH_X + 13'd16) && (y >= 10'd44) && above;

	// =====================================================================
	// Runner: 32x32 smiley cube at screen x 128..159 (style of the original)
	// =====================================================================
	wire [8:0] rtop   = 9'd368 - runner_h;                 // FLOOR_Y - 32 - h
	wire [8:0] ry     = y[8:0] - rtop;
	wire       in_run = (x >= 10'd128) && (x < 10'd160) && (y < 10'd480) &&
	                    (y[8:0] >= rtop) && (y[8:0] < rtop + 9'd32);
	wire [4:0] px = x[4:0];
	wire [4:0] py = ry[4:0];
	wire run_edge  = (px < 5'd2) || (px > 5'd29) || (py < 5'd2) || (py > 5'd29);
	wire run_eye   = (py >= 5'd9) && (py <= 5'd13) &&
	                 (((px >= 5'd8) && (px <= 5'd11)) || ((px >= 5'd20) && (px <= 5'd23)));
	wire run_mouth = ((py >= 5'd22) && (py <= 5'd23) && (px >= 5'd9) && (px <= 5'd22)) ||
	                 ((py >= 5'd19) && (py <= 5'd22) &&
	                  (((px >= 5'd7) && (px <= 5'd8)) || ((px >= 5'd23) && (px <= 5'd24))));
	wire [11:0] run_col = ((state == CRASH) && timer[2]) ? RUNNER_HIT : RUNNER;

	// =====================================================================
	// Sky: navy gradient with a parallax star field
	// =====================================================================
	wire [9:0] stx  = x + scroll[12:3];            // stars move at 1/8 speed
	wire [8:0] star_cell = {y[8:5], stx[9:5]};
	wire [8:0] hsh  = {star_cell[2:0], star_cell[8:3]} ^ {star_cell[5:0], star_cell[8:6]} ^ (star_cell * 9'd5) ^ 9'h0B5;
	wire star = (y >= 10'd48) && hsh[8] && hsh[7] &&
	            (stx[4:1] == hsh[3:0]) && (y[4:1] == hsh[7:4]);
	// 4 blue levels down the screen, blended with a 2x2 ordered dither
	wire [1:0]  bayer = {x[0] ^ y[0], y[0]};
	wire [3:0]  sky_b = 4'h2 + {2'b00, y[8:7]} + ((y[6:5] > bayer) ? 4'h1 : 4'h0);
	wire [11:0] sky   = {4'h1, 4'h1, sky_b};

	// =====================================================================
	// Lava floor
	// =====================================================================
	// wavy glowing cracks every 16 rows that scroll with the world
	wire [9:0] fy    = y - FLOOR_Y;
	wire [3:0] lava_tri = wx[5] ? wx[4:1] : ~wx[4:1];          // triangle wave, 64-px period
	wire [3:0] wave  = fy[3:0] + lava_tri + {3'b000, fy[4]} * 4'd7;
	wire [11:0] lava = (fy < 10'd3)    ? LAVA_TOP :
	                   (fy > 10'd66)   ? LAVA_DEEP :
	                   (wave < 4'd2)   ? LAVA_HOT : LAVA;

	// =====================================================================
	// Scene colour (before dimming)
	// =====================================================================
	reg [11:0] scene;
	always @(*) begin
		if (in_run && state != INIT)
			scene = (run_edge || run_eye || run_mouth) ? BLACK : run_col;
		else if (in_finish)
			scene = (wx[3] ^ y[3]) ? WHITE : BLACK;
		else if (in_spike)
			scene = spike_edge ? SPIKE_EDGE : SPIKE_IN;
		else if (in_block)
			scene = blk_edge ? BRICK_EDGE : brick_line ? BRICK_LINE : brick_shad ? BRICK_SHADOW : BRICK;
		else if (!above)
			scene = lava;
		else if (star)
			scene = STAR;
		else
			scene = sky;
	end

	// =====================================================================
	// HUD progress bar (x 96..543, y 30..37); fill = scroll/16 (448 px at the end)
	// =====================================================================
	wire in_bar    = hud_on && (x >= 10'd96) && (x <= 10'd543) && (y >= 10'd30) && (y <= 10'd37);
	wire bar_frame = (x == 10'd96) || (x == 10'd543) || (y == 10'd30) || (y == 10'd37);
	wire bar_full  = ({1'b0, x} - 11'd97) < {2'b00, scroll[12:4]};
	wire [11:0] bar_col = bar_frame ? WHITE : bar_full ? BAR_FILL : BAR_BG;

	// =====================================================================
	// Text: one HUD line + one big line + four small lines
	//   big   = 20 cells of 32x32 (5x7 font scaled x4)
	//   small = 40 cells of 16x16 (5x7 font scaled x2)
	// =====================================================================
	reg [4:0] big_msg, s1_msg, s2_msg, s3_msg, s4_msg;
	always @(*) begin
		big_msg = 5'd0; s1_msg = 5'd0; s2_msg = 5'd0; s3_msg = 5'd0; s4_msg = 5'd0;
		case (state)
			MENU:      begin big_msg = 5'd1; s1_msg = 5'd6; s2_msg = 5'd7;
			                 s3_msg = practice ? 5'd8 : 5'd17; s4_msg = 5'd18; end
			PAUSE:     begin big_msg = 5'd2; s1_msg = 5'd9; end
			CRASH:     begin big_msg = 5'd3; s1_msg = practice ? 5'd11 : 5'd10; end
			GAME_OVER: begin big_msg = 5'd4; s1_msg = 5'd12; s2_msg = 5'd13; end
			WIN:       begin big_msg = 5'd5; s1_msg = 5'd12; s2_msg = 5'd14; end
			default:   ;
		endcase
	end

	wire [9:0] y_hud = y - 10'd8;
	wire [9:0] y_big = y - 10'd136;
	wire [9:0] y_s1  = y - 10'd192;
	wire [9:0] y_s2  = y - 10'd216;
	wire [9:0] y_s3  = y - 10'd240;
	wire [9:0] y_s4  = y - 10'd264;

	reg [4:0]  msg;
	reg [5:0]  idx;
	reg [2:0]  gcol, grow;
	reg [11:0] txt_col;
	always @(*) begin
		msg = 5'd0; idx = x[9:4]; gcol = x[3:1]; grow = 3'd7; txt_col = WHITE;
		if (hud_on && y_hud < 10'd16) begin
			msg = practice ? 5'd16 : 5'd15;  grow = y_hud[3:1];
		end else if (y_big < 10'd32) begin
			msg = big_msg; idx = {1'b0, x[9:5]}; gcol = x[4:2]; grow = y_big[4:2];
			case (state)
				MENU:            txt_col = 12'hFC0;
				CRASH, GAME_OVER: txt_col = 12'hF44;
				WIN:             txt_col = 12'h4F4;
				default:         txt_col = WHITE;
			endcase
		end else if (y_s1 < 10'd16) begin
			msg = s1_msg; grow = y_s1[3:1]; txt_col = 12'hEEE;
		end else if (y_s2 < 10'd16) begin
			msg = s2_msg; grow = y_s2[3:1]; txt_col = 12'hEEE;
		end else if (y_s3 < 10'd16) begin
			msg = s3_msg; grow = y_s3[3:1]; txt_col = 12'hAAB;
		end else if (y_s4 < 10'd16) begin
			msg = s4_msg; grow = y_s4[3:1]; txt_col = 12'hAAB;
		end
	end

	wire [5:0] code_raw;
	text_rom trom(.msg(msg), .idx(idx), .code(code_raw));

	// fill in live values: 48 level, 49 lives, 50..53 crash digits (digit d -> code 27+d)
	reg [3:0] ph_digit;
	always @(*) begin
		case (code_raw)
			6'd48:   ph_digit = {2'b00, level};
			6'd49:   ph_digit = lives;
			6'd50:   ph_digit = crash_bcd[15:12];
			6'd51:   ph_digit = crash_bcd[11:8];
			6'd52:   ph_digit = crash_bcd[7:4];
			default: ph_digit = crash_bcd[3:0];
		endcase
	end
	wire [5:0] code = (code_raw >= 6'd48) ? (6'd27 + {2'b00, ph_digit}) : code_raw;

	wire [4:0] glyph;
	font_rom from(.code(code), .row(grow), .bits(glyph));

	wire txt_on = (msg != 5'd0) && (grow != 3'd7) && (gcol >= 3'd1) && (gcol <= 3'd5) &&
	              glyph[3'd5 - gcol];

	// =====================================================================
	// Final colour
	// =====================================================================
	always @(*) begin
		if (~bright)
			rgb = BLACK;                         // force black outside the visible area
		else if (txt_on)
			rgb = txt_col;
		else if (in_bar)
			rgb = bar_col;
		else if (dim)
			rgb = {1'b0, scene[11:9], 1'b0, scene[7:5], 1'b0, scene[3:1]};
		else
			rgb = scene;
	end

endmodule
