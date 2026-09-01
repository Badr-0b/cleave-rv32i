/*
 * Copyright (c) 2026 Cleave project
 * SPDX-License-Identifier: Apache-2.0
 *
 * Cleave RV32I single-cycle core — TinyTapeout top-level wrapper (SKELETON).
 *
 * This is the step-2 compilable skeleton only. It instantiates the stub core
 * `cleave_core` and ties off all unused I/O so the design elaborates cleanly.
 * No datapath logic lives here.
 */

`default_nettype none

module tt_um_cleave (
    input  wire [7:0] ui_in,    // Dedicated inputs  -> PROVISIONAL: core control/data input bus
    output wire [7:0] uo_out,   // Dedicated outputs -> PROVISIONAL: core debug/status byte
    input  wire [7:0] uio_in,   // IOs: Input path   -> PROVISIONAL: unused for now (tied off)
    output wire [7:0] uio_out,  // IOs: Output path  -> PROVISIONAL: driven to 0 (not used yet)
    output wire [7:0] uio_oe,   // IOs: Enable path  -> PROVISIONAL: all inputs (0 = input)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset (TinyTapeout provides active-LOW reset)
);

  // --------------------------------------------------------------------------
  // Reset polarity conversion
  // TinyTapeout supplies an active-LOW reset (rst_n). The stub core declares an
  // active-HIGH reset (rst). Convert here so the seam is explicit and documented.
  // --------------------------------------------------------------------------
  wire rst = ~rst_n;

  // Core debug/status output (drives uo_out).
  wire [7:0] core_dbg;

  // --------------------------------------------------------------------------
  // Stub core instance. This is the seam where the RV32I datapath gets built.
  // PROVISIONAL pin mapping:
  //   ui_in    -> core_in   (external control/data input bus)
  //   core_dbg -> uo_out    (core debug/status byte)
  // --------------------------------------------------------------------------
  cleave_core u_core (
      .clk      (clk),
      .rst      (rst),
      .core_in  (ui_in),
      .core_dbg (core_dbg)
  );

  // --------------------------------------------------------------------------
  // Drive every output so nothing floats.
  // --------------------------------------------------------------------------
  assign uo_out  = core_dbg;   // dedicated outputs = core debug/status byte
  assign uio_out = 8'h00;      // bidir output path tied low (unused for now)
  assign uio_oe  = 8'h00;      // bidir pins configured as inputs (0 = input)

  // List all unused inputs to prevent warnings.
  // clk, rst_n, ui_in are used; ena and uio_in are not (yet).
  wire _unused = &{ena, uio_in, 1'b0};

endmodule

`default_nettype wire
