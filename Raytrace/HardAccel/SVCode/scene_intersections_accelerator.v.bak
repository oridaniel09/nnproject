module scene_intersections_accelerator #(
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
