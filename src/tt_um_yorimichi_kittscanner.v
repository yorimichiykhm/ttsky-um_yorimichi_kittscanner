// File:    tt_um_yorimichi_kittscanner.v
// Author:  Yorimichi
// Date:    2025-11-03
// Version: 1.0
// Brief:   Testbench for KITT Scanner Project
// 
// Copyright (c) 2025- Yorimichi
// License: Apache-2.0
// 
// Revision History:
//   1.0 - Initial release
//
//`default_nettype none

module tt_um_yorimichi_kittscanner (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);
wire ENA_debunced;
debuncer i_debouncer(
    .clk    (clk), // 10MHz clock
    .rst_n  (rst_n),
    .ena_in (ui_in[0]),
    .ena_out(ENA_debunced)
);
//
kitt_scan_core i_kitt_scan_core(
    .clk    (clk), 
    .rst_n  (rst_n),
    .ENA    (ENA_debunced), 
    .SPEED  (ui_in[3]), 
    .MODE   (ui_in[2:1]), 
    .OINV   (ui_in[4]),
    .OSEL   (ui_in[5]), 
    .LEDOUT (uo_out), 
    .PWMOUT (uio_out)
);
assign uio_oe = 8'hff;
wire _unused = &{ena, ui_in[7:6],uio_in, 1'b0};

endmodule