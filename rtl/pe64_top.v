`timescale 1ns/1ps
//=============================================================================
// File        : pe64_top.v
// Description : 64:6 Scalable Priority Encoder with Pipelined Registered I/O
//               Top-level design for DFT / Scan Chain / ATPG demonstration
//
// Architecture:
//   Stage 1  : Input Pipeline Registers  (64 FFs for d + 1 FF for enable)
//   Stage 2  : Combinational pe64_lookahead encoder (pure logic, no FFs)
//   Stage 3  : Output Pipeline Registers (6 FFs for q + 1 FF for valid)
//
//   Total sequential elements available for scan: 72 FFs
//
// Sub-modules included (bottom-up hierarchy):
//   pe4            : 4:2  base priority encoder
//   pe16           : 16:4 hierarchical priority encoder (uses 2x pe4)
//   pe64_standard  : 64:6 standard priority encoder  (reference variant)
//   pe64_lookahead : 64:6 lookahead priority encoder  (primary datapath)
//   pe64_top       : pipelined top-level DFT wrapper
//
// DFT Ports:
//   scan_en  : active-high scan enable (mux select: 0=functional, 1=shift)
//   scan_in  : serial scan chain input
//   scan_out : serial scan chain output (driven by Genus after DFT insertion)
//
// Priority convention:
//   Highest-numbered set bit wins.
//   e.g.  d[63]=1 (any lower)  =>  q = 63,  v = 1
//         d[0] =1  (rest = 0)  =>  q =  0,  v = 1
//         d    = 0             =>  q =  x,  v = 0
//=============================================================================


//=============================================================================
// Module : pe4
// 4:2 Base Priority Encoder
//=============================================================================
module pe4 (
    input  wire [3:0] d,
    output wire [1:0] q,
    output wire       v
);
    assign q[1] = d[3] | d[2];
    assign q[0] = d[3] | (d[1] & ~d[2]);
    assign v    = |d;
endmodule


//=============================================================================
// Module : pe16
// 16:4 Hierarchical Priority Encoder  (two-level pe4 tree)
//=============================================================================
module pe16 (
    input  wire [15:0] d,
    output wire [3:0]  q,
    output wire        v
);
    wire [3:0] row_status;
    reg  [3:0] selected_row;
    wire [1:0] row_index;
    wire [1:0] col_index;
    wire       row_valid;

    // OR-reduce each nibble to produce a 4-bit group-valid vector
    assign row_status[0] = |d[3:0];
    assign row_status[1] = |d[7:4];
    assign row_status[2] = |d[11:8];
    assign row_status[3] = |d[15:12];

    // Level-1: select the highest-priority group
    pe4 row_pe (
        .d(row_status),
        .q(row_index),
        .v(row_valid)
    );

    // MUX: feed the selected group to the column encoder
    always @(*) begin
        case (row_index)
            2'b00: selected_row = d[3:0];
            2'b01: selected_row = d[7:4];
            2'b10: selected_row = d[11:8];
            2'b11: selected_row = d[15:12];
            default: selected_row = 4'b0000;
        endcase
    end

    // Level-2: resolve bit position within the chosen group
    pe4 col_pe (
        .d(selected_row),
        .q(col_index),
        .v()
    );

    assign q = {row_index, col_index};
    assign v = row_valid;
endmodule


//=============================================================================
// Module : pe64_standard
// 64:6 Standard Priority Encoder (two-level pe16/pe4 tree)
// Included as reference design; pe64_lookahead is used by pe64_top.
//=============================================================================
module pe64_standard (
    input  wire [63:0] d,
    output wire [5:0]  q,
    output wire        v
);
    wire [15:0] row_status;
    reg  [3:0]  selected_row;
    wire [3:0]  row_index;
    wire [1:0]  col_index;
    wire        row_valid;

    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : row_logic
            assign row_status[i] = |d[(i*4)+3 : i*4];
        end
    endgenerate

    pe16 row_pe (
        .d(row_status),
        .q(row_index),
        .v(row_valid)
    );

    always @(*) begin
        case (row_index)
            4'h0: selected_row = d[3:0];   4'h1: selected_row = d[7:4];
            4'h2: selected_row = d[11:8];  4'h3: selected_row = d[15:12];
            4'h4: selected_row = d[19:16]; 4'h5: selected_row = d[23:20];
            4'h6: selected_row = d[27:24]; 4'h7: selected_row = d[31:28];
            4'h8: selected_row = d[35:32]; 4'h9: selected_row = d[39:36];
            4'hA: selected_row = d[43:40]; 4'hB: selected_row = d[47:44];
            4'hC: selected_row = d[51:48]; 4'hD: selected_row = d[55:52];
            4'hE: selected_row = d[59:56]; 4'hF: selected_row = d[63:60];
            default: selected_row = 4'b0000;
        endcase
    end

    pe4 col_pe (
        .d(selected_row),
        .q(col_index),
        .v()
    );

    assign q = {row_index, col_index};
    assign v = row_valid;
endmodule


//=============================================================================
// Module : pe64_lookahead
// 64:6 Lookahead Priority Encoder
// Uses parallel OR-reduction (dor[]) to pre-compute group validity,
// then a direct casex selects the column nibble without a second group MUX,
// reducing critical-path depth compared to pe64_standard.
//=============================================================================
module pe64_lookahead (
    input  wire [63:0] d,
    output wire [5:0]  q,
    output wire        v
);
    wire [15:0] dor;           // group OR-reduce: dor[i] = |d[4i+3:4i]
    wire [3:0]  row_index;     // 4-bit row (group) index from pe16
    wire [3:0]  column_data;   // nibble of the highest-priority group
    wire [1:0]  col_index;     // 2-bit column (bit) index within group
    wire        row_valid;

    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : row_or_logic
            assign dor[i] = |d[(i*4)+3 : i*4];
        end
    endgenerate

    // Level-1: find the highest-priority group
    pe16 row_encoder (
        .d(dor),
        .q(row_index),
        .v(row_valid)
    );

    // Lookahead column select: uses dor pattern to directly pick the nibble
    // (avoids re-MUXing through row_index after pe16)
    reg [3:0] column_data_reg;
    always @(*) begin
        casex (dor)
            16'b1xxxxxxxxxxxxxxx: column_data_reg = d[63:60];
            16'b01xxxxxxxxxxxxxx: column_data_reg = d[59:56];
            16'b001xxxxxxxxxxxxx: column_data_reg = d[55:52];
            16'b0001xxxxxxxxxxxx: column_data_reg = d[51:48];
            16'b00001xxxxxxxxxxx: column_data_reg = d[47:44];
            16'b000001xxxxxxxxxx: column_data_reg = d[43:40];
            16'b0000001xxxxxxxxx: column_data_reg = d[39:36];
            16'b00000001xxxxxxxx: column_data_reg = d[35:32];
            16'b000000001xxxxxxx: column_data_reg = d[31:28];
            16'b0000000001xxxxxx: column_data_reg = d[27:24];
            16'b00000000001xxxxx: column_data_reg = d[23:20];
            16'b000000000001xxxx: column_data_reg = d[19:16];
            16'b0000000000001xxx: column_data_reg = d[15:12];
            16'b00000000000001xx: column_data_reg = d[11:8];
            16'b000000000000001x: column_data_reg = d[7:4];
            16'b0000000000000001: column_data_reg = d[3:0];
            default:              column_data_reg = 4'b0000;
        endcase
    end

    assign column_data = column_data_reg;

    // Level-2: resolve bit position within the selected nibble
    pe4 col_encoder (
        .d(column_data),
        .q(col_index),
        .v()
    );

    assign q = {row_index, col_index};
    assign v = row_valid;
endmodule


//=============================================================================
// Module : pe64_top  (Design Under Test for DFT/ATPG)
//
// Pipelined registered wrapper around pe64_lookahead.
// Sequential elements provide flip-flops for scan chain insertion.
//
// Pipeline timing:
//   Cycle +1 : d_s1 <= d  (input capture)
//   Cycle +2 : q    <= q_comb  (output capture, valid when v=1)
//
// Scan chain summary (for Genus DFT insertion):
//   Bit  1 – 64  : d_s1[63:0]  (input stage registers)
//   Bit  65      : en_s1        (enable pipeline register)
//   Bit  66 – 71 : q[5:0]       (output index registers)
//   Bit  72      : v             (valid flag register)
//   Total        : 72 FFs  =>  1 scan chain of length 72
//=============================================================================
module pe64_top (
    input  wire        clk,       // System clock  (100 MHz target)
    input  wire        rst_n,     // Active-low synchronous reset
    input  wire        enable,    // Pipeline enable
    input  wire [63:0] d,         // 64-bit one-hot / arbitrary input
    output reg  [5:0]  q,         // 6-bit encoded index of highest set bit
    output reg         v,         // Valid flag: 1 when at least one input set
    // ----- DFT scan chain ports -----
    input  wire        scan_en,   // Scan enable  (active high, muxed-scan)
    input  wire        scan_in,   // Scan serial input
    output wire        scan_out   // Scan serial output  (driven by Genus DFT)
);

    // -------------------------------------------------------------------------
    // Stage 1 : Input Pipeline Registers
    //   64 FFs  : d_s1[63:0]
    //    1 FF   : en_s1
    // -------------------------------------------------------------------------
    reg [63:0] d_s1;    // registered input data
    reg        en_s1;   // registered enable

    always @(posedge clk) begin
        if (!rst_n) begin
            d_s1  <= 64'b0;
            en_s1 <= 1'b0;
        end else begin
            d_s1  <= d;
            en_s1 <= enable;
        end
    end

    // -------------------------------------------------------------------------
    // Stage 2 : Combinational Priority Encoding  (no FFs — pure logic)
    // -------------------------------------------------------------------------
    wire [5:0] q_comb;
    wire       v_comb;

    pe64_lookahead u_pe64 (
        .d  (d_s1),
        .q  (q_comb),
        .v  (v_comb)
    );

    // -------------------------------------------------------------------------
    // Stage 3 : Output Pipeline Registers
    //   6 FFs  : q[5:0]
    //   1 FF   : v
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            q <= 6'b0;
            v <= 1'b0;
        end else if (en_s1) begin
            q <= q_comb;
            v <= v_comb;
        end else begin
            v <= 1'b0;   // deassert valid when not enabled; q retains last value
        end
    end

    // =========================================================================
    // Scan Chain Note
    //   scan_in / scan_out / scan_en ports are declared here so that
    //   Cadence Genus can wire them during DFT insertion (replace_scan /
    //   connect_scan_chains).  scan_out is intentionally left undriven in
    //   the RTL — Genus will connect it to the last scan FF output.
    //   Total scannable registers: 72 (DFFQXL -> SDFFQXL post-DFT)
    // =========================================================================

endmodule
