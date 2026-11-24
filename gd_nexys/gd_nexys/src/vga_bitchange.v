`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name:  vga_bitchange  (renderer)
// Project:      FPGA Geometry Dash (EE354, Nexys A7-100T)
// Description:  Same role as the EE354 example: turns (hCount, vCount) into a
//               12-bit colour every pixel. There is no frame buffer: every pixel
//               is worked out from scratch, 25 million times a second, from the
//               game state (scroll, runner height, level, ...) that game_sm holds.
//
//   Two themes, picked by the level:
//     level 1  Panama City   mint sky, skyline, lava road; traffic cones, barricades,
//                            potholes
//     level 2  Panama jungle orange sky, pixel-art jungle (assets/jungle.jpg), grass and
//                            dirt; steel spike traps, wooden crates, rivers
//
//   Draw order, front to back:
//     text > HUD bar > runner > finish line > obstacle sprites > floor (+ hole)
//     > background front layer > background back layer > clouds > sky
//
//   Parallax: the world (obstacles, floor) moves 1 px per px of 'scroll'. City: near
//   skyline 1/2, far skyline 1/4. Jungle: palms + bushes 1/2, mountains 1/4. Clouds 1/16.
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
	input [15:0] jump_bcd,       // 4 BCD digits of the jump counter
	output reg [11:0] rgb
	);

	// states (same encoding as game_sm)
	localparam INIT = 4'd0, MENU = 4'd1, LOAD = 4'd2, PLAY = 4'd3, PAUSE = 4'd4,
	           CRASH = 4'd5, LEVEL_CLEAR = 4'd6, GAME_OVER = 4'd7, WIN = 4'd8;

	localparam [9:0]  FLOOR_Y  = 10'd400;
	localparam [12:0] FINISH_X = 13'd7328;    // FINISH_SCROLL + runner x + runner width

	localparam [11:0] BLACK = 12'h000, WHITE = 12'hFFF;
	localparam [11:0] RUNNER = 12'hFE0, RUNNER_HIT = 12'hF22;
	localparam [11:0] LAVA_TOP = 12'hFD3, LAVA = 12'hD30, LAVA_HOT = 12'hF90, LAVA_DEEP = 12'h910;
	localparam [11:0] GRASS_TIP = 12'h6A3, GRASS = 12'h482, GRASS_EDGE = 12'h241;   // matched to
	localparam [11:0] DIRT = 12'h642, DIRT_DARK = 12'h420, DIRT_LIGHT = 12'h853, DIRT_DEEP = 12'h310;  // the jungle art
	localparam [11:0] BAR_FILL = 12'h2D4, BAR_BG = 12'h234, BAR_EDGE = 12'h122;
	localparam [11:0] HUD_DARK = 12'h233;

	wire [9:0] x = hCount - 10'd145;    // 'bright' is one pixel late, so visible x = hCount-145
	wire [9:0] y = vCount - 10'd35;

	wire jungle = (level == 2'd2);      // theme

	wire hud_on = (state == LOAD) || (state == PLAY) || (state == PAUSE) ||
	              (state == CRASH) || (state == LEVEL_CLEAR);
	wire dim    = (state == MENU) || (state == PAUSE) || (state == CRASH) ||
	              (state == GAME_OVER) || (state == WIN);

	// =====================================================================
	// World tiles under this pixel (level_rom: 0 empty, 1 spike, 2 block,
	// 3 tall block, 4 block + spike, 5 hole)
	// =====================================================================
	wire [12:0] wx = scroll + {3'b000, x};     // world x of this pixel
	wire [4:0]  lx = wx[4:0];                  // x inside the 32-px tile
	wire [2:0]  kind, kind_prev;               // this tile and the one to its left
	level_rom rom (.level(level), .tile(wx[12:5]),         .kind(kind));
	level_rom romp(.level(level), .tile(wx[12:5] - 8'd1),  .kind(kind_prev));

	wire       above = (y < FLOOR_Y);
	wire [8:0] hy    = 9'd399 - y[8:0];        // pixel height above floor (valid if above)
	wire [9:0] fy    = y - FLOOR_Y;            // pixel depth below the floor line

	// ---- obstacle sprites (sprite_rom: 32x32, colour 0 = transparent)
	wire lower = above && (hy < 9'd32);
	wire upper = above && (hy >= 9'd32) && (hy < 9'd64);
	reg  [2:0] spr_id;
	reg        spr_on;
	always @(*) begin
		spr_on = 1'b1; spr_id = 3'd0;
		case (kind)
			3'd1:    begin spr_on = lower; spr_id = 3'd0; end                    // cone / spikes
			3'd2:    begin spr_on = lower; spr_id = 3'd1; end                    // barricade / crate
			3'd3:    begin spr_on = lower | upper; spr_id = upper ? 3'd2 : 3'd3; end  // tall
			3'd4:    begin spr_on = lower | upper; spr_id = upper ? 3'd0 : 3'd4; end  // block + spike
			default: spr_on = 1'b0;
		endcase
	end
	wire [2:0] spr_px;
	sprite_rom sprites(.theme(jungle), .id(spr_id), .row(~hy[4:0]), .col(lx), .px(spr_px));
	wire in_sprite = spr_on && (spr_px != 3'd0);
	reg [11:0] spr_col;
	always @(*) begin
		case ({jungle, spr_px})
			// city: traffic orange, dark orange, white, ink, dark grey, yellow, light grey
			4'h1: spr_col = 12'hF61;  4'h2: spr_col = 12'hB30;  4'h3: spr_col = 12'hFFF;
			4'h4: spr_col = 12'h112;  4'h5: spr_col = 12'h445;  4'h6: spr_col = 12'hFC1;
			4'h7: spr_col = 12'hAAB;
			// jungle: light / mid / dark wood, ink, light / mid / dark steel
			4'h9: spr_col = 12'hD94;  4'hA: spr_col = 12'hA62;  4'hB: spr_col = 12'h631;
			4'hC: spr_col = 12'h211;  4'hD: spr_col = 12'hEEF;  4'hE: spr_col = 12'h99A;
			4'hF: spr_col = 12'h556;
			default: spr_col = BLACK;
		endcase
	end

	// ---- holes: pothole / river drawn into the floor (hole_rom, 64 x 80)
	wire [1:0] hole_here, hole_left;
	hole_rom holeA(.theme(jungle), .row(fy[6:0]), .col({1'b0, lx}), .px(hole_here));
	hole_rom holeB(.theme(jungle), .row(fy[6:0]), .col({1'b1, lx}), .px(hole_left));
	wire [1:0] here_px = (!above && kind == 3'd5)      ? hole_here : 2'd0;
	wire [1:0] left_px = (!above && kind_prev == 3'd5) ? hole_left : 2'd0;
	// two holes in a row: where one river's foam edge lies on the other's water, keep the water
	wire [1:0] hole_px = (here_px == 2'd3 && left_px != 2'd0) ? left_px :
	                     (here_px != 2'd0) ? here_px : left_px;
	reg [11:0] hole_col;
	always @(*) begin
		case ({jungle, hole_px})
			3'b001: hole_col = 12'h111;  3'b010: hole_col = 12'h333;  3'b011: hole_col = 12'h644;
			3'b101: hole_col = 12'h38D;  3'b110: hole_col = 12'h7CF;  3'b111: hole_col = 12'hCEF;
			default: hole_col = BLACK;
		endcase
	end

	// finish line: 16-px checkered strip
	wire in_finish = (wx >= FINISH_X) && (wx < FINISH_X + 13'd16) && (y >= 10'd44) && above;

	// =====================================================================
	// Runner: 32x32 smiley cube at screen x 128..159
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
	// Sky: vertical gradient blended with a 2x2 ordered dither
	// =====================================================================
	wire [1:0] bayer = {x[0] ^ y[0], y[0]};
	wire [3:0] grad  = {2'b00, y[8:7]} + ((y[6:5] > bayer) ? 4'h1 : 4'h0);   // 0..4 top->horizon
	wire [3:0] city_r = (4'hB + grad > 4'hE) ? 4'hE : 4'hB + grad;           // mint
	wire [11:0] sky = jungle ? {4'hF, 4'h9 + grad, 4'h3 + {2'b00, y[8:7]}}   // orange sunset
	                         : {city_r, 4'hF, 4'hE};

	// =====================================================================
	// Background band
	//   city:   skyline_rom, 555 x 158 seamless tile, two layers, y 242..399
	//   jungle: jungle_rom, 130 x 48 art pixels drawn 4x4 (520 x 192), mirrored into a
	//           1040-px loop, two layers (mountains / palms), y 208..399
	// =====================================================================
	localparam [9:0] SKY_W = 10'd555;
	localparam [9:0] CITY_Y = 10'd242, JUNGLE_Y = 10'd208;
	// offsets only change once per frame, so these dividers are not timing critical
	wire [12:0] off_f_full = {1'b0, scroll[12:1]} % {3'b000, SKY_W};    // near: 1/2 speed
	wire [12:0] off_b_full = {2'b00, scroll[12:2]} % {3'b000, SKY_W};   // far:  1/4 speed
	wire [12:0] off_jf_full = {1'b0, scroll[12:1]} % 13'd1040;          // jungle palms: 1/2
	wire [12:0] off_jb_full = {2'b00, scroll[12:2]} % 13'd1040;         // jungle mountains: 1/4
	wire [10:0] W1 = {1'b0, SKY_W}, W2 = {SKY_W, 1'b0};
	wire [10:0] cf_sum  = {1'b0, x} + off_f_full[10:0];
	wire [10:0] cb_sum  = {1'b0, x} + off_b_full[10:0];
	wire [10:0] cf_wrap = (cf_sum >= W2) ? cf_sum - W2 : (cf_sum >= W1) ? cf_sum - W1 : cf_sum;
	wire [10:0] cb_wrap = (cb_sum >= W2) ? cb_sum - W2 : (cb_sum >= W1) ? cb_sum - W1 : cb_sum;

	wire [9:0] c_row = y - CITY_Y;
	wire [2:0] city_b, city_f;
	skyline_rom city_bg(.row(c_row[7:0]), .col_back(cb_wrap[9:0]), .col_front(cf_wrap[9:0]),
	                    .back(city_b), .front(city_f));

	// screen x -> art column: add the layer's offset, wrap at 1040, divide by 4 (each
	// art pixel is 4 screen pixels wide), then mirror the second half (130..259 -> 129..0)
	wire [11:0] jf_sum = {2'b00, x} + off_jf_full[11:0];                // < 2 x 1040
	wire [11:0] jb_sum = {2'b00, x} + off_jb_full[11:0];
	wire [10:0] jf_u   = (jf_sum >= 12'd1040) ? jf_sum[10:0] - 11'd1040 : jf_sum[10:0];
	wire [10:0] jb_u   = (jb_sum >= 12'd1040) ? jb_sum[10:0] - 11'd1040 : jb_sum[10:0];
	wire [8:0]  jf_n   = jf_u[10:2],     jb_n   = jb_u[10:2];           // art column 0..259
	wire [8:0]  jf_mir = 9'd259 - jf_n,  jb_mir = 9'd259 - jb_n;        // mirrored half
	wire [7:0]  jf_col = (jf_n < 9'd130) ? jf_n[7:0] : jf_mir[7:0];
	wire [7:0]  jb_col = (jb_n < 9'd130) ? jb_n[7:0] : jb_mir[7:0];
	wire [9:0]  j_row  = y - JUNGLE_Y;                                  // /4 -> art row
	wire        jf_op, jb_op;
	wire [11:0] jf_color, jb_color;
	jungle_rom jungle_bg(.row(j_row[7:2]), .col_back(jb_col), .col_front(jf_col),
	                     .back_op(jb_op), .back_color(jb_color),
	                     .front_op(jf_op), .front_color(jf_color));

	wire in_city_band   = !jungle && above && (y >= CITY_Y);
	wire in_jungle_band =  jungle && above && (y >= JUNGLE_Y);
	wire [2:0] bg_b = in_city_band ? city_b : 3'd0;
	wire [2:0] bg_f = in_city_band ? city_f : 3'd0;
	wire [11:0] bgf_col = (bg_f == 3'd1) ? 12'h477 : 12'h364;           // teal / green towers
	wire [11:0] bgb_col = (bg_b == 3'd1) ? 12'h99A : 12'h788;           // grey towers
	wire        jungf_on = in_jungle_band && jf_op;                     // palms, bushes
	wire        jungb_on = in_jungle_band && jb_op;                     // mountains

	// clouds: 16 cells of 256 px in a 4096-px loop, at most one cloud each
	// (64x24 sprite drawn at 2x), moving at 1/16 of the world speed
	wire [11:0] cl_x  = {2'b00, x} + {3'b000, scroll[12:4]};
	reg         cl_on;
	reg  [9:0]  cl_y;
	reg  [7:0]  cl_off;
	reg         cl_shape;
	always @(*) begin
		cl_on = 1'b1; cl_shape = 1'b0;
		case (cl_x[11:8])
			4'd0:  begin cl_y = 10'd70;  cl_off = 8'd40;  end
			4'd1:  begin cl_y = 10'd118; cl_off = 8'd100; cl_shape = 1'b1; end
			4'd2:  begin cl_y = 10'd56;  cl_off = 8'd16;  end
			4'd3:  begin cl_y = 10'd104; cl_off = 8'd120; cl_shape = 1'b1; end
			4'd4:  begin cl_y = 10'd84;  cl_off = 8'd60;  cl_on = 1'b0; end
			4'd5:  begin cl_y = 10'd64;  cl_off = 8'd88;  end
			4'd6:  begin cl_y = 10'd112; cl_off = 8'd24;  cl_shape = 1'b1; end
			4'd7:  begin cl_y = 10'd76;  cl_off = 8'd110; end
			4'd8:  begin cl_y = 10'd108; cl_off = 8'd52;  cl_shape = 1'b1; end
			4'd9:  begin cl_y = 10'd58;  cl_off = 8'd8;   cl_on = 1'b0; end
			4'd10: begin cl_y = 10'd92;  cl_off = 8'd72;  end
			4'd11: begin cl_y = 10'd116; cl_off = 8'd124; cl_shape = 1'b1; end
			4'd12: begin cl_y = 10'd66;  cl_off = 8'd36;  end
			4'd13: begin cl_y = 10'd100; cl_off = 8'd96;  cl_shape = 1'b1; end
			4'd14: begin cl_y = 10'd60;  cl_off = 8'd12;  cl_on = 1'b0; end
			default: begin cl_y = 10'd110; cl_off = 8'd80; end
		endcase
	end
	wire [7:0] cl_lx = cl_x[7:0] - cl_off;          // 0..127 inside the cloud
	wire [9:0] cl_ly = y - cl_y;                    // 0..47 inside the cloud
	wire       in_cl_box = cl_on && (cl_x[7:0] >= cl_off) && (cl_lx < 8'd128) && (cl_ly < 10'd48);
	wire [1:0] cl_px;
	cloud_rom clouds(.shape(cl_shape), .row(cl_ly[5:1]), .col(cl_lx[6:1]), .px(cl_px));
	wire [1:0] cloud = in_cl_box ? cl_px : 2'd0;
	wire [11:0] cloud_col = (cloud == 2'd1) ? (jungle ? 12'hFEC : 12'hFFF)
	                                        : (jungle ? 12'hFC9 : 12'hDEF);

	// =====================================================================
	// Floor: lava road (city) / grass and dirt (jungle); both scroll with the world
	// =====================================================================
	wire [3:0]  lava_tri = wx[5] ? wx[4:1] : ~wx[4:1];          // triangle wave, 64-px period
	wire [3:0]  wave = fy[3:0] + lava_tri + {3'b000, fy[4]} * 4'd7;
	wire [11:0] lava = (fy < 10'd3)  ? LAVA_TOP :
	                   (fy > 10'd66) ? LAVA_DEEP :
	                   (wave < 4'd2) ? LAVA_HOT : LAVA;
	wire [3:0]  peb  = wx[6:3] ^ {fy[5:3], fy[2]} ^ {wx[8:7], wx[2:1]};  // pebble pattern
	wire [11:0] dirt = (fy < 10'd2)  ? (((wx[2:0] == 3'd1) || (wx[2:0] == 3'd5) || (wx[3:0] == 4'd10)) ? GRASS_TIP : GRASS) :
	                   (fy < 10'd6)  ? (((wx[3:0] ^ {fy[1:0], 2'b00}) == 4'd3) ? GRASS_TIP : GRASS) :
	                   (fy < 10'd8)  ? GRASS_EDGE :
	                   (fy > 10'd64) ? DIRT_DEEP :
	                   ((peb == 4'd0) && (fy[2:0] < 3'd2)) ? DIRT_LIGHT :
	                   ((peb == 4'd9) && (wx[1:0] != 2'd0)) ? DIRT_DARK : DIRT;
	wire [11:0] floor_col = jungle ? dirt : lava;

	// =====================================================================
	// Scene colour (before dimming)
	// =====================================================================
	reg [11:0] scene;
	always @(*) begin
		if (in_run && state != INIT)
			scene = (run_edge || run_eye || run_mouth) ? BLACK : run_col;
		else if (in_finish)
			scene = (wx[3] ^ y[3]) ? WHITE : BLACK;
		else if (in_sprite)
			scene = spr_col;
		else if (!above)
			scene = (hole_px != 2'd0) ? hole_col : floor_col;
		else if (jungf_on)
			scene = jf_color;
		else if (jungb_on)
			scene = jb_color;
		else if (bg_f != 3'd0)
			scene = bgf_col;
		else if (bg_b != 3'd0)
			scene = bgb_col;
		else if (cloud != 2'd0)
			scene = cloud_col;
		else
			scene = sky;
	end

	// =====================================================================
	// HUD progress bar (x 96..543, y 30..37); fill = scroll/16 (448 px at the end)
	// =====================================================================
	wire in_bar    = hud_on && (x >= 10'd96) && (x <= 10'd543) && (y >= 10'd30) && (y <= 10'd37);
	wire bar_frame = (x == 10'd96) || (x == 10'd543) || (y == 10'd30) || (y == 10'd37);
	wire bar_full  = ({1'b0, x} - 11'd97) < {2'b00, scroll[12:4]};
	wire [11:0] bar_col = bar_frame ? BAR_EDGE : bar_full ? BAR_FILL : BAR_BG;

	// =====================================================================
	// Text: one HUD line + one big line + four small lines
	//   big   = 20 cells of 32x32 (5x7 font scaled x4)
	//   small = 40 cells of 16x16 (5x7 font scaled x2)
	// =====================================================================
	reg [4:0] big_msg, s1_msg, s2_msg, s3_msg, s4_msg;
	always @(*) begin
		big_msg = 5'd0; s1_msg = 5'd0; s2_msg = 5'd0; s3_msg = 5'd0; s4_msg = 5'd0;
		case (state)
			MENU:      begin big_msg = 5'd1; s1_msg = jungle ? 5'd19 : 5'd6; s2_msg = 5'd7;
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
			txt_col = dim ? WHITE : HUD_DARK;            // readable on the light sky
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
			msg = s3_msg; grow = y_s3[3:1]; txt_col = 12'hCDE;
		end else if (y_s4 < 10'd16) begin
			msg = s4_msg; grow = y_s4[3:1]; txt_col = 12'hCDE;
		end
	end

	wire [5:0] code_raw;
	text_rom trom(.msg(msg), .idx(idx), .code(code_raw));

	// fill in live values: 48 level, 49 lives, 50..53 jump-counter digits (digit d -> code 27+d)
	reg [3:0] ph_digit;
	always @(*) begin
		case (code_raw)
			6'd48:   ph_digit = {2'b00, level};
			6'd49:   ph_digit = lives;
			6'd50:   ph_digit = jump_bcd[15:12];
			6'd51:   ph_digit = jump_bcd[11:8];
			6'd52:   ph_digit = jump_bcd[7:4];
			default: ph_digit = jump_bcd[3:0];
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
