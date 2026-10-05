/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module mandelbrot_zoom (
    input  wire        clk,        // Rendszerórajel
    input  wire        rst_n,      // Aktív alacsony reset
    input  wire [9:0]  pixel_x,    // Aktuális X pixel koordináta (0-639)
    input  wire [9:0]  pixel_y,    // Aktuális Y pixel koordináta (0-479)
    input  wire        video_on,   // Aktív képernyőterület jelző
    output reg  [7:0]  red,        // RGB színkimenet (Vörös)
    output reg  [7:0]  green,      // RGB színkimenet (Zöld)
    output reg  [7:0]  blue        // RGB színkimenet (Kék)
);

    // Fixed-point (fixpontos) számábrázolás paraméterei
    // Q4.28 formátum: 4 bit egész rész (előjellel együtt), 28 bit tört rész
    parameter BIT_WIDTH = 32;
    parameter FRAC_BITS = 28;
    parameter MAX_ITER  = 64;      // Maximális iterációs szám

    // Zoom és pozíció regiszterek
    reg signed [BIT_WIDTH-1:0] center_x;
    reg signed [BIT_WIDTH-1:0] center_y;
    reg signed [BIT_WIDTH-1:0] zoom_factor; // Minél nagyobb, annál kisebb a látómező
    reg [23:0] frame_counter;

    // Zoom és középpont frissítése képkockánként
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Kezdeti értékek (Középpont: pl. a Seahorse Valley közelében)
            center_x     <= -32'sh00B00000; // -0.75 fixpontosan (-0.75 * 2^28)
            center_y     <= 32'sh001A0000;  // 0.1 fixpontosan
            zoom_factor  <= 32'sh01000000;  // Kezdeti skála (1.0 * 2^24 vagy megfelelő arány)
            frame_counter<= 0;
        end else begin
            // Minden képkocka végén (amikor pixel_x és pixel_y eléri a maximumot) növeljük a zoomot
            if (pixel_x == 639 && pixel_y == 479) begin
                frame_counter <= frame_counter + 1;
                // Exponenciális vagy lineáris zoom szimulációja léptetéssel
                if (frame_counter[4] == 1) begin
                    zoom_factor <= zoom_factor + (zoom_factor >> 6); // Folyamatos zoom befelé
                end
            end
        end
    end

    // Koordináta transzformáció: Pixel koordináták leképzése a komplex számsíkra
    // c_r = center_x + (pixel_x - 320) * zoom_factor
    // c_i = center_y + (pixel_y - 240) * zoom_factor
    wire signed [BIT_WIDTH-1:0] c_r;
    wire signed [BIT_WIDTH-1:0] c_i;

    assign c_r = center_x + ($signed({1'b0, pixel_x}) - 320) * (zoom_factor >> 8);
    assign c_i = center_y + ($signed({1'b0, pixel_y}) - 240) * (zoom_factor >> 8);

    // Mandelbrot Iterációs Logika (Pipeline-osított vagy állapógépes)
    reg signed [BIT_WIDTH-1:0] z_r, z_i;
    reg [5:0] iteration;
    reg [1:0] state;

    localparam IDLE = 2'b00, CALC = 2'b01, DONE = 2'b10;

    // Köztes fixpontos szorzatok (64 bites eredmény a túlcsordulás elkerülésére)
    wire signed [63:0] z_r_sq_long = ($signed(z_r) * $signed(z_r));
    wire signed [63:0] z_i_sq_long = ($signed(z_i) * $signed(z_i));
    wire signed [63:0] z_ri_long   = ($signed(z_r) * $signed(z_i));

    // Visszaalakítás Q4.28-ra eltolással
    wire signed [BIT_WIDTH-1:0] z_r_sq = z_r_sq_long[FRAC_BITS+BIT_WIDTH-1:FRAC_BITS];
    wire signed [BIT_WIDTH-1:0] z_i_sq = z_i_sq_long[FRAC_BITS+BIT_WIDTH-1:FRAC_BITS];
    wire signed [BIT_WIDTH-1:0] z_ri   = z_ri_long[FRAC_BITS+BIT_WIDTH-1:FRAC_BITS];

    // Iterációs állapotgép pixelenként
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            iteration <= 0;
            z_r <= 0;
            z_i <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (video_on) begin
                        z_r <= c_r;
                        z_i <= c_i;
                        iteration <= 0;
                        state <= CALC;
                    end
                end

                CALC: begin
                    // Ha elértük a maximális iterációt vagy a magnitúdó > 4 (fixpontosan 4 * 2^28 = 0x40000000)
                    if ((iteration == MAX_ITER) || ((z_r_sq + z_i_sq) > 32'sh40000000)) begin
                        state <= DONE;
                    end else begin
                        // Z_next = Z^2 + C
                        // Z_r_next = z_r^2 - z_i^2 + c_r
                        // Z_i_next = 2*z_r*z_i + c_i
                        z_r <= z_r_sq - z_i_sq + c_r;
                        z_i <= (z_ri << 1) + c_i;
                        iteration <= iteration + 1;
                    end
                end

                DONE: begin
                    state <= IDLE;
                end
            endcase
        end
    end

    // Színezési logika a kapott iterációs szám alapján
    always @(*) begin
        if (!video_on) begin
            red   = 8'h00;
            green = 8'h00;
            blue  = 8'h00;
        end else if (iteration == MAX_ITER) begin
            // A halmaz belső részei feketék
            red   = 8'h00;
            green = 8'h00;
            blue  = 8'h00;
        end else begin
            // Egyszerű pszeudo-színezés az iterációk alapján
            red   = iteration[4:0] << 3;
            green = iteration[3:0] << 4;
            blue  = iteration[5:2] << 4;
        end
    end

endmodule
