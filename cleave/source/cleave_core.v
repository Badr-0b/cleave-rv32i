/*
 * Copyright (c) 2026 Cleave project
 * SPDX-License-Identifier: Apache-2.0
 *
 * cleave_core — RV32I single-cycle core (full datapath).
 *
 * One instruction is fetched, decoded, executed, and retired every clock. The
 * eight leaf modules do the work; this file is the integration — the muxes that
 * route operands, writeback, and the next PC. Data flow per cycle:
 *
 *   fetch    : u_pc holds the address; u_imem returns the instruction (comb ROM).
 *   decode   : split instr into opcode/funct3/funct7b5/rs1/rs2/rd; u_control turns
 *              those into the datapath control vector; u_immgen rebuilds the imm.
 *   execute  : u_regfile reads rs1/rs2; the ALU operates on the selected operands
 *              (rs1 or PC, rs2 or imm); u_branch evaluates the branch condition.
 *   memory   : u_dmem does sub-word stores and sign/zero-extended sub-word loads.
 *   writeback: result_src picks ALU / memory / PC+4 / immediate into the regfile.
 *   next PC  : PC+4, a branch/JAL target (PC+imm), or a JALR target (rs1+imm & ~1).
 *
 * Two shared-hardware notes worth calling out:
 *   - JALR reuses the ALU adder. u_control drives JALR as ADD with alu_src_b=imm
 *     (alu_src_a=0 -> rs1), so alu_res already equals rs1+imm on a JALR, and its
 *     result is otherwise unused there (JALR writes back PC+4). The next-PC mux
 *     takes alu_res & ~1 as the JALR target — no second adder.
 *   - Plain combinational register reads (no write-through). In a single-cycle
 *     datapath wd is combinational from the read ports, so forwarding it back on
 *     rd==rs would form a combinational loop; the regfile deliberately does not.
 *
 * Observability: a program ends in `BEQ x0,x0,0` and parks. The read-out port
 * exposes any register one byte at a time on the 8-bit debug output —
 * core_in[4:0] selects the register, core_in[6:5] selects the byte.
 *
 * Reset is active-HIGH (the wrapper converts TinyTapeout's active-low rst_n).
 *
 * Not handled by design (no trap path, matching cleave_dmem / illegal_instr):
 * misaligned data accesses and misaligned JALR targets are undefined; imem still
 * fetches the containing word, so the core stays well-defined.
 */

`default_nettype none

module cleave_core (
    input  wire       clk,       // core clock
    input  wire       rst,       // active-HIGH reset (PC -> 0)
    input  wire [7:0] core_in,   // debug read-out select (from ui_in)
    output wire [7:0] core_dbg   // debug read-out byte (to uo_out)
);

  // ---- result_src encodings (must match cleave_control) ----
  localparam [1:0] RES_ALU = 2'b00,
                   RES_MEM = 2'b01,
                   RES_PC4 = 2'b10,
                   RES_IMM = 2'b11;

  // ==========================================================================
  // Fetch
  // ==========================================================================
  wire [31:0] pc;
  wire [31:0] pc_next;
  wire [31:0] instr;

  cleave_pc u_pc (
      .clk(clk), .rst(rst), .pc_next(pc_next), .pc(pc)
  );

  cleave_imem u_imem (
      .addr(pc), .instr(instr)
  );

  // ==========================================================================
  // Decode — instruction field extraction
  // ==========================================================================
  wire [6:0] opcode   = instr[6:0];
  wire [4:0] rd       = instr[11:7];
  wire [2:0] funct3   = instr[14:12];
  wire [4:0] rs1a     = instr[19:15];
  wire [4:0] rs2a     = instr[24:20];
  wire       funct7b5 = instr[30];

  // ==========================================================================
  // Control
  // ==========================================================================
  wire       reg_write, alu_src_a, alu_src_b, mem_read, mem_write;
  wire       branch, jump, jalr, illegal_instr;
  wire [1:0] result_src;
  wire [2:0] imm_sel;
  wire [3:0] alu_ctrl;

  cleave_control u_control (
      .opcode(opcode), .funct3(funct3), .funct7b5(funct7b5),
      .reg_write(reg_write), .alu_src_a(alu_src_a), .alu_src_b(alu_src_b),
      .mem_read(mem_read), .mem_write(mem_write),
      .branch(branch), .jump(jump), .jalr(jalr),
      .result_src(result_src), .imm_sel(imm_sel), .alu_ctrl(alu_ctrl),
      .illegal_instr(illegal_instr)
  );

  // ==========================================================================
  // Register file, immediate, ALU
  // ==========================================================================
  wire [31:0] rd1, rd2, imm, dbg_data;
  reg  [31:0] wb_data;                       // writeback value (result_src mux, below)
  wire [4:0]  dbg_rs = core_in[4:0];

  cleave_regfile u_regfile (
      .clk(clk), .we(reg_write),
      .rs1(rs1a), .rs2(rs2a), .rd(rd), .wd(wb_data),
      .rd1(rd1), .rd2(rd2),
      .dbg_rs(dbg_rs), .dbg_data(dbg_data)
  );

  cleave_immgen u_immgen (
      .instr(instr), .imm_sel(imm_sel), .imm(imm)
  );

  wire [31:0] alu_a = alu_src_a ? pc  : rd1; // PC for AUIPC, else rs1
  wire [31:0] alu_b = alu_src_b ? imm : rd2; // immediate, else rs2
  wire [31:0] alu_res;
  wire        alu_zero;                       // unused: branch decisions use u_branch

  cleave_alu u_alu (
      .a(alu_a), .b(alu_b), .alu_ctrl(alu_ctrl),
      .result(alu_res), .zero(alu_zero)
  );

  // ==========================================================================
  // Branch condition + data memory
  // ==========================================================================
  wire take;
  cleave_branch u_branch (
      .rs1(rd1), .rs2(rd2), .funct3(funct3), .take(take)
  );
  wire branch_taken = branch & take;

  wire [31:0] dmem_rdata;
  cleave_dmem u_dmem (                        // load extend + write mask live inside
      .clk(clk), .mem_write(mem_write), .funct3(funct3),
      .addr(alu_res), .wdata(rd2), .rdata(dmem_rdata)
  );

  // ==========================================================================
  // Writeback mux (result_src)
  //   Stores/branches/illegal set result_src = x with reg_write = 0, so wb_data is
  //   never latched there; default -> ALU keeps it defined for clean simulation.
  // ==========================================================================
  wire [31:0] pc_plus4 = pc + 32'd4;

  always @(*) begin
    case (result_src)
      RES_ALU: wb_data = alu_res;
      RES_MEM: wb_data = dmem_rdata;
      RES_PC4: wb_data = pc_plus4;            // JAL / JALR link value
      RES_IMM: wb_data = imm;                 // LUI
      default: wb_data = alu_res;
    endcase
  end

  // ==========================================================================
  // Next-PC mux
  //   JALR target reuses the ALU adder (alu_res == rs1+imm on a JALR); bit0 cleared.
  //   JAL and taken branches go to PC+imm; everything else falls through to PC+4.
  //   jalr implies jump, so it is tested first.
  // ==========================================================================
  wire [31:0] pc_target   = pc + imm;
  wire [31:0] jalr_target = alu_res & ~32'h1;

  assign pc_next = jalr                  ? jalr_target
                 : (jump | branch_taken) ? pc_target
                 :                         pc_plus4;

  // ==========================================================================
  // Observability read-out: byte core_in[6:5] of the selected register -> uo_out
  // ==========================================================================
  reg [7:0] dbg_byte;
  always @(*) begin
    case (core_in[6:5])
      2'b00:   dbg_byte = dbg_data[7:0];
      2'b01:   dbg_byte = dbg_data[15:8];
      2'b10:   dbg_byte = dbg_data[23:16];
      default: dbg_byte = dbg_data[31:24];
    endcase
  end
  assign core_dbg = dbg_byte;

  // ==========================================================================
  // Simulation-only illegal-opcode assertion (stripped from synthesis). There is
  // no trap path in this core; illegal_instr is a debug hook only (option-a).
  // ==========================================================================
`ifdef SIMULATION
  always @(posedge clk)
    if (!rst && illegal_instr)
      $display("ASSERT cleave_core: illegal opcode at pc=%h instr=%h", pc, instr);
`endif

  // Deliberately unused: dmem reads unconditionally (writeback mux selects MEM), so
  // mem_read is not needed; the ALU zero flag is unused (u_branch decides branches);
  // core_in[7] is spare in the read-out encoding.
  wire _unused = &{1'b0, mem_read, alu_zero, core_in[7]};

endmodule

`default_nettype wire
