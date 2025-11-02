// File:    kitt_scan_core.v
// Author:  Yorimichi
// Date:    2025-11-03
// Version: 1.0
// Brief:   Core module for KITT Scanner
// 
// Copyright (c) 2025- Yorimichi
// License: Apache-2.0
// 
// Revision History:
//   1.0 - Initial release
//
module kitt_scan_core(
    input  wire          clk, // 10MHz clock
    input  wire          rst_n,
    input  wire          ENA, // Enable signal from debouncer
    input  wire          SPEED, // Speed control signal (0: slow, 1: fast)
    input  wire [1:0]    MODE, // Mode control signal
    input  wire          OINV, // Output inversion signal
    input  wire          OSEL, // Output selection signal
    output wire [7:0]    LEDOUT, // Lamp output for KITT scanner
    output wire [7:0]    PWMOUT // PWM output for KITT scanner
);
// parameters
parameter NUM_NORM = 21'd1500000; // 150ms in clock cycles (10MHz)
parameter NUM_FAST = 21'd1000000; // 100ms in clock cycles  (10MHz) 
//
// mode signal capture
reg       cap_enable; // Capture enable signal
reg [1:0] mode_ff; // Mode signal captured from the input
reg       speed_ff; // Speed signal captured from the input
reg       oinv_ff; // Output inversion signal captured from the input
reg       osel_ff; // Output selection signal captured from the input
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mode_ff <= 2'b00; // Reset mode signal
        speed_ff <= 1'b0; // Reset speed signal
        oinv_ff <= 1'b0; // Reset output inversion signal
        osel_ff <= 1'b0; // Reset output selection signal
    end else begin
        if (cap_enable) begin
            mode_ff <= MODE; // Capture mode signal when enabled
            speed_ff <= SPEED; // Capture speed signal when enabled
            oinv_ff <= OINV; // Capture output inversion signal when enabled
            osel_ff <= OSEL; // Capture output selection signal when enabled
        end
    end
end 
//
// prescaler for 150ms/100ms selected by SPEED
reg       next_psc_enable; // Next value for prescaler enable
reg       psc_enable; // Prescaler enable signal
//
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        psc_enable <= 1'b0; // Reset prescaler enable signal
    end else begin
        psc_enable <= next_psc_enable; // Update prescaler enable signal
    end
end
//
reg [20:0] prescaler;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        prescaler <= 21'b0;
    end else begin
        if (!psc_enable) begin
            prescaler <= 21'b0; // Reset prescaler if not enabled
        end else if (speed_ff == 1'b0) begin // Slow mode (150ms)
            if (prescaler < NUM_NORM-1) begin // 10MHz / 66.67Hz = 1500000 cycles for 150ms
                prescaler <= prescaler + 1'b1;
            end else begin
                prescaler <= 21'd0; // Reset prescaler
            end
        end else begin // Fast mode (100ms)
            if (prescaler < NUM_FAST-1) begin // 10MHz / 100Hz = 1000000 cycles for 100ms
                prescaler <= prescaler + 1'b1;
            end else begin
                prescaler <= 21'd0; // Reset prescaler
            end
        end
    end
end
//
wire psc_ovf; // PWM overflow signal
assign psc_ovf = psc_enable ? 
                 (prescaler == (speed_ff ? (NUM_FAST - 1'b1) : (NUM_NORM - 1'b1) ) ) : 1'b1; 
//
// PWM generation
parameter NUM_PWM = 1000; // 100us in clock cycles (10MHz)
parameter PWM_DUTY0 = (NUM_PWM / 4) - 1;
parameter PWM_DUTY1 = (NUM_PWM / 10) - 1;
parameter PWM_DUTY2 = (NUM_PWM / 20) - 1;
//
reg [9:0] pwm_count;
reg       tgl_cnt;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pwm_count <= 10'b0; // Reset PWM counter
        tgl_cnt <= 1'b0;
    end else begin
        if(!pwm_enable) begin
            pwm_count <= 10'b0; // Reset PWM counter if PWM is disabled
        end else if (pwm_count < NUM_PWM -1) begin
            pwm_count <= pwm_count + 1'b1; // Increment PWM counter
        end else begin
            pwm_count <= 10'b0; // Reset PWM counter
            tgl_cnt <= ~tgl_cnt;
        end
    end
end
//
// PWM signals
reg pwm25, pwm10, pwm05;
wire nx_pwm25, nx_pwm10, nx_pwm05;
assign nx_pwm25 = pwm_enable ?  ((pwm_count < PWM_DUTY0) ? 1'b1 : 1'b0) : 1'b0; // 25% duty cycle
assign nx_pwm10 = pwm_enable ?  ((pwm_count < PWM_DUTY1) ? 1'b1 : 1'b0) : 1'b0; // 10% duty cycle
assign nx_pwm05 = pwm_enable ?  ((pwm_count < PWM_DUTY2) ? 1'b1 : 1'b0) : 1'b0; // 5% duty cycle
//
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pwm25 <= 1'b0; // Reset PWM25 signal
        pwm10 <= 1'b0; // Reset PWM10 signal
        pwm05 <= 1'b0; // Reset PWM05 signal
    end else begin
        pwm25 <= nx_pwm25;
        pwm10 <= nx_pwm10;
        pwm05 <= nx_pwm05;
    end
end
//
// output signals
reg [7:0] next_lvout; // Next value for LVOUT
//reg [7:0] next_pwmout; // Next value for PWMOUT
reg [7:0] pre_lvout; // Previous value for LVOUT
reg [7:0] pre_pwmout; // Previous value for PWMOUT
//
reg [2:0] next_pwmsel [0:7]; // Next value for PWM selection
reg [2:0] pwmsel [0:7];
// 0: 100%
// 1: 25%
// 2: 10%
// 3: 5%
// 4: 0%
//
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pre_lvout <= 8'b0; // Reset previous LVOUT
        pre_pwmout <= 8'b0; // Reset previous PWMOUT
        for(integer i=0; i<8; i=i+1) begin
            pwmsel[i] <= 3'd4; // Initialize all PWM selection to 0% duty
        end
    end else begin
        pre_lvout <= next_lvout; // Store current LVOUT for next cycle
        for(integer i=0; i<8; i=i+1) begin
            pre_pwmout[i] <= (next_pwmsel[i] == 3'd0) ? 1'b1 : // 100% duty
                             (next_pwmsel[i] == 3'd1) ? nx_pwm25 : // 25% duty
                             (next_pwmsel[i] == 3'd2) ? nx_pwm10 : // 10% duty
                             (next_pwmsel[i] == 3'd3) ? nx_pwm05 : // 5% duty
                             1'b0; // 0% duty
        end
        for(integer i=0; i<8; i=i+1) begin
            pwmsel[i] <= next_pwmsel[i];  // Update PWM selection for next cycle
        end
    end
end
assign LEDOUT = {8{oinv_ff}} ^ (osel_ff ? pre_pwmout : pre_lvout); // Select output based on OSEL and invert if OINV is high
//assign PWMOUT = oinv_ff ? ~pre_pwmout : pre_pwmout; // Invert PWMOUT if OINV is high
//
// state machine states
parameter IDLE = 6'd0;
parameter CAPT = 6'd1;
parameter HEAD_MD0 = 6'd10;
parameter HEAD_MD1 = 6'd40;
parameter HEAD_MD2 = 6'd50;
parameter HEAD_MD3 = 6'd2;
//
reg [5:0] state; // Current state of the FSM
//
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= IDLE; // Reset state to IDLE
    end else begin
        state <= next_state; // Update state based on next_state
    end
end
//
reg [5:0] next_state; // Next state of the FSM
reg       pwm_enable; // PWM enable signal
//
always@* begin
    if(ENA == 1'b0) begin
        next_state = IDLE; // If ENA is low, go to IDLE state
        next_psc_enable = 1'b0; // Disable prescaler
        cap_enable = 1'b0; // Disable capture
        pwm_enable = 1'b0; // Disable PWM
        next_lvout = 8'b0; // Set LVOUT to 0
        //next_pwmout = 8'b0; // Set PWMOUT to 0
        for(integer i=0; i<8; i=i+1) begin
            next_pwmsel[i] = 3'd4; // 0% duty
        end          
    end else begin
        if(psc_ovf == 1'b0) begin
            next_state = state; // Stay in the current state if prescaler overflow is not set
            next_psc_enable = 1'b1; // 
            cap_enable = 1'b0; // Keep capture disabled
            pwm_enable = 1'b1; // Keep PWM disabled
            next_lvout = pre_lvout; // Set LVOUT to 0
            //next_pwmout = pre_pwmout; // Set PWMOUT to 0
            for(integer i=0; i<8; i=i+1) begin
               next_pwmsel[i] = pwmsel[i]; // 0% duty
            end          
 
        end else begin
            case (state)
                IDLE: begin // psc_ovf is always 1
                    next_state = CAPT; // Move to capture state when ENA is high
                    next_psc_enable = 1'b0;
                    cap_enable = 1'b1;
                    pwm_enable = 1'b0;
                    next_lvout = 8'b0; // Set LVOUT to 0
                    //next_pwmout = 8'b0; // Set PWMOUT to 0
                    for(integer i=0; i<8; i=i+1) begin
                        next_pwmsel[i] = 3'd4; // 0% duty
                    end                      end
                CAPT: begin // psc_ovf is always 1                    
                    case (mode_ff)
                        2'b00: begin
                            next_state = HEAD_MD0; // Head mode 0
                            next_lvout = 8'b00000001;
                            //next_pwmout = 8'b00000001;
                            next_pwmsel[0] = 3'd0; // 100% duty
                            for(integer i=1; i<8; i=i+1) begin
                                next_pwmsel[i] = 3'd4; // 0% duty
                            end
                        end
                        2'b01: begin
                            next_state = HEAD_MD1; // Head mode 1
                            next_lvout = 8'b10000001;
                            //next_pwmout = 8'b10000001;
                            next_pwmsel[0] = 3'd0; // 100% duty
                            next_pwmsel[7] = 3'd0; // 100% duty
                            for(integer i=1; i<7; i=i+1) begin
                                next_pwmsel[i] = 3'd4; // 0% duty
                            end
                        end
                        2'b10: begin
                            next_state = HEAD_MD2; // Head mode 2
                            next_lvout = 8'b00000000;
                            //next_pwmout = 8'b00000000;
                            for(integer i=0; i<8; i=i+1) begin
                                next_pwmsel[i] = 3'd4; // 0% duty
                            end
                        end
                        2'b11: begin
                            next_state = HEAD_MD3; // Head mode 3
                            next_lvout = 8'b10101010;
                            //next_pwmout = {{4{1'b1, pwm05}}};
                            for(integer i=0; i<8; i=i+2) begin
                                next_pwmsel[i] = 3'd3; // 5% duty
                                next_pwmsel[i+1] = 3'd0; // 100% duty
                            end
                        end
                        default: begin
                            next_state = IDLE; // Default case to handle unexpected modes
                            next_lvout = 8'b00000000;
                            //next_pwmout = 8'b00000000;
                            for(integer i=0; i<8; i=i+1) begin
                                next_pwmsel[i] = 3'd4; // 0% duty
                            end
                        end
                    endcase
                    next_psc_enable = 1'b1;
                    cap_enable = 1'b1;
                    pwm_enable = 1'b0;
                end
                HEAD_MD0: begin
                    next_state = state + 1'b1;
                    next_psc_enable = 1'b1;
                    cap_enable = 1'b0;
                    pwm_enable = 1'b1;
                    next_lvout = 8'b00000011;
                    //next_pwmout = {6'b000000, 1'b1, pwm25};
                    next_pwmsel[0] = 3'd1; // 25% duty
                    next_pwmsel[1] = 3'd0; // 100% duty
                    for(integer i=2; i<8; i=i+1) begin
                        next_pwmsel[i] = 3'd4; // 0% duty
                    end
                end
                HEAD_MD0 + 1: begin
                    next_state = state + 1'b1;
                    next_psc_enable = 1'b1;
                    cap_enable = 1'b0;
                    pwm_enable = 1'b1;
                    next_lvout = 8'b00000111;
                    //next_pwmout = {5'b00000, 1'b1, pwm25, pwm10};
                    next_pwmsel[0] = 3'd2; // 10% duty
                    next_pwmsel[1] = 3'd1; // 25% duty
                    next_pwmsel[2] = 3'd0; // 100% duty 
                    for(integer i=3; i<8; i=i+1) begin
                        next_pwmsel[i] = 3'd4; // 0% duty
                    end
                end
                HEAD_MD0 + 2: begin
                    next_state = state + 1'b1;
                    next_psc_enable = 1'b1;
                    cap_enable = 1'b0;
                    pwm_enable = 1'b1;
                    next_lvout = 8'b00001111;
                    //next_pwmout = {4'b0000, 1'b1, pwm25, pwm10, pwm05};
                    next_pwmsel[0] = 3'd3; // 5% duty
                    next_pwmsel[1] = 3'd2; // 10% duty
                    next_pwmsel[2] = 3'd1; // 25% duty
                    next_pwmsel[3] = 3'd0; // 100% duty 
                    for(integer i=4; i<8; i=i+1) begin
                        next_pwmsel[i] = 3'd4; // 0% duty
                    end
                end
                HEAD_MD0 + 3,
                HEAD_MD0 + 4,
                HEAD_MD0 + 5,
                HEAD_MD0 + 6,
                HEAD_MD0 + 7,
                HEAD_MD0 + 8,
                HEAD_MD0 + 9: begin
                    next_state = state + 1'b1;
                    next_psc_enable = 1'b1;
                    cap_enable = 1'b0;
                    pwm_enable = 1'b1;
                    next_lvout = {pre_lvout[6:0], 1'b0};
                    //next_pwmout = {pre_pwmout[6:0], 1'b0};
                    next_pwmsel[0] = 3'd4;
                    for(integer i=1; i<8; i=i+1) begin
                        next_pwmsel[i] = pwmsel[i-1]; // left shift
                    end
                end
                HEAD_MD0 + 10: begin
                    next_state = state + 1'b1;
                    next_psc_enable = 1'b1;
                    cap_enable = 1'b0;
                    pwm_enable = 1'b1;
                    next_lvout = 8'b10000000;
                    // next_pwmout = {1'b1, 7'b0000000};
                    for(integer i=0; i<7; i=i+1) begin
                        next_pwmsel[i] = 3'd4; // 0% duty
                    end
                    next_pwmsel[7] = 3'd0; // 100% duty
                end
                HEAD_MD0 + 11: begin
                    next_state = state + 1'b1;
                    next_psc_enable = 1'b1;
                    cap_enable = 1'b0;
                    pwm_enable = 1'b1;
                    next_lvout = 8'b11000000;
                    //next_pwmout = {pwm25, 1'b1, 6'b000000};
                    for(integer i=0; i<6; i=i+1) begin
                        next_pwmsel[i] = 3'd4; // 0% duty
                    end
                    next_pwmsel[6] = 3'd0; // 100% duty
                    next_pwmsel[7] = 3'd1; // 25% duty
                end
                HEAD_MD0 + 12: begin
                    next_state = state + 1'b1;
                    next_psc_enable = 1'b1;
                    cap_enable = 1'b0;
                    pwm_enable = 1'b1;
                    next_lvout = 8'b11100000;
                    //next_pwmout = {pwm10, pwm25, 1'b1, 5'b00000};
                    for(integer i=0; i<5; i=i+1) begin
                        next_pwmsel[i] = 3'd4; // 0% duty
                    end
                    next_pwmsel[5] = 3'd0; // 100% duty
                    next_pwmsel[6] = 3'd1; // 25% duty
                    next_pwmsel[7] = 3'd2; // 10% duty
                end
                HEAD_MD0 + 13: begin
                    next_state = state + 1'b1;
                    next_psc_enable = 1'b1;
                    cap_enable = 1'b0;
                    pwm_enable = 1'b1;
                    next_lvout = 8'b11110000;
                    //next_pwmout = {pwm05, pwm10, pwm25, 1'b1, 4'b0000};
                    for(integer i=0; i<4; i=i+1) begin
                        next_pwmsel[i] = 3'd4; // 0% duty
                    end
                    next_pwmsel[4] = 3'd0; // 100% duty
                    next_pwmsel[5] = 3'd1; // 25% duty
                    next_pwmsel[6] = 3'd2; // 10% duty
                    next_pwmsel[7] = 3'd3; // 5% duty
                end
                HEAD_MD0 + 14,
                HEAD_MD0 + 15,
                HEAD_MD0 + 16,
                HEAD_MD0 + 17,
                HEAD_MD0 + 18,
                HEAD_MD0 + 19,
                HEAD_MD0 + 20: begin
                    next_state = state + 1'b1;
                    next_psc_enable = 1'b1;
                    cap_enable = 1'b0;
                    pwm_enable = 1'b1;
                    next_lvout = {1'b0, pre_lvout[7:1]};
                    //next_pwmout = {1'b0, pre_pwmout[7:1]};
                    for(integer i=0; i<7; i=i+1) begin
                        next_pwmsel[i] = pwmsel[i+1]; // right shift
                    end
                    next_pwmsel[7] = 3'd4; // 0% duty
                end
                HEAD_MD0 + 21: begin
                    next_state = HEAD_MD0;
                    next_psc_enable = 1'b1;
                    cap_enable = 1'b0;
                    pwm_enable = 1'b1;
                    next_lvout = 8'b00000001;
                    //next_pwmout = {7'b0000000, pwm05};
                    for(integer i=1; i<8; i=i+1) begin
                        next_pwmsel[i] = 3'd4; // 0% duty
                    end
                    next_pwmsel[0] = 3'd3; // 5% duty
                end
                // mode 1
                HEAD_MD1: begin
                    next_state = state + 1'b1;
                    next_psc_enable = 1'b1;
                    cap_enable = 1'b0;
                    pwm_enable = 1'b1;
                    next_lvout = 8'b10000001;
                    //next_pwmout = 8'b10000001;
                    for(integer i=1; i<7; i=i+1) begin
                        next_pwmsel[i] = 3'd4; // 0% duty
                    end
                    next_pwmsel[0] = 3'd0; // 100% duty
                    next_pwmsel[7] = 3'd0; // 100% duty
                end
                HEAD_MD1 + 1: begin
                    next_state = state + 1'b1;
                    next_psc_enable = 1'b1;
                    cap_enable = 1'b0;
                    pwm_enable = 1'b1;
                    next_lvout = 8'b11000011;
                    //next_pwmout = {pwm10, 1'b1, 2'b00, 2'b00, 1'b1, pwm10};
                    for(integer i=2; i<6; i=i+1) begin
                        next_pwmsel[i] = 3'd4; // 0% duty
                    end
                    next_pwmsel[0] = 3'd2; // 10% duty
                    next_pwmsel[1] = 3'd0; // 100% duty
                    next_pwmsel[6] = 3'd0; // 100% duty
                    next_pwmsel[7] = 3'd2; // 10% duty
                end
                HEAD_MD1 + 2, 
                HEAD_MD1 + 3, 
                HEAD_MD1 + 4: begin
                    next_state = state + 1'b1;
                    next_psc_enable = 1'b1;
                    cap_enable = 1'b0;
                    pwm_enable = 1'b1;
                    next_lvout = {1'b0, pre_lvout[7:5], pre_lvout[2:0], 1'b0};
                    //next_pwmout = {1'b0, pre_pwmout[7:5], pre_pwmout[2:0], 1'b0};
                    next_pwmsel[0] = 3'd4; // 0% duty
                    for(integer i=1; i<4; i=i+1) begin
                        next_pwmsel[i] = pwmsel[i-1]; // left shift
                    end
                    for(integer i=4; i<7; i=i+1) begin
                        next_pwmsel[i] = pwmsel[i+1]; // right shift
                    end
                    next_pwmsel[7] = 3'd4; // 0% duty
                end
                HEAD_MD1 + 5: begin
                    next_state = state + 1'b1;
                    next_psc_enable = 1'b1;
                    cap_enable = 1'b0;
                    pwm_enable = 1'b1;
                    next_lvout = 8'b00011000;
                    //next_pwmout = 8'b00011000;
                    for(integer i=0; i<3; i=i+1) begin
                        next_pwmsel[i] = 3'd4; // 0% duty
                    end
                    next_pwmsel[3] = 3'd0; // 100% duty
                    next_pwmsel[4] = 3'd0; // 100% duty
                    for(integer i=5; i<8; i=i+1) begin
                        next_pwmsel[i] = 3'd4; // 0% duty
                    end
                end 
                HEAD_MD1 + 6: begin
                    next_state = state + 1'b1;
                    next_psc_enable = 1'b1;
                    cap_enable = 1'b0;
                    pwm_enable = 1'b1;
                    next_lvout = 8'b00111100;
                    //next_pwmout = {2'b00, 1'b1, pwm10, pwm10, 1'b1, 2'b00};
                    for(integer i=0; i<2; i=i+1) begin
                        next_pwmsel[i] = 3'd4; // 0% duty
                    end
                    next_pwmsel[2] = 3'd0; // 100% duty
                    next_pwmsel[3] = 3'd2; // 10% duty
                    next_pwmsel[4] = 3'd2; // 10% duty
                    next_pwmsel[5] = 3'd0; // 100% duty
                    for(integer i=6; i<8; i=i+1) begin
                        next_pwmsel[i] = 3'd4; // 0% duty
                    end
                end
                HEAD_MD1 + 7: begin
                    next_state = state + 1'b1;
                    next_psc_enable = 1'b1;
                    cap_enable = 1'b0;
                    pwm_enable = 1'b1;
                    next_lvout = {pre_lvout[6:4], 1'b0, 1'b0, pre_lvout[3:1]};
                    //next_pwmout = {pre_pwmout[6:4], 1'b0, 1'b0, pre_pwmout[3:1]};
                    for(integer i=0; i<3; i=i+1) begin
                        next_pwmsel[i] = pwmsel[i+1]; // right shift
                    end
                    next_pwmsel[3] = 3'd4; // 0% duty
                    next_pwmsel[4] = 3'd4; // 0% duty
                    for(integer i=5; i<8; i=i+1) begin
                        next_pwmsel[i] = pwmsel[i-1]; // left shift
                    end                    
                end
                HEAD_MD1 + 8: begin
                    next_state = HEAD_MD1;
                    next_psc_enable = 1'b1;
                    cap_enable = 1'b0;
                    pwm_enable = 1'b1;
                    next_lvout = 8'b10000001;
                    //next_pwmout = 8'b10000001;
                    next_pwmsel[0] = 3'd0; // 100% duty
                    for(integer i=1; i<7; i=i+1) begin
                        next_pwmsel[i] = 3'd4; // 0% duty
                    end
                    next_pwmsel[7] = 3'd0; // 100% duty
                end
                // mode 2                               
                HEAD_MD2: begin
                    next_state = state + 1'b1;
                    next_psc_enable = 1'b1;
                    cap_enable = 1'b0;
                    pwm_enable = 1'b1;
                    next_lvout = 8'b10000000;
                    //next_pwmout = 8'b10000000;
                    for(integer i=0; i<7; i=i+1) begin
                        next_pwmsel[i] = 3'd4; // 0% duty
                    end
                    next_pwmsel[7] = 3'd0; // 100% duty
                end
                HEAD_MD2 + 1: begin
                    next_state = state + 1'b1;
                    next_psc_enable = 1'b1;
                    cap_enable = 1'b0;
                    pwm_enable = 1'b1;
                    next_lvout = {1'b0, pre_lvout[7:1]};
                    //next_pwmout = {pwm10, 1'b1, 6'b000000};
                    for(integer i=0; i<7; i=i+1) begin
                        next_pwmsel[i] = pwmsel[i+1]; // right shift
                    end
                    next_pwmsel[7] = 3'd2; // 10% duty
                end
                HEAD_MD2 + 2,
                HEAD_MD2 + 3,
                HEAD_MD2 + 4,
                HEAD_MD2 + 5,
                HEAD_MD2 + 6,
                HEAD_MD2 + 7,
                HEAD_MD2 + 8: begin
                    next_state = state + 1'b1;
                    next_psc_enable = 1'b1;
                    cap_enable = 1'b0;
                    pwm_enable = 1'b1;
                    next_lvout = {1'b0, pre_lvout[7:1]};
                    //next_pwmout = {1'b0, pre_pwmout[7:1]};
                    for(integer i=0; i<7; i=i+1) begin
                        next_pwmsel[i] = pwmsel[i+1]; // right shift
                    end
                    next_pwmsel[7] = 3'd4; // 0% duty
                end
                HEAD_MD2 + 9: begin
                    next_state = HEAD_MD2;
                    next_psc_enable = 1'b1;
                    cap_enable = 1'b0;
                    pwm_enable = 1'b1;                    
                    next_lvout = 8'b00000000;
                    //next_pwmout = 8'b00000000;
                    for(integer i=0; i<8; i=i+1) begin
                        next_pwmsel[i] = 3'd4; // 0% duty
                    end
                end
                // mode 3
                HEAD_MD3: begin
                    next_state = HEAD_MD3 + 1; 
                    next_psc_enable = 1'b1;
                    cap_enable = 1'b0;
                    pwm_enable = 1'b1;   
                    next_lvout = 8'b01010101;
                    //next_pwmout = {{4{pwm05, 1'b1}}};
                    for(integer i=0; i<4; i=i+1) begin
                        next_pwmsel[2*i] = 3'd0; // 100% duty
                        next_pwmsel[2*i+1] = 3'd3; // 5% duty
                    end
                end
                HEAD_MD3 + 1: begin
                    next_state = HEAD_MD3; 
                    next_psc_enable = 1'b1;
                    cap_enable = 1'b0;
                    pwm_enable = 1'b1;   
                    next_lvout = 8'b10101010;
                    //next_pwmout = {{4{1'b1, pwm05}}};
                    for(integer i=0; i<4; i=i+1) begin
                        next_pwmsel[2*i+1] = 3'd0; // 100% duty
                        next_pwmsel[2*i] = 3'd3; // 5% duty
                    end
                end
                default: begin
                    next_state = IDLE; // Default case to handle unexpected states
                    next_psc_enable = 1'b0; // Disable prescaler
                    cap_enable = 1'b0; // Disable capture 
                    pwm_enable = 1'b0; // Disable PWM
                    next_lvout = 8'b0; // Set LVOUT to 0
                    //next_pwmout = 8'b0; // Set PWMOUT to 0
                    for(integer i=0; i<8; i=i+1) begin
                        next_pwmsel[i] = 3'd4; // 0% duty
                    end
                end
            endcase
        end
    end
end
//
assign PWMOUT[0] = oinv_ff ^ pwm05;
assign PWMOUT[1] = oinv_ff ^ pwm10;
assign PWMOUT[2] = oinv_ff ^ pwm25;
assign PWMOUT[3] = psc_ovf;
assign PWMOUT[4] = tgl_cnt;
assign PWMOUT[5] = ENA;
assign PWMOUT[6] = speed_ff;
assign PWMOUT[7] = |mode_ff;
//
endmodule
