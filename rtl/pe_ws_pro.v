`timescale 1ns/1ps
`default_nettype none

//=============================================================================
// pe_ws_pro.v
// Production-grade Weight-Stationary Processing Element (PE)
//
// Power Optimizations Implemented:
//   1. Operand Isolation     — registered mult inputs hold previous when idle
//   2. Multiplier Bypass     — skip multiply when activation or weight is zero
//   3. TPU-style PE Freeze   — freeze pipeline outputs when pe_enable is low
//   4. Sparse-Aware Control  — mult_en_reg gates valid propagation
//   5. Registered Mult Inputs — prevents input toggling into multiplier
//=============================================================================
module pe_ws_pro #(
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH  = 32
)(
    input  wire                         clk,
    input  wire                         rst,

    /* control */
    input  wire                         weight_load,
    input  wire                         acc_clear,
    input  wire                         valid_in,
    input  wire                         pe_enable,   // wavefront enable for this PE

    /* data inputs */
    input  wire signed [DATA_WIDTH-1:0] activation_in,
    input  wire signed [DATA_WIDTH-1:0] weight_in,
    input  wire signed [ACC_WIDTH-1:0]  psum_in,

    /* data outputs */
    output reg  signed [DATA_WIDTH-1:0] activation_out,
    output reg  signed [ACC_WIDTH-1:0]  psum_out,

    /* pipeline control */
    output reg                          valid_out
);

    //=========================================================================
    // Internal registers
    //=========================================================================
    reg signed [DATA_WIDTH-1:0] weight_reg;
    reg signed [ACC_WIDTH-1:0]  acc_reg;

    // Registered multiplier inputs (operand-hold / input-hold)
    reg signed [DATA_WIDTH-1:0] mult_a_reg;
    reg signed [DATA_WIDTH-1:0] mult_b_reg;
    reg                         mult_en_reg;

    // Multiplier pipeline registers
    reg signed [ACC_WIDTH-1:0]  pipe_mult_reg;
    reg signed [ACC_WIDTH-1:0]  pipe_psum_reg;
    reg                         pipe_valid_reg;

    //=========================================================================
    // [OPT-1] Sparsity detection: two-sided zero check
    //=========================================================================
    wire activation_zero;
    wire weight_zero;
    wire is_active;

    assign activation_zero = (activation_in == {DATA_WIDTH{1'b0}});
    assign weight_zero     = (weight_reg    == {DATA_WIDTH{1'b0}});
    assign is_active       = valid_in & ~activation_zero & ~weight_zero & pe_enable;

    //=========================================================================
    // Weight stationary register — loads weight once, holds it
    //=========================================================================
    always @(posedge clk) begin
        if (rst)
            weight_reg <= {DATA_WIDTH{1'b0}};
        else if (weight_load)
            weight_reg <= weight_in;
    end

    //=========================================================================
    // [OPT-2] Registered operand isolation (hold previous when skip)
    // Prevents multiplier input toggling — major switching reduction
    //=========================================================================
    always @(posedge clk) begin
        if (rst) begin
            mult_a_reg  <= {DATA_WIDTH{1'b0}};
            mult_b_reg  <= {DATA_WIDTH{1'b0}};
            mult_en_reg <= 1'b0;
        end else begin
            if (is_active) begin
                mult_a_reg  <= activation_in;
                mult_b_reg  <= weight_reg;
                mult_en_reg <= 1'b1;
            end else begin
                // hold previous values (usually zero) to prevent toggling
                mult_a_reg  <= mult_a_reg;
                mult_b_reg  <= mult_b_reg;
                mult_en_reg <= 1'b0;
            end
        end
    end

    //=========================================================================
    // Signed multiply (combinational from registered inputs — stable)
    //=========================================================================
    wire signed [ACC_WIDTH-1:0] mult_result_w;
    assign mult_result_w = $signed(mult_a_reg) * $signed(mult_b_reg);

    //=========================================================================
    // [OPT-3] Multiplier bypass — only update pipeline when mult was active
    //=========================================================================
    always @(posedge clk) begin
        if (rst) begin
            pipe_mult_reg  <= {ACC_WIDTH{1'b0}};
            pipe_psum_reg  <= {ACC_WIDTH{1'b0}};
            pipe_valid_reg <= 1'b0;
        end else begin
            if (mult_en_reg)
                pipe_mult_reg <= mult_result_w;
            else
                pipe_mult_reg <= {ACC_WIDTH{1'b0}};  // zero when bypassed

            pipe_psum_reg  <= psum_in;
            pipe_valid_reg <= valid_in & pe_enable & mult_en_reg;
        end
    end

    //=========================================================================
    // Accumulator with bypass: if mult was bypassed, psum passes through
    //=========================================================================
    always @(posedge clk) begin
        if (rst)
            acc_reg <= {ACC_WIDTH{1'b0}};
        else if (acc_clear)
            acc_reg <= {ACC_WIDTH{1'b0}};
        else if (pipe_valid_reg)
            acc_reg <= pipe_psum_reg + pipe_mult_reg;
    end

    //=========================================================================
    // [OPT-4] TPU-style PE freeze: hold outputs when pe_enable is low
    // Prevents register switching when PE is outside wavefront window
    //=========================================================================
    always @(posedge clk) begin
        if (rst) begin
            activation_out <= {DATA_WIDTH{1'b0}};
            psum_out       <= {ACC_WIDTH{1'b0}};
            valid_out      <= 1'b0;
        end else begin
            if (pe_enable) begin
                activation_out <= activation_in;
                psum_out       <= acc_reg;
                valid_out      <= valid_in;
            end else begin
                // hold values — avoids toggling when PE is disabled
                activation_out <= activation_out;
                psum_out       <= psum_out;
                valid_out      <= valid_out;
            end
        end
    end

endmodule

`default_nettype wire
