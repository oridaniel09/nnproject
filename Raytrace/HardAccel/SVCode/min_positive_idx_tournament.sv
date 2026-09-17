`timescale 1ns / 1ps

module min_positive_x_tournament #(
    parameter int N = 8) 
(
    input  logic                      clk,
    input  logic                      rst_n,
    
    input  logic                      valid_in,

    // Inputs
    input  logic signed [31:0]        x_in [N],
    input  logic                      y_in [N],

    // Outputs
    output logic [IDX_W-1:0]          min_idx,
    output logic signed [31:0]        min_x,
    output logic                      is_there_intersection,
    output logic                      valid_out
);
	 
	 localparam int IDX_W  = ($clog2(N) > 0) ? $clog2(N) : 1;
    localparam int LEVELS = $clog2(N);
    localparam int P2_N   = 1 << LEVELS;


    typedef struct packed {
        logic signed [31:0] val;
        logic [IDX_W-1:0]   idx;
        logic               valid;
    } tree_node_t;

    tree_node_t tree [LEVELS+1][P2_N];

    // =========================================================================
    // LEVEL 0: Populate base
    // =========================================================================
    always_comb begin
        for (int i = 0; i < P2_N; i++) begin
            if (i < N) begin
                tree[0][i].val   = x_in[i];
                tree[0][i].idx   = i[IDX_W-1:0];
                tree[0][i].valid = y_in[i];
            end else begin
                tree[0][i].val   = '0;
                tree[0][i].idx   = '0;
                tree[0][i].valid = 1'b0; 
            end
        end
    end

    // =========================================================================
    // TOURNAMENT LOGIC
    // =========================================================================
    genvar lvl, i;
    generate
        for (lvl = 0; lvl < LEVELS; lvl++) begin : g_level
            for (i = 0; i < (P2_N >> (lvl + 1)); i++) begin : g_node
                
                always_comb begin
                    automatic tree_node_t left  = tree[lvl][2*i];
                    automatic tree_node_t right = tree[lvl][2*i+1];

                    if (left.valid && right.valid) begin
                        if (left.val <= right.val) begin
                            tree[lvl+1][i] = left;
                        end else begin
                            tree[lvl+1][i] = right;
                        end
                    end 
                    else if (left.valid) begin
                        tree[lvl+1][i] = left;
                    end 
                    else if (right.valid) begin
                        tree[lvl+1][i] = right;
                    end 
                    else begin
                        tree[lvl+1][i].val   = '0;
                        tree[lvl+1][i].idx   = '0;
                        tree[lvl+1][i].valid = 1'b0;
                    end
                end

            end
        end
    endgenerate

    // =========================================================================
    // OUTPUT STAGE
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            min_idx               <= '0;
            min_x                 <= '0;
            is_there_intersection <= 1'b0;
            valid_out             <= 1'b0;
        end else begin
            valid_out <= valid_in;

            if (valid_in) begin
                min_idx               <= tree[LEVELS][0].idx;
                min_x                 <= tree[LEVELS][0].val;
                is_there_intersection <= tree[LEVELS][0].valid;
            end
        end
    end

endmodule