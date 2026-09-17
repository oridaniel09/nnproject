`timescale 1ns / 1ps

module min_positive_4types_idx #(
    parameter int PREV_IDX_W = 3 // Width of min_idx from preceding blocks
) (
    input  logic                      clk,
    input  logic                      rst_n,
    
    input  logic                      valid_in,

    // Inputs from exactly 4 previous blocks
    input  logic signed [31:0]        x_in [4],
    input  logic                      y_in [4],
    input  logic [PREV_IDX_W-1:0]     min_type_idx_in [4],

    // Outputs
    output logic [1:0]                min_idx,          // Which of the 4 blocks won (0 to 3)
    output logic [PREV_IDX_W-1:0]     min_type_idx_out, // The forwarded index from the winning block
    output logic signed [31:0]        min_x,
    output logic                      is_there_intersection,
    output logic                      valid_out
);

    typedef struct packed {
        logic signed [31:0]    val;
        logic [1:0]            idx;
        logic [PREV_IDX_W-1:0] type_idx;
        logic                  valid;
    } node_t;

    node_t l0 [4]; // Base inputs
    node_t l1 [2]; // First tournament level
    node_t l2;     // Final winner

    // =========================================================================
    // LEVEL 0: Pack inputs
    // =========================================================================
    always_comb begin
        for (int i = 0; i < 4; i++) begin
            l0[i].val      = x_in[i];
            l0[i].idx      = i[1:0];
            l0[i].type_idx = min_type_idx_in[i];
            l0[i].valid    = y_in[i];
        end
    end

    // =========================================================================
    // COMPARATOR FUNCTION
    // =========================================================================
    function automatic node_t compare_nodes(node_t left, node_t right);
        if (left.valid && right.valid) begin
            return (left.val <= right.val) ? left : right;
        end else if (left.valid) begin
            return left;
        end else if (right.valid) begin
            return right;
        end else begin
            compare_nodes.val      = '0;
            compare_nodes.idx      = '0;
            compare_nodes.type_idx = '0;
            compare_nodes.valid    = 1'b0;
            return compare_nodes;
        end
    endfunction

    // =========================================================================
    // TOURNAMENT LOGIC (Unrolled for N=4)
    // =========================================================================
    always_comb begin
        // Level 1: 4 nodes reduce to 2
        l1[0] = compare_nodes(l0[0], l0[1]);
        l1[1] = compare_nodes(l0[2], l0[3]);
        
        // Level 2: 2 nodes reduce to 1
        l2    = compare_nodes(l1[0], l1[1]);
    end

    // =========================================================================
    // OUTPUT STAGE
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            min_idx               <= '0;
            min_type_idx_out      <= '0;
            min_x                 <= '0;
            is_there_intersection <= 1'b0;
            valid_out             <= 1'b0;
        end else begin
            valid_out <= valid_in;

            if (valid_in) begin
                min_idx               <= l2.idx;
                min_type_idx_out      <= l2.type_idx;
                min_x                 <= l2.val;
                is_there_intersection <= l2.valid;
            end
        end
    end

endmodule