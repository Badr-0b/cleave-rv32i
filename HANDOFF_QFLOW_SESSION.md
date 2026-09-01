# Cleave RV32I — qflow Backend Session Handoff

**Session date:** 2026-09-01 (overnight, ~02:30–13:00 local)
**Author:** Claude Code (Opus 4.8), unattended run while the user slept
**Goal:** Harden `tt_um_cleave` to a **DRC-clean + LVS-clean sky130 GDSII** via the qflow stack
under WSL2, with all outputs in `C:\Users\Nitro\Desktop\ASIC\Projects\cleave`.

---

## 0. TL;DR — where things stand

| Stage | Status | Artifact |
|-------|--------|----------|
| Environment / PDK wiring | ✅ done | volare sky130A + symlink shim (see §2) |
| Project staged | ✅ done | `Projects/cleave/` with 10 repo source files |
| **Synthesis** | ✅ done | `synthesis/tt_um_cleave.v` — 22,636 cells / 3,072 flops, **no latches** |
| **Placement** | ✅ done | `layout/tt_um_cleave.def` (placed, ~62 min via graywolf) |
| **Routing** | 🔄 in progress / retried | first attempt killed by a WSL restart at 10:20; **restarted ~12:54** |
| Migrate / DRC / GDS / LVS | ⏳ pending | auto-run after routing (chained) → `layout/tt_um_cleave.gds` |
| STA (OpenSTA) | ⛔ blocked | OpenSTA cloned but **not built** — needs a `sudo apt` (see §5) |

**There is no GDS yet.** It only appears after routing → migrate → gdsii succeed. Routing is the
long pole (22.6k cells) and the first run died when the laptop slept (WSL VM restarted, killing
the background job and wiping `/tmp`). A retry is running now, logging to a **persistent** file on
the C: drive so a second sleep won't lose the log.

---

## 1. The design (from the repo — source of truth)

- Repo: `C:\Users\Nitro\Documents\GitHub\cleave-rv32i` → `ttsky-verilog-template/`
- **Top module = `tt_um_cleave`** (TinyTapeout wrapper around the full `cleave_core`).
  - NB: the wrapper's header comment says "stub/skeleton" — that comment is **stale**. Its port
    map (`.clk/.rst/.core_in/.core_dbg`) matches the real full `cleave_core`. The design is
    complete (Phase 1 A–K done, 10/10 sim tests per `PROJECT_STAGES.md`).
- **10 source files** (`ttsky-verilog-template/src/`): `tt_um_cleave, cleave_core, cleave_pc,
  cleave_imem, cleave_regfile, cleave_alu, cleave_immgen, cleave_branch, cleave_control,
  cleave_dmem`. (`config.json`/`project.v` are NOT RTL — excluded.)
- **Why it's big:** on-chip 64×32 data RAM (2,048 flops) + 32×32 regfile (992 flops) + PC = 3,072
  flops, built from flip-flops (not macros); their read muxes are large combinational trees. qflow
  mapped it to **22,636 cells** (≈2.4× the 9.4k the runbook estimated from a standalone yosys run;
  the gap is qflow's fanout buffering + `ff_n40C_1v95` corner + less area-oriented mapping — only
  ~2,200 of the cells are buffers, so the rest is genuine logic+flops).

Deliverable definition (`.claude/OBJECTIVE_UPDATE.md`): DRC-clean + LVS-clean GDSII. Design-only
proof of concept — **no fabrication, no TinyTapeout submission.** STA is a nice-to-have.

---

## 2. Environment & PDK wiring (critical — this is what makes qflow work here)

qflow, magic, netgen, qrouter, graywolf are Linux builds under **WSL2 (Ubuntu 24.04)**. Windows
paths map to `/mnt/c/...`.

- **Canonical PDK = volare sky130A**, commit `c6d73a35f524070e85faff4a6a9eef49553ebc2b`, enabled at
  `~/.volare/sky130A` → `~/.volare/volare/sky130/versions/c6d73a35…/sky130A`. It is **complete**
  (cell GDS + 446 mag/maglef views + qflow tech scripts).
  - Do **NOT** use `ASIC/PDK/open_pdks/sky130/sky130A` (incomplete — no GDS/mag) or
    `/usr/local/share/pdk/sky130A` (stub). The runbook names the incomplete one; we corrected it.
- **The symlink shim (load-bearing):** volare's prebuilt qflow `.sh` and magic `.magicrc` hardcode
  a build-machine prefix `~/work/open_pdks/open_pdks/root/volare/sky130/build/c6d73a35…/`. A symlink
  makes it resolve to the real install (fixes qflow + magic at once):
  ```
  ~/work/open_pdks/open_pdks/root/volare/sky130/build/c6d73a35f524070e85faff4a6a9eef49553ebc2b
      -> ~/.volare/volare/sky130/versions/c6d73a35f524070e85faff4a6a9eef49553ebc2b
  ```
  **If qflow ever complains about missing `~/work/open_pdks/...` paths, recreate that symlink.**
- **Shell env** (`~/.bashrc`): `export PDK_ROOT=$HOME/.volare` and `export PDK=sky130A`.
- **Headless graphics:** graywolf/qrouter open an X window whenever `DISPLAY` is set (WSLg = `:0`)
  and it crashes on a missing `9x15` font (the `-15`/SIGTERM you saw in the GUI). All CLI runs use
  `unset DISPLAY`; `project_vars.sh` also sets `graywolf_options = "-n"`. In the **GUI**, uncheck
  "Placement graphic view" and "Show graphic view" before Run.

Original bug that started all this: the GUI built `<techdir>/<pdknode>.sh` from a mismatched
osu035 techdir + sky130 dropdown → `FileNotFoundError .../tech/osu035/sky130_fd_sc_hd.sh`. Fixed by
pointing the project at sky130 (`qflow_manager.py:3427/3463`).

---

## 3. Project layout (`C:\Users\Nitro\Desktop\ASIC\Projects\cleave`)

```
Projects/cleave/
├── qflow_vars.sh      # techdir=~/.volare/sky130A/libs.tech/qflow, techname=sky130_fd_sc_hd
├── project_vars.sh    # graywolf_options=-n, initial_density=0.40, sta_tool=opensta
├── source/            # the 10 authoritative .v files (copied from repo src/)
├── synthesis/         # tt_um_cleave.v (mapped netlist), tt_um_cleave.sdc (clk @ 40ns)
├── layout/            # tt_um_cleave.def (placed); *_route.def + tt_um_cleave.gds appear after route/gds
└── log/               # per-step logs + session_route_chain.log (the retry's persistent log)
```
Everything is on the C: drive → directly visible from Windows Explorer.

**Superseded:** the earlier messy project at `ASIC/qflow/` (module `cleave_pc`, a *submodule* only)
was a scratch run — ignore it. The real work is here in `Projects/cleave/` on `tt_um_cleave`.

---

## 4. How to resume / finish the GDS

All commands run in a WSL shell. `PDK_ROOT`/`PDK` come from `~/.bashrc`; always `unset DISPLAY`.

### Check whether the overnight retry finished
```bash
tail -40 /mnt/c/Users/Nitro/Desktop/ASIC/Projects/cleave/log/session_route_chain.log
ls -l   /mnt/c/Users/Nitro/Desktop/ASIC/Projects/cleave/layout/tt_um_cleave.gds   # exists ⇒ done
```
Look for `ROUTE_EXIT=0`, then `gdsii_EXIT=0`, and a `tt_um_cleave.gds`.

### If routing is still running
```bash
ps -eo etime,comm | grep qrouter        # is it alive?
```
Let it finish — the chain auto-continues into migrate→drc→gdsii→lvs.

### If routing was killed again (laptop slept) — restart the whole chain
```bash
cd /mnt/c/Users/Nitro/Desktop/ASIC/Projects/cleave
unset DISPLAY
qflow route    tt_um_cleave && \
qflow migrate  tt_um_cleave && \
qflow drc      tt_um_cleave && \
qflow gdsii    tt_um_cleave && \
qflow lvs      tt_um_cleave
```
**Prevent the sleep-kill:** run it in a way that survives (e.g. keep the laptop awake, or
`sudo systemd-inhibit --what=sleep ...`), because a WSL VM restart kills background jobs.

### If routing congests / doesn't complete (qrouter reports remaining/failed nets)
Lower utilization and re-place+route:
- edit `project_vars.sh`: `set initial_density = 0.35` (then 0.30 if needed)
- `qflow place tt_um_cleave` (another ~60 min) then `qflow route tt_um_cleave`.
Graywolf/qrouter are near their comfortable size limit here; if it keeps failing, the repo is
already set up for **OpenROAD/OpenLane** (`src/config.json`), which handles a 22.6k-cell block far
better and still targets sky130 — a reasonable pivot if qflow routing proves impractical.

---

## 5. STA (OpenSTA) — not finished, needs your sudo

qflow's default `sta_tool` is `vesta` (absent); we set `sta_tool = opensta`. `opensta.sh` calls
`/usr/local/share/qflow/bin/sta`. OpenSTA is **cloned to `~/OpenSTA`** but **not built** — its deps
were never installed (needs an interactive `sudo`, which the unattended session can't do).

To finish STA:
```bash
# 1) deps (you run — interactive sudo):
sudo apt install -y swig libeigen3-dev
# 2) build (no sudo):
cd ~/OpenSTA && cmake -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build -j
# 3) install into qflow's bin (you run — sudo):
sudo cp ~/OpenSTA/build/app/sta /usr/local/share/qflow/bin/sta
# 4) run it (SDC already written: synthesis/tt_um_cleave.sdc, clk @ 40 ns):
cd /mnt/c/Users/Nitro/Desktop/ASIC/Projects/cleave && qflow sta tt_um_cleave
tail -40 log/sta.log     # look for no negative slack at 40 ns; loosen the period if needed
```
STA is optional for the DRC/LVS deliverable — skip it if you just want the GDS.

---

## 6. How to view the layout / GDS

Once `layout/tt_um_cleave.gds` exists:
- **KLayout (easiest):** double-click `C:\Users\Nitro\Desktop\ASIC\Projects\cleave\layout\tt_um_cleave.gds`
  in Explorer (you have KLayout 0.30.7 installed), or in WSL: `klayout .../layout/tt_um_cleave.gds`.
- **GDS3D:** load it for the 2.5D/3D cross-section (portfolio shot).
- **Magic (editable, in-tech):** `magic -T sky130A .../layout/tt_um_cleave.mag` (from the layout dir).

Sign-off logs to screenshot for the writeup: `log/drc.log` (magic DRC → expect 0 errors),
`log/lvs.log` (netgen → expect **"Circuits match uniquely."**), and `log/sta.log` if STA is run.

---

## 7. Caveats / gotchas learned this session

- **WSL sleeps kill long jobs.** The first routing run died when the laptop slept (VM restart also
  wipes `/tmp`). Durable artifacts on `/mnt/c` survive; keep the machine awake for the long route.
- **Design size** (22.6k cells) makes graywolf placement ~1 hr and qrouter potentially longer with
  congestion risk. This is expected, not a bug.
- **`ff_n40C_1v95`** (fast corner) is what the tech `.sh` points liberty at — fine for functional
  P&R + DRC/LVS. For real timing sign-off, re-run STA against `tt_025C_1v80` and `ss_100C_1v60`.
- **imem ROM** (64×32 constants) hardens to combinational logic — expected, not a memory macro.
- **WSL command quoting:** `wsl.exe -- bash -lc '…'` has `$vars`/`$(...)` expanded by the outer
  Git-Bash; run logic from a script file instead (this whole session used scratch `.sh` files).

---

*End of handoff. Synthesis + placement are solid and reproducible; the remaining work is finishing
routing (and its GDS/DRC/LVS chain) without the laptop sleeping, plus the optional OpenSTA build.*
