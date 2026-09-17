module calc_halfspace_intersection_time (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               start_calc,
    
    input  logic signed [31:0] normal_x, normal_y, normal_z,
    input  logic signed [31:0] ray_vector_x, ray_vector_y, ray_vector_z,
    
    output logic signed [31:0] intersection_time,
    output logic               validity_bit,
    output logic               intersection_exists
);

    typedef enum logic [2:0] {
        IDLE          = 3'b000,
        CALC_DOT_MULT = 3'b001,
        CALC_DOT_ADD  = 3'b010,
        CHECK_ZERO    = 3'b011,
        CALC_DIV      = 3'b100
    } state_t;

    state_t current_state, next_state;

    // Datapath registers
    logic signed [31:0] mult_x, mult_y, mult_z;
    logic signed [31:0] v_dot;

    // Hardware DIV interface signals
    logic               div_start;
    logic               div_valid;
    logic signed [31:0] div_result;

    // External variable-latency DIV module instantiation
    // Computes: result = dividend / divisor
    q16_16_div u_div (
        .clk(clk),
        .rst_n(rst_n),
        .start(div_start),
        .dividend(32'hFFFF0000), // -1.0 represented in Q16.16
        .divisor(v_dot),
        .result(div_result),
        .valid(div_valid)
    );

    // Q16.16 Multiplication Function
    function automatic logic signed [31:0] q_mult(
        input logic signed [31:0] a, 
        input logic signed [31:0] b
    );
        logic signed [63:0] temp;
        temp = 64'(a) * 64'(b);
        return temp[47:16];
    endfunction

    // ---------------------------------------------------------
    // Sequential State and Datapath Logic
    // ---------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state       <= IDLE;
            validity_bit        <= 1'b0;
            intersection_exists <= 1'b0;
            div_start           <= 1'b0;
        end else begin
            current_state <= next_state;
            
            case (current_state)
                IDLE: begin
                    validity_bit <= 1'b0;
                end
                
                // Stage 1: Parallel multiplications for dot product
                CALC_DOT_MULT: begin
                    mult_x <= q_mult(normal_x, ray_vector_x);
                    mult_y <= q_mult(normal_y, ray_vector_y);
                    mult_z <= q_mult(normal_z, ray_vector_z);
                end
                
                // Stage 2: Summation for dot product (v)
                CALC_DOT_ADD: begin
                    v_dot <= mult_x + mult_y + mult_z;
                end
                
                // Stage 3: Check if v is zero
                CHECK_ZERO: begin
                    if (v_dot == 32'sd0) begin
                        intersection_time   <= 32'hFFFF0000; // -1.0 in Q16.16
                        intersection_exists <= 1'b0;
                        validity_bit        <= 1'b1;
                    end else begin
                        div_start <= 1'b1; // Trigger division
                    end
                end
                
                // Stage 4: Wait for division and check bounds
                CALC_DIV: begin
                    div_start <= 1'b0; // Pulse start
                    if (div_valid) begin
                        validity_bit <= 1'b1;
                        if (div_result > 32'sd0) begin
                            intersection_time   <= div_result;
                            intersection_exists <= 1'b1;
                        end else begin
                            intersection_time   <= 32'hFFFF0000; // -1.0 in Q16.16
                            intersection_exists <= 1'b0;
                        end
                    end
                end
            endcase
        end
    end

    // ---------------------------------------------------------
    // Next State Combinational Logic
    // ---------------------------------------------------------
    always_comb begin
        next_state = current_state; 
        
        case (current_state)
            IDLE: begin
                if (start_calc) next_state = CALC_DOT_MULT;
            end
            
            CALC_DOT_MULT: begin
                next_state = CALC_DOT_ADD;
            end
            
            CALC_DOT_ADD: begin
                next_state = CHECK_ZERO;
            end

            CHECK_ZERO: begin
                if (v_dot == 32'sd0) begin
                    next_state = IDLE;
                end else begin
                    next_state = CALC_DIV;
                end
            end

            CALC_DIV: begin
                if (div_valid) next_state = IDLE;
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

endmodule