module debuncer (
    input wire clk, // 10MHz clock
    input wire rst_n,
    input wire ena_in,
    output reg ena_out
);
    // 2-FFs synchronizer 
    //
    reg [1:0] sync_ff;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) sync_ff <= 2'b00;
        else sync_ff <= {sync_ff[0], ena_in};
    end
    //
    // 25ms prescaler
    //
    reg [17:0] prescaler;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prescaler <= 18'b0;
        end else begin
            if (prescaler < 18'd249999) begin // 10MHz / 400Hz = 250000 cycles for 25ms
                prescaler <= prescaler + 1'b1;
            end else begin
                prescaler <= 18'd0; // Reset prescaler
            end
        end
    end
    wire psc_enable;
    assign psc_enable = (prescaler == 18'd249999); // Enable signal when prescaler reaches 25ms
    //
    // 3-sampling synchronizer
    //
    reg [2:0] sample_ff;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) sample_ff <= 3'b000;
        else if (psc_enable) sample_ff <= {sample_ff[1:0], sync_ff[1]};
    end
    //
    // eneble output
    //
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ena_out <= 1'b0;
        end else begin
            if(sample_ff == 3'b111) ena_out <= 1'b1;
            else if(sample_ff == 3'b000) ena_out <= 1'b0;
        end
    end
endmodule
