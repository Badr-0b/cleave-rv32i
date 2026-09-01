/*
 * Unit test — cleave_dmem (byte-addressable data RAM).
 * Compile with -DSIMULATION so the RAM zero-inits (loads before stores read 0).
 * Covers: SW/LW word round-trip; SB at all 4 byte offsets read back via LB
 * (sign-extend) and LBU (zero-extend); SH at offsets 0 and 2 via LH/LHU; write-mask
 * isolation (SB must not clobber neighbor bytes); and a negative control on the
 * write enable (a store with mem_write=0 must NOT change memory).
 *
 * "Teeth" note: the mem_write=0 case is what proves the bench can fail — if the
 * store gating were broken, that check would catch it. Confirmed by temporarily
 * forcing mem_write high there during development (then reverted).
 */
`default_nettype none
`timescale 1ns/1ps

module tb_cleave_dmem;
  reg         clk = 1'b0;
  reg         mem_write;
  reg  [2:0]  funct3;
  reg  [31:0] addr, wdata;
  wire [31:0] rdata;
  integer     errors = 0;

  cleave_dmem dut (
    .clk(clk), .mem_write(mem_write), .funct3(funct3),
    .addr(addr), .wdata(wdata), .rdata(rdata)
  );

  always #5 clk = ~clk;

  localparam [2:0] F3_B=3'b000, F3_H=3'b001, F3_W=3'b010, F3_BU=3'b100, F3_HU=3'b101;

  // Synchronous store on the next rising edge.
  task store(input [2:0] f3, input [31:0] a, input [31:0] d);
    begin
      @(negedge clk); funct3 = f3; addr = a; wdata = d; mem_write = 1'b1;
      @(posedge clk); #1; mem_write = 1'b0;
    end
  endtask

  // Combinational load: drive size+address, sample rdata, compare.
  task load_chk(input [2:0] f3, input [31:0] a, input [31:0] exp, input [8*40-1:0] name);
    begin
      funct3 = f3; addr = a; #1;
      if (rdata !== exp) begin
        $display("FAIL %0s: rdata=%h exp=%h", name, rdata, exp);
        errors = errors + 1;
      end else $display("ok   %0s", name);
    end
  endtask

  integer o;
  initial begin
    mem_write = 0; funct3 = 0; addr = 0; wdata = 0;
    @(negedge clk);

    // ---- SW / LW word round-trip ----
    store(F3_W, 32'h0000_0020, 32'hAABB_CCDD);
    load_chk(F3_W, 32'h0000_0020, 32'hAABB_CCDD, "SW/LW word round-trip");

    // ---- SB at each byte offset, read back LB (sign) and LBU (zero) ----
    // Fresh word at 0x30, cleared first so neighbor lanes are known 0.
    store(F3_W, 32'h0000_0030, 32'h0000_0000);
    for (o = 0; o < 4; o = o + 1) begin
      store(F3_B, 32'h0000_0030 + o, 32'h0000_0080);      // store byte 0x80
      load_chk(F3_B,  32'h0000_0030 + o, 32'hFFFF_FF80,
               {"LB  sign-ext off=", "0" + o[7:0]});
      load_chk(F3_BU, 32'h0000_0030 + o, 32'h0000_0080,
               {"LBU zero-ext off=", "0" + o[7:0]});
      store(F3_B, 32'h0000_0030 + o, 32'h0000_0000);      // restore lane to 0
    end

    // ---- SH at offsets 0 and 2, read back LH (sign) and LHU (zero) ----
    store(F3_W, 32'h0000_0040, 32'h0000_0000);
    store(F3_H, 32'h0000_0040, 32'h0000_8123);            // half at offset 0
    load_chk(F3_H,  32'h0000_0040, 32'hFFFF_8123, "LH  sign-ext off=0");
    load_chk(F3_HU, 32'h0000_0040, 32'h0000_8123, "LHU zero-ext off=0");
    store(F3_H, 32'h0000_0042, 32'h0000_00FF);            // half at offset 2
    load_chk(F3_H,  32'h0000_0042, 32'h0000_00FF, "LH  off=2 (positive)");
    load_chk(F3_W,  32'h0000_0040, 32'h00FF_8123, "SH did not disturb low half");

    // ---- Write-mask isolation: SB one byte, neighbors intact ----
    store(F3_W, 32'h0000_0050, 32'hAABB_CCDD);
    store(F3_B, 32'h0000_0052, 32'h0000_0011);            // change only byte 2
    load_chk(F3_W, 32'h0000_0050, 32'hAA11_CCDD, "SB isolates its lane");

    // ---- Negative control: mem_write=0 must NOT write ----
    store(F3_W, 32'h0000_0060, 32'h1234_5678);            // establish known word
    @(negedge clk); funct3 = F3_W; addr = 32'h0000_0060; wdata = 32'hFFFF_FFFF;
    mem_write = 1'b0;                                      // gate OFF
    @(posedge clk); #1;
    load_chk(F3_W, 32'h0000_0060, 32'h1234_5678, "mem_write=0 -> no write");

    if (errors == 0) $display("\nALL cleave_dmem TESTS PASSED");
    else begin $display("\n%0d FAILURE(S)", errors); $fatal; end
    $finish;
  end
endmodule

`default_nettype wire
