`timescale 1ns/1ps
`default_nettype none

//=============================================================================
// systolic_array_4x4_pro.v
// Top-level 4×4 Weight-Stationary Systolic Array
//
// Features:
//   - Integrated controller (localized_controller_pro)
//   - Wavefront PE scheduling via cycle counter
//   - All PE power optimizations inherited from pe_ws_pro
//   - Partial sums flow top-to-bottom, activations flow left-to-right
//=============================================================================
module systolic_array_4x4_pro #(
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH  = 32,
    parameter SIZE       = 4
)(
    input  wire                              clk,
    input  wire                              rst,
    input  wire                              start,

    // one activation per row (packed bus)
    input  wire signed [DATA_WIDTH*SIZE-1:0] activation_in,
    // weight column vector per load cycle (packed bus)
    input  wire signed [DATA_WIDTH*SIZE-1:0] weight_in,

    // results: bottom-row partial sums (output of last row)
    output wire signed [ACC_WIDTH*SIZE-1:0]  result_out,
    output wire                              done
);

    //=========================================================================
    // Controller instantiation
    //=========================================================================
    wire        weight_load;
    wire        valid_in_ctrl;
    wire        acc_clear;
    wire [7:0]  cycle;

    localized_controller_pro #(
        .SIZE(SIZE)
    ) controller (
        .clk         (clk),
        .rst         (rst),
        .start       (start),
        .weight_load (weight_load),
        .acc_clear   (acc_clear),
        .valid_in    (valid_in_ctrl),
        .done        (done),
        .cycle       (cycle)
    );

    //=========================================================================
    // Unpack activation and weight buses
    //=========================================================================
    wire signed [DATA_WIDTH-1:0] act [0:SIZE-1];
    wire signed [DATA_WIDTH-1:0] w   [0:SIZE-1];

    genvar gi;
    generate
        for (gi = 0; gi < SIZE; gi = gi + 1) begin : unpack
            assign act[gi] = activation_in[DATA_WIDTH*(gi+1)-1 : DATA_WIDTH*gi];
            assign w[gi]   = weight_in[DATA_WIDTH*(gi+1)-1 : DATA_WIDTH*gi];
        end
    endgenerate

    //=========================================================================
    // PE interconnect wires
    //=========================================================================
    // Activation wires (left-to-right): act_wire[row][col]
    // act_wire[row][0] = external input, act_wire[row][col] = output of PE[row][col-1]
    wire signed [DATA_WIDTH-1:0] act_wire [0:SIZE-1][0:SIZE];

    // Partial sum wires (top-to-bottom): psum_wire[row][col]
    // psum_wire[0][col] = 0 (top), psum_wire[row][col] = psum_out of PE[row-1][col]
    wire signed [ACC_WIDTH-1:0]  psum_wire [0:SIZE][0:SIZE-1];

    // Valid out wires (unused at outputs, but needed for connectivity)
    wire valid_out_wire [0:SIZE-1][0:SIZE-1];

    //=========================================================================
    // Wavefront PE enable: PE[r][c] active when cycle >= r+c and cycle < r+c+SIZE
    //=========================================================================
    wire pe_en [0:SIZE-1][0:SIZE-1];

    generate
        for (gi = 0; gi < SIZE; gi = gi + 1) begin : gen_en_row
            genvar gj;
            for (gj = 0; gj < SIZE; gj = gj + 1) begin : gen_en_col
                assign pe_en[gi][gj] = (cycle >= (gi + gj)) && (cycle < (gi + gj + SIZE));
            end
        end
    endgenerate

    //=========================================================================
    // Connect external inputs
    //=========================================================================
    generate
        for (gi = 0; gi < SIZE; gi = gi + 1) begin : input_connect
            // Activation inputs: leftmost column
            assign act_wire[gi][0] = act[gi];
            // Partial sum inputs: top row = 0
            assign psum_wire[0][gi] = {ACC_WIDTH{1'b0}};
        end
    endgenerate

    //=========================================================================
    // PE array instantiation (SIZE × SIZE)
    //=========================================================================
    generate
        for (gi = 0; gi < SIZE; gi = gi + 1) begin : pe_row
            genvar gj;
            for (gj = 0; gj < SIZE; gj = gj + 1) begin : pe_col
                pe_ws_pro #(
                    .DATA_WIDTH (DATA_WIDTH),
                    .ACC_WIDTH  (ACC_WIDTH)
                ) pe_inst (
                    .clk            (clk),
                    .rst            (rst),
                    .weight_load    (weight_load),
                    .acc_clear      (acc_clear),
                    .valid_in       (valid_in_ctrl),
                    .pe_enable      (pe_en[gi][gj]),
                    .activation_in  (act_wire[gi][gj]),
                    .weight_in      (w[gj]),
                    .psum_in        (psum_wire[gi][gj]),
                    .activation_out (act_wire[gi][gj+1]),
                    .psum_out       (psum_wire[gi+1][gj]),
                    .valid_out      (valid_out_wire[gi][gj])
                );
            end
        end
    endgenerate

    //=========================================================================
    // Output: bottom-row partial sums are the final matrix product results
    //=========================================================================
    generate
        for (gi = 0; gi < SIZE; gi = gi + 1) begin : output_pack
            assign result_out[ACC_WIDTH*(gi+1)-1 : ACC_WIDTH*gi] = psum_wire[SIZE][gi];
        end
    endgenerate

endmodule

`default_nettype wire
