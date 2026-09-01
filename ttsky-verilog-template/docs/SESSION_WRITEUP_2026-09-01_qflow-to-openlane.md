# Cleave RV32I — Backend Session Writeup (qflow → OpenLane), 2026-09-01

**Full, unabridged record of one backend session:** every step, every fix, every dead-end, and
the final signed-off result. Written for the future maintainer (likely you) so nothing has to be
re-derived. This supersedes the interim repo-root `HANDOFF_QFLOW_SESSION.md`.

---

## 0. Executive summary

**Goal:** harden `tt_um_cleave` (the Cleave RV32I single-cycle core) to a **DRC-clean +
LVS-clean sky130 GDSII**, running the open-source backend under WSL2 on a Windows 11 laptop.

**Outcome: achieved — a clean GDSII exists.** It was *not* produced by qflow (which is where the
session started and where most of the pain was); qflow got the design through synthesis and
placement but its router, `qrouter`, could not converge on this design's congestion after
multiple hours and two density settings. We pivoted to **OpenROAD via LibreLane (OpenLane 2)**,
which completed the entire flow — synthesis through signoff — in ~45 minutes and produced a fully
DRC/LVS-clean GDS.

**The one-line arc:** qflow blocked by a technology-path bug → fixed the sky130 wiring → qflow
synthesis + placement succeeded → qflow routing hit a congestion wall (twice) → pivoted to
OpenLane/OpenROAD → clean GDSII.

### Headline result (OpenLane run `RUN_2026-09-01_13-22-07`)

| Metric | Value |
|---|---|
| **magic DRC errors** | **0** ✅ |
| **KLayout DRC errors** | **0** ✅ |
| **routing DRC errors** | **0** ✅ |
| **netgen LVS** | **0 errors, 0 device/net/pin differences** ✅ (layout matches netlist) |
| **Final GDS** | `tt_um_cleave.gds`, 34.7 MB ✅ |
| Die size | 647.04 × 657.76 µm (≈ 0.425 mm²) |
| Standard cells | 24,338 (75,436 total instances incl. fill/tap/decap) |
| Sequential cells (flops) | 3,102 |
| Std-cell utilization | 57.0 % |
| Antenna violations | 0 (46 antenna diodes inserted) |
| Power-grid violations | 0 (worst IR drop ≈ 0.34 mV) |
| Estimated power | ≈ 16.55 mW |
| **Hold timing** | **0 violations, all corners** ✅ |
| **Setup timing @ 40 ns** | 2,765 violations — **all in the slow `ss_100C_1v60` corner**; typical (`tt`) and fast (`ff`) corners are clean |

**Deliverable status:** the objective (`.claude/OBJECTIVE_UPDATE.md`) defines "done" as a
DRC-clean + LVS-clean GDSII, with timing explicitly optional. **That milestone is met.** The
design does not close *setup* timing at 25 MHz in the worst-case corner — expected for a
single-cycle core with flop-based memory — but that does not affect the DRC/LVS-clean-GDS
deliverable.

---

## 1. Session metadata & environment

| Item | Value |
|---|---|
| Date | 2026-09-01 (ran roughly 02:30–17:00 local, with an overnight gap) |
| Host CPU | 13th Gen Intel Core **i9-13900H** — 14 cores / 20 threads |
| Host RAM | 16 GB (15.7 GB reported) |
| GPU | NVIDIA RTX 5050 (not usable by any tool here — see §8) |
| OS | Windows 11 Pro 26200; backend under **WSL2, Ubuntu 24.04.4 LTS** |
| WSL resources | 20 vCPUs (full), ~7.6 GB RAM (WSL2 default ≈ 50 % of host) |
| Working dirs | Windows `C:\Users\Nitro\...` ↔ WSL `/mnt/c/Users/Nitro/...` |

**Scope / deliverable:** design-only proof of concept. A DRC-clean + LVS-clean sky130 GDSII of
the Cleave RV32I core; optional KLayout/GDS3D render for a portfolio. No fabrication, no
TinyTapeout shuttle submission. Timing sign-off is a nice-to-have, not the definition of done.

---

## 2. The design under test

- **Codename:** Cleave. **Wrapper (backend top):** `tt_um_cleave`. **Core:** `cleave_core`.
- **ISA:** RV32I, **single-cycle** (one instruction fetched, decoded, executed, retired per clock).
- **Source of truth:** the GitHub repo `C:\Users\Nitro\Documents\GitHub\cleave-rv32i`, RTL under
  `ttsky-verilog-template/src/`. Ten Verilog files:
  `tt_um_cleave, cleave_core, cleave_pc, cleave_imem, cleave_regfile, cleave_alu, cleave_immgen,
  cleave_branch, cleave_control, cleave_dmem`. (`config.json`/`project.v` are not RTL for this macro.)
- **A trap caught early:** `src/tt_um_cleave.v`'s header comment calls it a "SKELETON / stub core."
  That comment is **stale** — the instantiation (`.clk / .rst / .core_in / .core_dbg`) exactly
  matches the *full* `cleave_core` interface, and `PROJECT_STAGES.md` confirms Phase-1 RTL is
  complete (10/10 sim tests). So the wrapper is correct; only its comment lied. Verified by reading
  `cleave_core.v`'s real port list before trusting it.
- **Why this design is heavy for P&R:** the on-chip memories are built from **flip-flops, not
  macros** — a 64×32 data RAM (2,048 flops) + a 32×32 register file (992 flops) + PC/misc = **3,102
  flops**. The read paths around them are wide combinational mux trees. qflow's synthesis mapped the
  whole thing to **22,636 standard cells**; OpenLane's mapping landed at 24,338 std cells. The large
  mux fan-in is what creates local routing hotspots that defeated qrouter.

---

## 3. Act 1 — the original qflow error

The session opened with the qflow GUI (`qflow_manager.py`) throwing:

```
FileNotFoundError: [Errno 2] No such file or directory:
'/mnt/c/Users/Nitro/Desktop/ASIC/qflow/tech/osu035/sky130_fd_sc_hd.sh'
```

**Root cause — a technology mismatch.** qflow builds its technology-setup path as
`<techdir>/<selected-PDK>.sh` (`/usr/local/share/qflow/scripts/qflow_manager.py:3427` and `:3463`,
`pdkscript = pdkdir + '/' + self.pdknode.get() + '.sh'`). The project's saved `qflow_vars.sh` had
`techdir = .../tech/osu035` (from an earlier osu035 setup), but the GUI's **Technology dropdown was
set to `sky130_fd_sc_hd`**. qflow glued the osu035 directory to the sky130 script name → a file
that cannot exist (the osu035 dir only ships `osu035.sh`).

This was a scratch project directory (`ASIC/qflow/`, module `cleave_pc` — a *submodule*, not the
real top). It was used only to diagnose and fix the sky130 wiring; the real work later moved to
`Projects/cleave/`.

---

## 4. Act 2 — wiring qflow to sky130

### 4.1 The PDK hunt

The runbook (`docs/qflow-sky130-runbook.md`) pointed at
`ASIC/PDK/open_pdks/sky130/sky130A/libs.tech/qflow` — but that build is **incomplete**: its
`gds/` held only a placeholder `sources.txt`, and `mag/`/`maglef/` held only `generate_magic.tcl`.
The LEF, Liberty, and magic techfile were present, but the **standard-cell GDS and mag/maglef
abstract views were missing** — so synthesis/place/route could run, but layout migration and final
GDS would fail. Unusable for a full flow.

Searching the machine turned up **two complete, prebuilt sky130A PDKs**:

- **ciel** — `~/.ciel/ciel/sky130/versions/7b70722e33c03fcb5dabcf4d479fb0822d9251c9/sky130A`
- **volare** — `~/.volare/volare/sky130/versions/c6d73a35f524070e85faff4a6a9eef49553ebc2b/sky130A`

Both had the real 4.2 MB cell GDS, ~446 mag/maglef views, the magic techfile, and the qflow tech
scripts. **volare was chosen** as canonical because `~/.bashrc` already set `PDK_ROOT=$HOME/.volare`
and volare had an *enabled* `~/.volare/sky130A` symlink.

### 4.2 The baked-path problem, and the symlink shim (the load-bearing fix)

The prebuilt qflow `.sh` and magic `.magicrc` in these PDKs hardcode a **build-machine path** that
does not exist on this laptop:

```
${HOME}/work/open_pdks/open_pdks/root/volare/sky130/build/c6d73a35…/sky130A/…
```

Rather than edit files inside a package-managed PDK, one **symlink** was created so that entire
prefix resolves to the real install — fixing qflow's `.sh` and magic's `.magicrc` fallback at once
(both use the identical prefix; the magic techfile and `.par` contain no baked paths):

```bash
mkdir -p ~/work/open_pdks/open_pdks/root/volare/sky130/build
ln -sfn ~/.volare/volare/sky130/versions/c6d73a35f524070e85faff4a6a9eef49553ebc2b \
        ~/work/open_pdks/open_pdks/root/volare/sky130/build/c6d73a35f524070e85faff4a6a9eef49553ebc2b
```

> If qflow/magic ever complains about a missing `~/work/open_pdks/...` path, recreate this symlink.

### 4.3 The headless-graphics fix

graywolf (and qrouter) try to open an X graphics window whenever `DISPLAY` is set. Under WSLg
(`DISPLAY=:0`) they die on a missing bitmap font — `ERROR[TWgetfont]: font:9x15 not available`
— and the process is SIGTERM'd, which qflow reports as **"exited with status -15 / Errors
encountered."** The placement itself actually succeeds; only the optional graphics view crashes.
Two independent guards were applied:

- All CLI runs use `unset DISPLAY` (graywolf then auto-selects `-n`, no graphics).
- `project_vars.sh` sets `graywolf_options = "-n"`, and `TWSC*no.graphics : on` is set in the
  `.par` — the exact setting the GUI's **"Placement graphic view"** checkbox controls (uncheck it
  in the GUI, or it re-enables graphics on the next Run).

Verified end-to-end on the scratch `cleave_pc` submodule: synthesis + placement passed headlessly.

---

## 5. Act 3 — making the setup durable

- **Standardized on volare** (matching the existing `PDK_ROOT`). Added `export PDK=sky130A` to
  `~/.bashrc` (`PDK_ROOT=$HOME/.volare` was already there and is correct).
- **Removed the ciel shim** to keep a single source of truth; kept only the volare shim.
- **Deleted a dangling `source/top.v`** symlink (pointed at a missing EE270 file) that was spraying
  `cat: .../top.v: No such file or directory` noise and could confuse qflow's auto module detection.
- **Deliberately did NOT set `QFLOW_TECH`/`QFLOW_TECH_DIR` globally** — that would override the
  sibling `EE270_PD` project, which legitimately uses **osu018**. Per-project `qflow_vars.sh` is the
  correct tech selector; `checkdirs.sh` (CLI) does not scan `PDK_ROOT`, only the GUI does.

---

## 6. Act 4 — the real tt_um_cleave run in qflow

### 6.1 Staging

Project at `C:\Users\Nitro\Desktop\ASIC\Projects\cleave` (`source/ synthesis/ layout/ log/`). The
stale 972-line monolith in `source/` was replaced with the **10 authoritative repo files**.
`qflow_vars.sh` set `techdir=~/.volare/sky130A/libs.tech/qflow`, `techname=sky130_fd_sc_hd`, with
`source/synthesis/layout/log` all under the project. `project_vars.sh`: `graywolf_options=-n`,
`initial_density=0.40`, `sta_tool=opensta`. The tech resolved to real LEF/GDS/Liberty via the shim.

### 6.2 Synthesis — ✅ success

`qflow synthesize tt_um_cleave` (yosys 0.33) mapped to sky130_fd_sc_hd cleanly: **22,636 cells,
3,072 dfxtp flops, no inferred latches.** (Buffers were only ~2,235 of the total — the bulk is
genuine logic + flops, not bloat.)

### 6.3 Placement — ✅ success, but slow

graywolf (TimberWolf simulated annealing) placed all cells and wrote a DEF — but took **~62 min at
density 0.40**, and later **~75 min at 0.30**. graywolf is single-threaded and scales poorly at
~22 k cells. A useful lesson surfaced here: the visible `graywolf` process sits in `do_wait`; the
actual worker is `TimberWolfSC`. Checking only the wrapper made it *look* hung (0 % CPU) when
`TimberWolfSC` was in fact at 100 % CPU the whole time — **always check CPU on the worker, and note
that graywolf writes its `.def` only at the end, so mid-run file timestamps stay stale.**

### 6.4 An overnight WSL-sleep kill

The first routing run was launched in the background overnight. The **laptop slept, which restarts
the WSL2 VM** — that killed the background job *and* wiped `/tmp` (where the first run's log lived).
Durable artifacts on `/mnt/c` survived. Lesson: **long background jobs die when the laptop sleeps;
log to `/mnt/c`, not `/tmp`, and keep the machine awake.**

### 6.5 Routing — ❌ the wall (twice)

`qrouter` (single-threaded maze router) never converged:

- **At density 0.40:** after the initial pass it entered stage-2 rip-up-and-reroute and stuck at
  **~4,900–5,100 "Failed net routes"**, improving only ~6 nets per multi-minute pass. Extrapolated
  to *hundreds* of passes — effectively never. Congestion-bound, not slow.
- **At density 0.30** (bigger die, more routing area): re-placement took ~75 min, then routing again
  stalled at a similarly high failed-net count.

This is the fundamental limitation: **qflow's graywolf/qrouter are near their practical ceiling at
~22 k cells with wide mux hotspots.** The design is genuinely OpenROAD-sized.

### 6.6 Decision: pivot

With routing not converging after multiple hours and two densities, we archived the qflow progress
and pivoted to OpenROAD/OpenLane.

---

## 7. Act 5 — the pivot to OpenROAD / LibreLane

### 7.1 Archiving qflow's work

Everything qflow produced was packed into
`Projects/cleave/archive_qflow_2026-09-01.tar.gz` (2.1 MB): the mapped netlist, SDC, placement
`.def`, all logs, and the setup files, with a README. **OpenLane cannot "resume" from qflow's
placement** (incompatible intermediate formats) — it re-runs from RTL — so the archive is a record
+ netlist cross-check, not an input.

### 7.2 Docker — two hurdles

OpenLane needs a tool environment; the chosen path was LibreLane's dockerized mode.

1. **Docker daemon wasn't running.** Docker Desktop was installed but off; it was launched from
   Windows (`Start-Process "Docker Desktop.exe"`).
2. **WSL integration was disabled.** The daemon came up on the Windows side, but `docker` inside
   Ubuntu couldn't reach it — `settings-store.json` had no integrated distros. Fixed by editing
   `%APPDATA%\Docker\settings-store.json` (`enableIntegrationWithDefaultWslDistro=true`,
   `integratedWslDistros=["Ubuntu"]`, `enableIntegrationWithWslDistros=true`) and restarting Docker
   Desktop. After that, `docker` worked in WSL (client/server 29.7.2, integration OK).

### 7.3 LibreLane install + config

Installed **LibreLane v3.0.11** in a Python venv (`~/ll-venv`, `pip install librelane`). Wrote a
minimal, robust config (`Projects/cleave/config_librelane.json`):

```json
{
  "DESIGN_NAME": "tt_um_cleave",
  "VERILOG_FILES": "dir::source/*.v",
  "CLOCK_PORT": "clk",
  "CLOCK_PERIOD": 40,
  "FP_SIZING": "relative",
  "FP_CORE_UTIL": 40,
  "PL_TARGET_DENSITY_PCT": 45,
  "GRT_ALLOW_CONGESTION": true,
  "RUN_LINTER": false,
  "PDK": "sky130A"
}
```

### 7.4 The TTY flag-order bug

First dockerized launch failed instantly: `cannot attach stdin to a TTY-enabled container because
stdin is not a terminal`. LibreLane's `--dockerized` allocates a TTY by default, which a background
shell doesn't have. The fix was **flag order** — `--docker-no-tty` must come **before**
`--dockerized` ("has no effect if set after"):

```bash
librelane --docker-no-tty --dockerized ./config_librelane.json
```

### 7.5 The clean run

Second launch worked. Sequence: pulled `ghcr.io/librelane/librelane:3.0.11` (multi-GB, one-time),
fetched the LibreLane-pinned sky130 PDK inside the container, then ran the full OpenROAD flow —
synthesis → floorplan → PDN → I/O placement → global placement → detailed placement → **CTS** →
global route → antenna repair → **detailed route (TritonRoute, multithreaded across all 20 cores)**
→ fill → parasitic extraction → multi-corner STA → **magic + KLayout DRC** → **netgen LVS** → GDS.
**Total ≈ 45 minutes**, peak container memory **under 1 GB** (the earlier OOM worry was unfounded).
`LIBRELANE_EXIT=0`.

---

## 8. Can more hardware help? (asked during the session)

- **GPU (RTX 5050): no.** Neither qflow nor OpenROAD uses the GPU; there is no CUDA path in the
  mainline open-source flow. The GPU stays idle regardless.
- **CPU multicore:** this is the real difference. **qflow's graywolf and qrouter are
  single-threaded** — the i9's other cores cannot be handed that work, and there is no flag to
  change it. **OpenROAD multi-threads** the heavy steps (global/detailed routing, placement
  optimization) and auto-used all **20 threads** here. That parallelism, plus a smarter router, is
  why OpenROAD cleared the congestion qrouter couldn't.
- **RAM:** the actual scarce resource on this 16 GB laptop (WSL gets ~7.6 GB; Windows was near
  full). It turned out not to bind — the OpenLane run peaked under 1 GB. You cannot "make a tool use
  more RAM" to go faster; memory is demand-driven and headroom is just OOM safety margin. The only
  memory/speed lever is thread count, which OpenROAD was already maxing.

---

## 9. Results in detail (OpenLane `RUN_2026-09-01_13-22-07`)

### Physical / signoff

| Category | Value |
|---|---|
| Die bbox | 0,0 → 647.04, 657.76 µm; die area 425,597 µm²; core area 402,894 µm² |
| Std-cell utilization | 57.0 % |
| magic DRC / KLayout DRC / route DRC | 0 / 0 / 0 |
| LVS | 0 errors; 0 unmatched devices/nets/pins; 0 device/net differences; 0 property fails |
| Antenna | 0 violating nets, 0 violating pins; 46 antenna diodes inserted |
| Power-grid | 0 violations; worst IR drop ≈ 0.34 mV; VPWR ≈ 1.7997 V |
| Power (est.) | 16.55 mW total (internal 9.09 mW, switching 7.46 mW, leakage ≈ 0.4 µW) |
| Global-route wirelength | 1,136,464 units; detailed-route 829,432; converged over 8 iterations |
| Disconnected pins | 10 total, **0 critical** (the unused `ena` / `uio_in` inputs the wrapper ties off) |

### Instance breakdown (75,436 total)

| Class | Count |
|---|---|
| Standard cells (logic) | 24,338 |
| Sequential (flops) | 3,102 |
| Multi-input combinational | 9,119 |
| Timing-repair buffers | 5,563 |
| Hold buffers | 3,041 |
| Clock buffers / inverters | 568 / 31 |
| Tap cells | 5,757 |
| Fill cells | 51,098 |
| Antenna cells | 96 |

### Timing (clk = 40 ns / 25 MHz), across 6 corners

| | Result |
|---|---|
| **Hold** | **0 violations** in every corner (WNS/TNS = 0). ✅ |
| **Setup** | 2,765 violations — **entirely in the `ss_100C_1v60` slow corner** (max/nom/min ss = 1,136 / 935 / 694). **`tt` and `ff` corners: 0 setup violations.** |
| Setup WNS (worst) | −5.98 ns (ss corner) |
| Electrical DRC | max-slew 5,342, max-cap 55, max-fanout 66 — predominantly in the ss corner |

**Interpretation:** the design meets setup at the typical and fast corners at 25 MHz and has zero
hold problems anywhere; it only misses setup in the worst-case slow corner. For a functional PoC
that is entirely acceptable and does not affect the DRC/LVS-clean deliverable. A single-cycle RV32I
with flop-based memory inherently has a long combinational path (fetch → regfile → ALU → dmem →
writeback in one cycle); closing it in *all* corners would need a slower clock (~80–150 ns) or
pipelining.

---

## 10. Every failure & gotcha (consolidated)

| # | Symptom | Root cause | Fix |
|---|---|---|---|
| 1 | `FileNotFoundError .../tech/osu035/sky130_fd_sc_hd.sh` | qflow builds `<techdir>/<pdknode>.sh`; project techdir was osu035 but dropdown was sky130 | Point project at sky130 (correct `qflow_vars.sh`) |
| 2 | sky130 layout steps would fail | `ASIC/PDK/open_pdks` sky130A build incomplete (no cell GDS / mag / maglef) | Use complete prebuilt volare (or ciel) sky130A instead |
| 3 | qflow/magic can't find `${HOME}/work/open_pdks/...` files | volare/ciel bake CI build paths into their qflow `.sh` and magic `.magicrc` | One symlink recreating that prefix → real install (§4.2) |
| 4 | Placement "exited with status -15 / errors" | graywolf opened X graphics under WSLg, missing `9x15` font, SIGTERM'd | `unset DISPLAY` + `graywolf_options=-n` + `.par` `no.graphics:on`; uncheck GUI "graphic view" |
| 5 | Shell vars/loops silently empty in `wsl.exe -- bash -lc '…'` | outer Git-Bash mangles `$var`/`$(...)` before reaching WSL | Put logic in a script file and run `wsl.exe -- bash -lc "bash /mnt/c/.../x.sh"` |
| 6 | Overnight routing job vanished; its `/tmp` log gone | laptop slept → WSL2 VM restarted → killed bg jobs + wiped `/tmp` | Log to `/mnt/c`; keep laptop awake for long runs |
| 7 | graywolf *looked* hung (0 % CPU) | watched the `do_wait` wrapper, not the `TimberWolfSC` worker | Check CPU on the worker; graywolf writes `.def` only at the end |
| 8 | **qrouter never converged** (~4,900 stuck nets @0.40 and @0.30) | design too congested for single-threaded qrouter at ~22 k cells | **Pivot to OpenROAD/OpenLane** |
| 9 | `docker` unavailable in WSL | Docker Desktop daemon off, then WSL integration disabled | Launch Docker Desktop; enable Ubuntu WSL integration in `settings-store.json`; restart |
| 10 | LibreLane: `cannot attach stdin to a TTY-enabled container` | `--docker-no-tty` placed *after* `--dockerized` (ignored) | Put `--docker-no-tty` **before** `--dockerized` |
| 11 | 2,765 setup violations @40 ns | single-cycle long path fails setup in the ss slow corner | Optional: loosen clock (~80–150 ns) or pipeline; not required for the deliverable |

---

## 11. Final machine state (what's installed/configured now)

- **PDK:** volare sky130A `c6d73a35…` at `~/.volare/sky130A`; the resolving shim at
  `~/work/open_pdks/open_pdks/root/volare/sky130/build/c6d73a35…`. ciel copy still exists but is
  unused (its shim was removed).
- **Shell:** `~/.bashrc` has `export PDK_ROOT=$HOME/.volare` and `export PDK=sky130A`.
- **Docker Desktop:** WSL integration enabled for Ubuntu (v29.7.2).
- **LibreLane:** v3.0.11 in venv `~/ll-venv`; tool image `ghcr.io/librelane/librelane:3.0.11`
  pulled; LibreLane-pinned sky130 PDK cached in-container.
- **qflow:** 1.4.104, wired to volare sky130 and headless — kept as-is (superseded for this design).
- **OpenSTA:** cloned to `~/OpenSTA` but **never built** (needs `sudo apt install swig
  libeigen3-dev` then cmake) — now moot, since OpenLane runs OpenSTA internally.

### Where everything lives

| Artifact | Path |
|---|---|
| **Final GDS** | `Projects\cleave\layout\tt_um_cleave.gds` (copy) and `…\runs\RUN_2026-09-01_13-22-07\final\gds\tt_um_cleave.gds` |
| Final DEF | `…\runs\RUN_2026-09-01_13-22-07\final\def\tt_um_cleave.def` |
| Full OpenLane run (all steps, logs, metrics) | `Projects\cleave\runs\RUN_2026-09-01_13-22-07\` |
| LibreLane config | `Projects\cleave\config_librelane.json` |
| LibreLane run log | `Projects\cleave\log_librelane_run.txt` |
| qflow archive | `Projects\cleave\archive_qflow_2026-09-01.tar.gz` |
| qflow setup/logs | `Projects\cleave\qflow_vars.sh`, `project_vars.sh`, `log\`, `synthesis\` |
| Interim handoff (superseded) | repo root `HANDOFF_QFLOW_SESSION.md` |
| **This document** | `ttsky-verilog-template\docs\SESSION_WRITEUP_2026-09-01_qflow-to-openlane.md` |

---

## 12. How to reproduce / re-run

All in WSL. `PDK_ROOT`/`PDK` come from `~/.bashrc`.

**Re-run the OpenLane flow (the working path):**
```bash
source ~/ll-venv/bin/activate
cd /mnt/c/Users/Nitro/Desktop/ASIC/Projects/cleave
librelane --docker-no-tty --dockerized ./config_librelane.json
# result: runs/RUN_*/final/gds/tt_um_cleave.gds
```

**Timing-closure experiment (optional):** copy `config_librelane.json`, bump `"CLOCK_PERIOD"` to
e.g. `100`, re-run; check `runs/RUN_*/**/metrics.json` for `timing__setup_vio__count` → 0.

**View the GDS:** double-click `Projects\cleave\layout\tt_um_cleave.gds` in Explorer (KLayout
0.30 installed), or `klayout .../layout/tt_um_cleave.gds` in WSL; or load in GDS3D for a 2.5D view.

**qflow (for the record, not recommended for this design):** `cd Projects/cleave; unset DISPLAY;
qflow synthesize place tt_um_cleave` works; `qflow route` will not converge (§6.5).

---

## 13. Open items & recommendations

- **Timing closure (optional):** to pass setup in *all* corners, loosen the clock (~80–150 ns) or
  pipeline the core (split fetch/decode/execute/mem/writeback). Not needed for the DRC/LVS goal.
- **Electrical DRC:** the max-slew/max-cap warnings are almost all in the slow corner and track the
  setup story; they clear with a looser clock or targeted buffering.
- **Portfolio render:** load the GDS in KLayout (2.5D) and/or GDS3D and screenshot; pair with the
  signoff numbers in §9.
- **qflow:** documented dead-end for a ~22 k-cell block — keep OpenLane as the backend for Cleave.
- **OpenSTA:** no longer needed as a standalone (OpenLane runs multi-corner STA internally); the
  `~/OpenSTA` clone can be deleted.

---

## 14. Appendix

### Tool versions
qflow 1.4.104 · yosys 0.33 (2584903) · magic 8.3.620 · netgen · qrouter 1.4.90 · graywolf ·
Docker 29.7.2 · LibreLane v3.0.11 · OpenROAD/yosys/magic/netgen/KLayout inside the LibreLane image ·
KLayout 0.30 (host).

### Key files (verbatim)

`Projects/cleave/qflow_vars.sh`:
```tcsh
#!/bin/tcsh -f
set projectpath=/mnt/c/Users/Nitro/Desktop/ASIC/Projects/cleave
set techdir=/home/nitro/.volare/sky130A/libs.tech/qflow
set techname=sky130_fd_sc_hd
set sourcedir=$projectpath/source
set synthdir=$projectpath/synthesis
set layoutdir=$projectpath/layout
set logdir=$projectpath/log
```

`Projects/cleave/project_vars.sh`:
```tcsh
#!/bin/tcsh -f
set graywolf_options = "-n"
set initial_density = 0.30
set sta_tool = opensta
```

The volare shim (recreate if broken):
```bash
mkdir -p ~/work/open_pdks/open_pdks/root/volare/sky130/build
ln -sfn ~/.volare/volare/sky130/versions/c6d73a35f524070e85faff4a6a9eef49553ebc2b \
        ~/work/open_pdks/open_pdks/root/volare/sky130/build/c6d73a35f524070e85faff4a6a9eef49553ebc2b
```

### Glossary
- **PDK** — Process Design Kit (sky130 = SkyWater 130 nm open PDK; `sky130_fd_sc_hd` = the
  high-density standard-cell library).
- **LEF / DEF / GDS** — abstract cell/tech geometry / placement+route exchange format / final
  mask-layout database (the tape-out artifact).
- **DRC / LVS** — Design-Rule Check (geometry legal?) / Layout-vs-Schematic (does the drawn layout
  match the netlist?). Both clean = the deliverable.
- **STA / WNS / TNS** — Static Timing Analysis / Worst & Total Negative Slack.
- **CTS** — Clock-Tree Synthesis (balances clock delay to all flops).
- **Corner** — a (process, voltage, temperature) condition: `ff`=fast, `tt`=typical, `ss`=slow.
- **Utilization** — fraction of core area occupied by standard cells.
- **Antenna / tap / decap / fill** — auxiliary cells inserted during P&R for manufacturability,
  well-tie, decoupling, and density.

---

*End of writeup. The signed-off GDSII lives at
`C:\Users\Nitro\Desktop\ASIC\Projects\cleave\layout\tt_um_cleave.gds`.*
