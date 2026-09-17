`timescale 1ns / 1ps

module scene_intersection_accelerator #(
    parameter int NUM_ENTRIES = 8)
(
    input  logic               clk,
    input  logic               rst_n,

    // Ray Control & Data
    input  logic               start_calc,
    input  logic signed [31:0] ray_point_x, ray_point_y, ray_point_z,
    input  logic signed [31:0] ray_vector_x, ray_vector_y, ray_vector_z,

    // Cache Control - Simple Spheres (Type 1)
    input  logic               ss_flush, ss_add_entry, ss_set_valid,
    input  logic [1:0]         ss_write_sel,
    input  logic [31:0]        ss_write_data,

    // Cache Control - Checker Spheres (Type 2)
    input  logic               cs_flush, cs_add_entry, cs_set_valid,
    input  logic [1:0]         cs_write_sel,
    input  logic [31:0]        cs_write_data,

    // Cache Control - Simple Halfspaces (Type 3)
    input  logic               sh_flush, sh_add_entry, sh_set_valid,
    input  logic [2:0]         sh_write_sel,
    input  logic [31:0]        sh_write_data,

    // Cache Control - Checker Halfspaces (Type 4)
    input  logic               ch_flush, ch_add_entry, ch_set_valid,
    input  logic [2:0]         ch_write_sel,
    input  logic [31:0]        ch_write_data,

    // Outputs
    output logic               out_valid,
    output logic               out_intersection_exists,
    output logic signed [31:0] out_min_time,
    output logic [2:0]         out_min_type, // 0: None, 1: SS, 2: CS, 3: SH, 4: CH
    output logic [IDX_W-1:0]   out_min_obj_idx
);

		
	 localparam int IDX_W = $clog2(NUM_ENTRIES);
	 
    // =========================================================================
    // CACHE CONTROLLERS[cite: 1, 2]
    // =========================================================================
    logic [NUM_ENTRIES-1:0] ss_write_on, ss_clear_entry;
    logic [NUM_ENTRIES-1:0] cs_write_on, cs_clear_entry;
    logic [NUM_ENTRIES-1:0] sh_write_on, sh_clear_entry;
    logic [NUM_ENTRIES-1:0] ch_write_on, ch_clear_entry;

    logic [1:0] ss_wsel_routed, cs_wsel_routed;
    logic [2:0] sh_wsel_routed, ch_wsel_routed;
    logic [31:0] ss_wdata_routed, cs_wdata_routed, sh_wdata_routed, ch_wdata_routed;

    sphere_cache_controller #(.N(NUM_ENTRIES)) ss_ctrl (
        .clk(clk), .rst_n(rst_n), .flush(ss_flush), .add_entry(ss_add_entry), 
        .write_sel_in(ss_write_sel), .write_data_in(ss_write_data),
        .write_on(ss_write_on), .clear_entry(ss_clear_entry), .write_sel(ss_wsel_routed), .write_data(ss_wdata_routed)
    );

    sphere_cache_controller #(.N(NUM_ENTRIES)) cs_ctrl (
        .clk(clk), .rst_n(rst_n), .flush(cs_flush), .add_entry(cs_add_entry), 
        .write_sel_in(cs_write_sel), .write_data_in(cs_write_data),
        .write_on(cs_write_on), .clear_entry(cs_clear_entry), .write_sel(cs_wsel_routed), .write_data(cs_wdata_routed)
    );

    halfspace_cache_controller #(.N(NUM_ENTRIES)) sh_ctrl (
        .clk(clk), .rst_n(rst_n), .flush(sh_flush), .add_entry(sh_add_entry), 
        .write_sel_in(sh_write_sel), .write_data_in(sh_write_data),
        .write_on(sh_write_on), .clear_entry(sh_clear_entry), .write_sel(sh_wsel_routed), .write_data(sh_wdata_routed)
    );

    halfspace_cache_controller #(.N(NUM_ENTRIES)) ch_ctrl (
        .clk(clk), .rst_n(rst_n), .flush(ch_flush), .add_entry(ch_add_entry), 
        .write_sel_in(ch_write_sel), .write_data_in(ch_write_data),
        .write_on(ch_write_on), .clear_entry(ch_clear_entry), .write_sel(ch_wsel_routed), .write_data(ch_wdata_routed)
    );

    // =========================================================================
    // DATAPATH: CACHES & ALUs[cite: 3, 4, 5, 6]
    // =========================================================================
    // Arrays for Tournament inputs
    logic signed [31:0] ss_alu_time [NUM_ENTRIES], cs_alu_time [NUM_ENTRIES];
    logic signed [31:0] sh_alu_time [NUM_ENTRIES], ch_alu_time [NUM_ENTRIES];
    
    logic ss_alu_exist [NUM_ENTRIES], cs_alu_exist [NUM_ENTRIES];
    logic sh_alu_exist [NUM_ENTRIES], ch_alu_exist [NUM_ENTRIES];

    // Completion trackers for variable latency sync
    logic [NUM_ENTRIES-1:0] ss_alu_done, cs_alu_done, sh_alu_done, ch_alu_done;
    logic [NUM_ENTRIES-1:0] ss_cache_valid, cs_cache_valid, sh_cache_valid, ch_cache_valid;

    genvar i;
    generate
        // --- 1. Simple Spheres ---
        for (i = 0; i < NUM_ENTRIES; i++) begin : gen_ss
            logic [31:0] rad, cx, cy, cz;
            logic alu_val_pulse;
            
            sphere_cache_entry cache (
                .clk(clk), .rst_n(rst_n), .write_on(ss_write_on[i]), .write_sel(ss_wsel_routed), .write_data(ss_wdata_routed),
                .set_valid(ss_set_valid & ss_write_on[i]), .clear_entry(ss_clear_entry[i]), .valid_flag(ss_cache_valid[i]),
                .radius(rad), .center_x(cx), .center_y(cy), .center_z(cz)
            );

            calc_sphere_intersection_time alu (
                .clk(clk), .rst_n(rst_n), .start_calc(start_calc), .valid_entry(ss_cache_valid[i]),
                .sphere_radius(rad), .sphere_center_x(cx), .sphere_center_y(cy), .sphere_center_z(cz),
                .ray_point_x(ray_point_x), .ray_point_y(ray_point_y), .ray_point_z(ray_point_z),
                .ray_vector_x(ray_vector_x), .ray_vector_y(ray_vector_y), .ray_vector_z(ray_vector_z),
                .intersection_time(ss_alu_time[i]), .validity_bit(alu_val_pulse), .intersection_exists(ss_alu_exist[i])
            );

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) ss_alu_done[i] <= 1'b0;
                else if (start_calc) ss_alu_done[i] <= 1'b0;
                else if (alu_val_pulse || !ss_cache_valid[i]) ss_alu_done[i] <= 1'b1;
            end
        end

        // --- 2. Checker Spheres ---
        for (i = 0; i < NUM_ENTRIES; i++) begin : gen_cs
            logic [31:0] rad, cx, cy, cz;
            logic alu_val_pulse;
            
            sphere_cache_entry cache (
                .clk(clk), .rst_n(rst_n), .write_on(cs_write_on[i]), .write_sel(cs_wsel_routed), .write_data(cs_wdata_routed),
                .set_valid(cs_set_valid & cs_write_on[i]), .clear_entry(cs_clear_entry[i]), .valid_flag(cs_cache_valid[i]),
                .radius(rad), .center_x(cx), .center_y(cy), .center_z(cz)
            );

            calc_sphere_intersection_time alu (
                .clk(clk), .rst_n(rst_n), .start_calc(start_calc), .valid_entry(cs_cache_valid[i]),
                .sphere_radius(rad), .sphere_center_x(cx), .sphere_center_y(cy), .sphere_center_z(cz),
                .ray_point_x(ray_point_x), .ray_point_y(ray_point_y), .ray_point_z(ray_point_z),
                .ray_vector_x(ray_vector_x), .ray_vector_y(ray_vector_y), .ray_vector_z(ray_vector_z),
                .intersection_time(cs_alu_time[i]), .validity_bit(alu_val_pulse), .intersection_exists(cs_alu_exist[i])
            );

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) cs_alu_done[i] <= 1'b0;
                else if (start_calc) cs_alu_done[i] <= 1'b0;
                else if (alu_val_pulse || !cs_cache_valid[i]) cs_alu_done[i] <= 1'b1;
            end
        end

        // --- 3. Simple Halfspaces ---
        for (i = 0; i < NUM_ENTRIES; i++) begin : gen_sh
            logic [31:0] nx, ny, nz;
            logic alu_val_pulse;
            
            halfspace_cache_entry cache (
                .clk(clk), .rst_n(rst_n), .write_on(sh_write_on[i]), .write_sel(sh_wsel_routed), .write_data(sh_wdata_routed),
                .set_valid(sh_set_valid & sh_write_on[i]), .clear_entry(sh_clear_entry[i]), .valid_flag(sh_cache_valid[i]),
                .point_x(), .point_y(), .point_z(), .normal_x(nx), .normal_y(ny), .normal_z(nz)
            );

            calc_halfspace_intersection_time alu (
                .clk(clk), .rst_n(rst_n), .start_calc(start_calc),
                .normal_x(nx), .normal_y(ny), .normal_z(nz),
                .ray_vector_x(ray_vector_x), .ray_vector_y(ray_vector_y), .ray_vector_z(ray_vector_z),
                .intersection_time(sh_alu_time[i]), .validity_bit(alu_val_pulse), .intersection_exists(sh_alu_exist[i])
            );

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) sh_alu_done[i] <= 1'b0;
                else if (start_calc) sh_alu_done[i] <= 1'b0;
                else if (alu_val_pulse || !sh_cache_valid[i]) sh_alu_done[i] <= 1'b1;
            end
        end

        // --- 4. Checker Halfspaces ---
        for (i = 0; i < NUM_ENTRIES; i++) begin : gen_ch
            logic [31:0] nx, ny, nz;
            logic alu_val_pulse;
            
            halfspace_cache_entry cache (
                .clk(clk), .rst_n(rst_n), .write_on(ch_write_on[i]), .write_sel(ch_wsel_routed), .write_data(ch_wdata_routed),
                .set_valid(ch_set_valid & ch_write_on[i]), .clear_entry(ch_clear_entry[i]), .valid_flag(ch_cache_valid[i]),
                .point_x(), .point_y(), .point_z(), .normal_x(nx), .normal_y(ny), .normal_z(nz)
            );

            calc_halfspace_intersection_time alu (
                .clk(clk), .rst_n(rst_n), .start_calc(start_calc),
                .normal_x(nx), .normal_y(ny), .normal_z(nz),
                .ray_vector_x(ray_vector_x), .ray_vector_y(ray_vector_y), .ray_vector_z(ray_vector_z),
                .intersection_time(ch_alu_time[i]), .validity_bit(alu_val_pulse), .intersection_exists(ch_alu_exist[i])
            );

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) ch_alu_done[i] <= 1'b0;
                else if (start_calc) ch_alu_done[i] <= 1'b0;
                else if (alu_val_pulse || !ch_cache_valid[i]) ch_alu_done[i] <= 1'b1;
            end
        end
    endgenerate

    // =========================================================================
    // FSM FOR VARIABLE LATENCY SYNC & TOURNAMENT TRIGGER
    // =========================================================================
    typedef enum logic [1:0] {IDLE, WAIT_ALUS, LATCH_L1, LATCH_L2} state_t;
    state_t state, next_state;

    logic all_alus_done;
    assign all_alus_done = (&ss_alu_done) & (&cs_alu_done) & (&sh_alu_done) & (&ch_alu_done);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else        state <= next_state;
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE:      if (start_calc)    next_state = WAIT_ALUS;
            WAIT_ALUS: if (all_alus_done) next_state = LATCH_L1;
            LATCH_L1:                     next_state = LATCH_L2;
            LATCH_L2:                     next_state = IDLE;
        endcase
    end

    logic trigger_l1;
    assign trigger_l1 = (state == WAIT_ALUS) && all_alus_done;

    // =========================================================================
    // TOURNAMENT TREES[cite: 7, 8, 9]
    // =========================================================================
    logic [IDX_W-1:0]   ss_min_idx, cs_min_idx, sh_min_idx, ch_min_idx;
    logic signed [31:0] ss_min_x,   cs_min_x,   sh_min_x,   ch_min_x;
    logic               ss_min_ex,  cs_min_ex,  sh_min_ex,  ch_min_ex;
    logic               l1_valid_out; // Synchronized valid flag across L1s

    min_positive_x_tournament #(.N(NUM_ENTRIES)) l1_ss (
        .clk(clk), .rst_n(rst_n), .valid_in(trigger_l1), .x_in(ss_alu_time), .y_in(ss_alu_exist),
        .min_idx(ss_min_idx), .min_x(ss_min_x), .is_there_intersection(ss_min_ex), .valid_out(l1_valid_out)
    );

    min_positive_x_tournament #(.N(NUM_ENTRIES)) l1_cs (
        .clk(clk), .rst_n(rst_n), .valid_in(trigger_l1), .x_in(cs_alu_time), .y_in(cs_alu_exist),
        .min_idx(cs_min_idx), .min_x(cs_min_x), .is_there_intersection(cs_min_ex), .valid_out()
    );

    min_positive_x_tournament #(.N(NUM_ENTRIES)) l1_sh (
        .clk(clk), .rst_n(rst_n), .valid_in(trigger_l1), .x_in(sh_alu_time), .y_in(sh_alu_exist),
        .min_idx(sh_min_idx), .min_x(sh_min_x), .is_there_intersection(sh_min_ex), .valid_out()
    );

    min_positive_x_tournament #(.N(NUM_ENTRIES)) l1_ch (
        .clk(clk), .rst_n(rst_n), .valid_in(trigger_l1), .x_in(ch_alu_time), .y_in(ch_alu_exist),
        .min_idx(ch_min_idx), .min_x(ch_min_x), .is_there_intersection(ch_min_ex), .valid_out()
    );

    logic signed [31:0] l2_x_in [4];
    logic               l2_y_in [4];
    logic [IDX_W-1:0]   l2_idx_in [4];

    always_comb begin
        l2_x_in[0] = ss_min_x; l2_y_in[0] = ss_min_ex; l2_idx_in[0] = ss_min_idx;
        l2_x_in[1] = cs_min_x; l2_y_in[1] = cs_min_ex; l2_idx_in[1] = cs_min_idx;
        l2_x_in[2] = sh_min_x; l2_y_in[2] = sh_min_ex; l2_idx_in[2] = sh_min_idx;
        l2_x_in[3] = ch_min_x; l2_y_in[3] = ch_min_ex; l2_idx_in[3] = ch_min_idx;
    end

    logic [1:0]         l2_min_idx;
    logic [IDX_W-1:0]   l2_min_obj_idx;
    logic signed [31:0] l2_min_x;
    logic               l2_is_there_inter;
    logic               l2_valid_out;

    min_positive_4types_idx #(.PREV_IDX_W(IDX_W)) l2_final (
        .clk(clk), .rst_n(rst_n), .valid_in(l1_valid_out),
        .x_in(l2_x_in), .y_in(l2_y_in), .min_type_idx_in(l2_idx_in),
        .min_idx(l2_min_idx), .min_type_idx_out(l2_min_obj_idx),
        .min_x(l2_min_x), .is_there_intersection(l2_is_there_inter), .valid_out(l2_valid_out)
    );

    // =========================================================================
    // OUTPUT REGISTERS 
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid               <= 1'b0;
            out_intersection_exists <= 1'b0;
            out_min_time            <= '0;
            out_min_type            <= '0;
            out_min_obj_idx         <= '0;
        end else if (start_calc) begin
            out_valid <= 1'b0; // Reset validity upon new ray arrival
        end else if (l2_valid_out) begin
            out_valid               <= 1'b1;
            out_intersection_exists <= l2_is_there_inter;
            out_min_time            <= l2_min_x;
            out_min_obj_idx         <= l2_min_obj_idx;
            // Map L2 index (0-3) to C type (1-4) or 0 if no intersection[cite: 9]
            out_min_type            <= l2_is_there_inter ? (3'd1 + {1'b0, l2_min_idx}) : 3'd0;
        end
    end

endmodule