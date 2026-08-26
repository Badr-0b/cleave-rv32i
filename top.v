module tt_um_yourname_riscv (
    input  wire [7:0] ui_in,    // dedicated inputs
    output wire [7:0] uo_out,   // dedicated outputs
    input  wire [7:0] uio_in,   // bidir input path
    output wire [7:0] uio_out,  // bidir output path
    output wire [7:0] uio_oe,   // bidir enable, 1=output
    input  wire       ena,      // high when enabled
    input  wire       clk,
    input  wire       rst_n     // active-low reset
);