module halfspace_cache_controller #(
    parameter N = 8 // Total number of cache entries
)(
    input  logic               clk,
    input  logic               rst_n,

    // Inputs
    input  logic               flush,
    input  logic               add_entry,
    input  logic [2:0]         write_sel_in,
    input  logic [31:0]        write_data_in,

    // Outputs to Cache Entries
    output logic [N-1:0]       write_on,
    output logic [N-1:0]       clear_entry,
    output logic [2:0]         write_sel,
    output logic [31:0]        write_data
);

    logic [$clog2(N+1)-1:0] top_index;
    logic                   add_entry_d; // Delayed signal for edge detection

    // Register previous state of add_entry
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            add_entry_d <= 1'b0;
        end else begin
            add_entry_d <= add_entry;
        end
    end

    // Sequential logic for top_index
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            top_index <= '0;
        end else if (flush) begin
            top_index <= '0;
        // Falling edge detection: increments after the write sequence finishes
        end else if (~add_entry && add_entry_d && (top_index < N)) begin
            top_index <= top_index + 1'b1;
        end
    end

    // Combinational routing and decoders
    always_comb begin
        write_on    = '0;
        clear_entry = '0;
        
        write_sel   = write_sel_in;
        write_data  = write_data_in;

        if (flush) begin
            clear_entry = {N{1'b1}};
        end

        if (add_entry && (top_index < N)) begin
            write_on[top_index] = 1'b1;
        end
    end

endmodule