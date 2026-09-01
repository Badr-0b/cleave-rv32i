# HANDOFF — Cleave RV32I, Step 3 (building the single-cycle core)

**Date:** 2026-08-28
**Scope:** Design-only PoC → DRC/LVS-clean GDSII (no shuttle, no fab). See
`.claude/OBJECTIVE_UPDATE.md`. Active plan:
`.claude/plans/read-c-users-nitro-documents-github-clea-wobbly-comet.md` (has a per-stage
progress log). Supersedes `.claude/plans/cleave-build-plan.md` (old teaching-subset scope).

## 1. Locked decisions (this build)
- **ISA:** full RV32I base integer. FENCE/ECALL/EBREAK decode as NOPs. No CSR, no traps, no
  pipelining, no external bus. On-chip ROM + byte-addressable RAM.
- **Regfile:** full 32×32 (x0 = 0).
- **Backend:** installed **qflow** stack (Yosys, graywolf, qrouter, Magic, netgen, OpenSTA) →
  Magic DRC clean + netgen LVS clean + OpenSTA sign-off. **No OpenLane.** Render via KLayout/GDS3D.
- **Authorship:** collaborative. Assistant drafts mechanical combinational modules; user reviews +
  greenlights each, and has been improving them (see §4). Confirm the split per stage.

## 2. Build order & status
Modules live in `ttsky-verilog-template/src/`. Build stages A–K (see plan for detail):

| Stage | Module(s) | Status |
|-------|-----------|--------|
| A | `cleave_pc.v`, `cleave_imem.v` | ✅ done, sim-verified |
| B | `cleave_regfile.v` | ✅ done, sim-verified |
| C | `cleave_alu.v` | ✅ done, sim-verified |
| D | `cleave_immgen.v` | ✅ done, sim-verified |
| **E** | `cleave_branch.v` | **⏭ NEXT** — branch comparator (6 conditions) |
| F | `cleave_control.v` | pending — main + ALU decode table |
| G | `cleave_dmem.v` | pending — data RAM, sub-word LB/LH/LW/… + SB/SH/SW |
| H | `cleave_core.v` (integrate) | pending — replace stub, wire datapath/muxes |
| I | loads/stores in core | pending |
| J | branches + jumps in core | pending |
| K | observability + wrapper/`info.yaml` refine | pending |

**`cleave_core.v` is still the tied-off stub** until Stage H. `tt_um_cleave.v` wrapper unchanged.

## 3. Key encodings established (must stay consistent when writing control, Stage F)
- **`alu_ctrl` (4 bits, cleave_alu):** `{modifier, funct3}` → for R-type,
  `alu_ctrl = {instr[30], funct3}`. ADD=0000, SUB=1000, SLL=0001, SLT=0010, SLTU=0011, XOR=0100,
  SRL=0101, SRA=1101, OR=0110, AND=0111.
- **`imm_sel` (3 bits, cleave_immgen):** I=000, S=001, B=010, U=011, J=100. Control must always
  drive a valid value (immgen's `default` is `32'bx` don't-care — an illegal sel shows as X in sim).
- **Reset:** wrapper converts TinyTapeout active-low `rst_n` → active-high `rst` for the core.
  `cleave_pc` resets PC to 0.

## 4. User modifications kept (already reviewed/verified)
- `cleave_regfile.v`: `regs[1:31]` (drops dead x0 storage) + `` `ifdef SIMULATION `` zero-init.
  (A write-through/transparent-read attempt was reverted — causes a combinational loop when
  rd==rs1/rs2 in a single-cycle datapath.)
- `cleave_alu.v`: explicit shared adder/subtractor (`a + ~b + is_sub`) + `zero = ~|result`.
- `cleave_immgen.v`: `default: imm = 32'bx` (don't-care, gate-minimizing). A CSR `IMM_Z` breadcrumb
  was removed at user request (out of scope).

## 5. How to verify (env)
- `iverilog`/`vvp` at `C:\msys64\mingw64\bin` — that dir must be on PATH for its DLLs.
- Per-module throwaway self-checking benches are written to the session scratchpad and run as:
  `iverilog -g2012 -o out.vvp <tb>.v src/<module>.v && vvp out.vvp`. Each prints `ALL … CHECKS PASSED`.
- Housekeeping on each module: add to `info.yaml` `source_files:` and `test/Makefile`
  `PROJECT_SOURCES`. Both are currently up to date through Stage D.

## 6. Immediate next step
Stage E: draft `cleave_branch.v` — inputs `rd1`, `rd2`, `funct3`; output `branch_taken` resolving
BEQ/BNE (eq/ne), BLT/BGE (signed), BLTU/BGEU (unsigned). Then Stage F control ties immgen/alu/branch
together via the decode table, and Stage H integrates everything into `cleave_core.v`.

## 7. Definition of done
Working RV32I in sim (proof program exercising every instruction group, ending in `BEQ x0,x0,0`
self-loop, state read via the `ui_in`/`uo_out` debug port) → harden via qflow → Magic DRC clean +
netgen LVS clean + OpenSTA timing pass → optional KLayout/GDS3D render.
