# Cleave — RV32I Single-Cycle Core on SkyWater 130 nm

**Cleave** is a from-scratch **RV32I** single-cycle processor core, written in Verilog and hardened
all the way to a DRC/LVS-clean **sky130** GDSII through an open-source ASIC flow. It is packaged as a
[TinyTapeout](https://tinytapeout.com/)-style project (`tt_um_cleave`) targeting a single 1×1 tile.

This is a **design-only proof of concept** — a complete RTL-to-GDSII pass on the open SKY130 process.
No fabrication or tapeout submission.

---

## ASIC layout

<!-- ▼▼▼ SCREENSHOT 1 — hardened die / floorplan with dimensions ▼▼▼
     Drop the image in docs/ (e.g. docs/asic-dimensions.png) and update the path below. -->

![Cleave hardened die — dimensions](docs/asic-dimensions.png)

<!-- ▲▲▲ SCREENSHOT 1 ▲▲▲ -->

*Signed-off GDSII: [`cleave/layout/tt_um_cleave.gds`](cleave/layout/tt_um_cleave.gds).*

## Package — QFN32 3D model

<!-- ▼▼▼ SCREENSHOT 2 — 3D render of the QFN32 shell model ▼▼▼
     Render docs/Shell_Model/tt_um_cleave-QFN32.obj and save the shot as e.g. docs/shell-3d.png. -->

![Cleave QFN32 package — 3D model](docs/shell-3d.png)

<!-- ▲▲▲ SCREENSHOT 2 ▲▲▲ -->

*3D model source: [`docs/Shell_Model/`](docs/Shell_Model/) (`.obj` + `.mtl`).*

---

## Architecture

A textbook single-cycle datapath implementing the full **RV32I base integer ISA**:

| Block | Module | What it does |
|-------|--------|--------------|
| Program counter | `cleave_pc` | PC steps by 4; next-PC mux for branches/jumps |
| Instruction memory | `cleave_imem` | On-chip word-addressed ROM |
| Register file | `cleave_regfile` | 32 × 32-bit, `x0` hardwired to 0, dual read + debug read port |
| ALU | `cleave_alu` | ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND |
| Immediate generator | `cleave_immgen` | I / S / B / U / J immediate reassembly |
| Branch comparator | `cleave_branch` | BEQ, BNE, BLT, BGE, BLTU, BGEU |
| Control unit | `cleave_control` | Full-ISA decode → control vector |
| Data memory | `cleave_dmem` | Byte-addressable RAM: SB/SH/SW + LB/LH/LW/LBU/LHU |
| Core integration | `cleave_core` | Fetch → decode → regfile → ALU → memory → writeback, incl. LUI/AUIPC and JAL/JALR |
| TinyTapeout wrapper | `tt_um_cleave` | Maps the core onto the TT I/O; active-low reset → active-high |

The single 8-bit dedicated **input** bus (`ui_in`) feeds the core's control/data input; the 8-bit
dedicated **output** bus (`uo_out`) exposes a core debug/status byte, so a testbench can observe
register state through the pins. See the block/architecture diagrams in [`docs/`](docs/).

## Repository layout

```
cleave-rv32i/
├── README.md
├── docs/                       # Architecture diagrams + QFN32 3D package model
├── cleave/                     # sky130 backend workspace
│   ├── source/                 # RTL fed to the flow
│   ├── config_librelane.json   # LibreLane/OpenLane config (25 MHz target, sky130A)
│   ├── qflow_*.sh              # qflow flow scripts/vars
│   ├── log/                    # per-step sign-off logs (synth / place / route)
│   └── layout/tt_um_cleave.gds # signed-off GDSII
└── ttsky-verilog-template/     # TinyTapeout project (authoritative RTL + tests)
    ├── src/                    # the 10 RV32I source files + info.yaml wrapper config
    ├── test/                   # cocotb bench + self-checking unit benches
    └── synth/                  # standalone Yosys sanity synthesis
```

## Verification

Every module has a persisted, self-checking [Icarus Verilog](http://iverilog.icarus.com/) bench in
`ttsky-verilog-template/test/unit/`, plus a full-core integration "proof" program
(`tb_cleave_proof.v`) that exercises every instruction group — LUI/AUIPC, R/I ALU ops (incl. shifts
and SLT), the SB/SH/SW → LB/LH/LW/LBU/LHU round-trip, each branch condition, and JAL/JALR — and
checks results against hand-computed values via the debug port.

```powershell
# from the repo root (needs iverilog on PATH)
powershell -File ttsky-verilog-template/test/unit/run_unit_tests.ps1
```

The suite currently passes **10/10** (9 module benches + the integration proof). Waveforms can be
inspected in GTKWave.

## Backend flow

RTL is hardened against the open-source **SkyWater sky130A** PDK using an open EDA stack — Yosys for
synthesis, OpenROAD/[LibreLane](https://github.com/librelane/librelane) (with a qflow path also
present) for floorplan, placement, CTS and routing, and Magic / KLayout / netgen for GDS streamout
and DRC/LVS sign-off. Target clock is 40 ns (25 MHz). The resulting layout is in
`cleave/layout/tt_um_cleave.gds`; per-step logs are under `cleave/log/`.

## Try it locally

```bash
git clone <this-repo>
cd cleave-rv32i
# RTL + tests live under ttsky-verilog-template/ (see its README for the cocotb flow);
# the standalone unit benches run with the PowerShell script above.
```

## License

RTL is Apache-2.0 (see the SPDX headers in `ttsky-verilog-template/src/`). Built on the TinyTapeout
Verilog template and the open SkyWater sky130 PDK.
