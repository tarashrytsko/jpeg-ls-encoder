# Wide Horizontal + Block Splitting (~4 Gb/s) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** From one mode-parameterized RTL, produce timing-closed ~512 MB/s bitstreams for **horizontal** (`N_H=1,N_V=16`) and **block** (`N_H=4,N_V=4`) JPEG-LS splitting on `xc7a200tfbg676-2`, each bit-exact lossless, with the existing vertical build unaffected.

**Architecture:** The wide 16-lane pipeline is already grid-parametric except two vertical-specific spots. Generalize the wide splitter's intra-strip y-range to `swathH = i_h/N_V` (one RTL edit), generalize the striding tool `make_strided_hex.py` with an `N_V` argument (row/block layout), then build each mode via a build-time `(N_H,N_V)` integer generic + a mode-specific ROM. Everything else (`jls_encoder_axis`, `axis_image_source`, `encoder_wrapper`, FIFOs, sink, `jls_demo_top`, XDC, clk_wiz 32/32) is unchanged.

**Tech Stack:** Verilog-2001, Vivado 2024.2 (xsim + synth_1/impl_1), Python (striding tool + verifier), TCL build scripts.

## Global Constraints

- `N_E = 16` lanes in every mode; `N_H * N_V = 16` (one block per lane).
- Clocks `wr_clk = rd_clk = 32 MHz` (1:1), from `clk_wiz_0` (already set) → throughput `16 × 32 = 512 Mpix/s = 512 MB/s`.
- Demo image **256×256** (`JPEG_ENC_8f.sim/images/wide_256.pgm`, already exists); all modes' per-lane strip width ≤ 1024 so `LB_DEPTH=1024` is unchanged.
- Lossless only (`NEAR=0`). Verify with `verify_lossless.py <jls> <pgm> <N_H> <N_V>` (grid reassembly).
- Target device `xc7a200tfbg676-2`. HW gate: `impl_1 → write_bitstream`, **WNS ≥ 0**.
- Branch `feature/jls-encoder-axis`. Vertical build (`N_H=16,N_V=1`) must keep passing.

---

## Background facts (verified this session)

- **`block_split.v`** (module `splitter_block`, wide lockstep): has `wire [15:0] stripW = i_w / N_H;` and intra-strip counters `xs` (0..stripW-1), `ys`. It uses **`i_h`** for the y-range in three places (lines 58, 75, 98) — this hardcodes `N_V=1`. All lanes get a pixel every valid cycle: `o_x[k*8+:8] <= i_x[k*8+:8]`, `o_last_enc[k]` at strip end.
- **`encoder_wrapper.v`** already derives per-lane `col_w = i_w/N_H` and `row_h = i_h/N_V` for any grid — no change.
- **`axis_image_source.v`** streams `rom_wide.hex` words in order; word count `N = (IMG_W/N_E)*IMG_H = W*H/N_E` is mode-invariant. Stride lives in the ROM, not the RTL — no change.
- **`jls_demo_top.v`** params `N_E=16, N_H=16, N_V=1, IMG_W=256, IMG_H=256`; instantiates `jls_encoder_axis #(.N_E,.N_H,.N_V)`. Overriding `N_H`/`N_V` (integers) via a synth generic propagates down.
- **`tb_jls_wide.v`** (AXIS-fed sim TB) params `N_E=16,N_H=16,N_V=1`, `HEXFILE`, `IMG_W=256,IMG_H=256`; instantiates `jls_encoder_axis #(.N_E,.N_H,.N_V)` and captures 16 lanes → `output_h{N_H}v{N_V}_<W>x<H>.jls`.
- **`make_strided_hex.py`** currently takes `(in.pgm, out.hex, N_H)`, assumes `N_V=1` (column-strided): `byte k = px[ys*w + k*sw + xs]`, `sw=w/N_H`.
- Striding ↔ splitter contract: lane `k` = block `(bx,by)` with `bx=k%N_H, by=k/N_H`; at intra-strip `(xs,ys)` its full-image pixel is `(bx*stripW+xs, by*swathH+ys)`, `stripW=W/N_H`, `swathH=H/N_V`. ROM word order is `ys` outer, `xs` inner (matches the splitter counter).

---

## File Structure

**Modified**
- `JPEG_ENC_8f.srcs/sources_1/new/block_split.v` — add `swathH`, use it for y-range/`o_last`.
- `tools/make_strided_hex.py` — add optional `N_V` arg + general `(bx,by)` formula (default `N_V=1` = current behavior).

**New**
- `JPEG_ENC_8f.srcs/sources_1/new/rom_wide_h1v16.hex`, `rom_wide_h4v4.hex` — per-mode ROMs.
- `JPEG_ENC_8f.sim/sim_1/behav/xsim/build_wide_mode.tcl` — `(N_H,N_V)`-parameterized synth+impl (activates the mode ROM, sets the generic).

**Unchanged:** `jls_encoder_axis.v`, `axis_image_source.v`, `axis_pixel_in.v`, `axis_sink.v`, `jls_demo_top.v`, `encoder_wrapper.v`, `fifo_*`, `jls_demo_top_wide.xdc`, `clk_wiz_0` (32/32).

---

## Task 1: Generalize the splitter y-range (`swathH`)

**Files:** Modify `JPEG_ENC_8f.srcs/sources_1/new/block_split.v`

**Interfaces:**
- Consumes: module params `N_H`, `N_V`; inputs `i_w[15:0]`, `i_h[13:0]`.
- Produces: a splitter that streams each lane's `stripW×swathH` sub-image (`stripW=i_w/N_H`, `swathH=i_h/N_V`) in lockstep, asserting `o_last_enc[*]` at `(stripW-1, swathH-1)`. At `N_V=1`, `swathH=i_h` → identical to current behavior.

- [ ] **Step 1: Add the `swathH` wire.** Replace:
```verilog
    // strip width (per lane). Each lane encodes a stripW x i_h sub-image.
    wire [15:0] stripW = i_w / N_H;
    reg  [15:0] xs;   // intra-strip x: 0..stripW-1
    reg  [13:0] ys;   // y: 0..i_h-1
```
with:
```verilog
    // per-lane sub-image is stripW x swathH (grid geometry).
    wire [15:0] stripW = i_w / N_H;
    wire [13:0] swathH = i_h / N_V;
    reg  [15:0] xs;   // intra-strip x: 0..stripW-1
    reg  [13:0] ys;   // intra-swath y: 0..swathH-1
```

- [ ] **Step 2: Fix the three `i_h-1` uses.** Change each of these EXACT lines from `i_h-1` to `swathH-1`:
  - `frame_active` end test: `else if(xs == stripW-1 && ys == i_h-1)` → `else if(xs == stripW-1 && ys == swathH-1)`
  - counter: `if (ys < i_h-1) ys <= ys + 1;` → `if (ys < swathH-1) ys <= ys + 1;`
  - routing `o_last`: `if (xs == stripW-1 && ys == i_h-1)` → `if (xs == stripW-1 && ys == swathH-1)`
  Leave everything else unchanged (stripW usage, the wide broadcast, ports).

- [ ] **Step 3: Compile-check.** From `JPEG_ENC_8f.sim/sim_1/behav/xsim/`:
```
xvlog --relax "../../../../JPEG_ENC_8f.srcs/sources_1/new/block_split.v" -log xvlog_t1.log
```
Expected: analyzes `splitter_block`, no ERROR.

- [ ] **Step 4: Vertical regression gate.** Confirm `N_V=1` behavior is unchanged. Ensure the vertical feed exists (regenerate with the CURRENT tool — N_H arg only):
```
python tools/make_strided_hex.py "JPEG_ENC_8f.sim/images/wide_256.pgm" "JPEG_ENC_8f.sim/images/wide_256_strided.hex" 16
```
`tb_jls_wide.v` is already at vertical defaults (N_H=16,N_V=1, HEXFILE=wide_256_strided.hex). Run it:
```
cd JPEG_ENC_8f.sim/sim_1/behav/xsim
xvlog --relax -prj tb_jls_wide_vlog.prj -log xvlog_t1v.log
xelab --debug typical --relax --mt 2 -L xil_defaultlib -L fifo_generator_v13_2_11 -L unisims_ver -L unimacro_ver -L secureip -L xpm --snapshot tb_jls_wide_behav xil_defaultlib.tb_jls_wide xil_defaultlib.glbl -log elaborate_t1v.log
xsim tb_jls_wide_behav -tclbatch run_quit.tcl -log simulate_t1v.log
```
Then verify (from project root):
```
python verify_lossless.py "JPEG_ENC_8f.sim/output_block/output_h16v1_256x256.jls" "JPEG_ENC_8f.sim/images/wide_256.pgm" 16 1
```
Expected: `BENCHMARK_RESULT ... OUT_BYTES=9593` in the sim log and `LOSSLESS: exact match (256x256)`. (9593 = the known vertical result — must be unchanged.)

- [ ] **Step 5: Commit.**
```bash
git add "JPEG_ENC_8f.srcs/sources_1/new/block_split.v"
git commit -m "feat(wide): generalize splitter y-range to swathH=i_h/N_V (any grid; vertical unchanged)"
```

## Task 2: Generalize `make_strided_hex.py` (`N_V` arg)

**Files:** Modify `tools/make_strided_hex.py`

**Interfaces:**
- Produces: `python tools/make_strided_hex.py in.pgm out.hex N_H [N_V]`. With `N_V` omitted or `1` → column-strided (unchanged). General: `byte k = px[(by*sh+ys)*w + (bx*sw+xs)]`, `bx=k%N_H, by=k/N_H, sw=w/N_H, sh=h/N_V, N_E=N_H*N_V`; word order `ys` outer, `xs` inner; total words `sw*sh = w*h/N_E`.

- [ ] **Step 1: Replace the file** with the generalized version:
```python
# tools/make_strided_hex.py  —  python tools/make_strided_hex.py in.pgm out.hex N_H [N_V]
# Emits one N_E-byte word per cycle (ys outer, xs inner). Byte k = lane k's pixel,
# lane k at block (bx=k%N_H, by=k//N_H); full-image coord (bx*sw+xs, by*sh+ys).
# N_V defaults to 1 (column-strided / vertical) for back-compat.
import sys
def token(d,i):
    while d[i:i+1].isspace(): i+=1
    if d[i:i+1]==b'#':
        while d[i:i+1]!=b'\n': i+=1
        return token(d,i)
    j=i
    while not d[j:j+1].isspace(): j+=1
    return d[i:j],j
def main():
    src,dst,NH = sys.argv[1], sys.argv[2], int(sys.argv[3])
    NV = int(sys.argv[4]) if len(sys.argv) > 4 else 1
    d=open(src,'rb').read(); i=0
    mg,i=token(d,i); assert mg==b'P5'
    w,i=token(d,i); h,i=token(d,i); mx,i=token(d,i); i+=1
    w,h=int(w),int(h); px=d[i:i+w*h]
    assert w % NH == 0, "width must be divisible by N_H"
    assert h % NV == 0, "height must be divisible by N_V"
    sw=w//NH; sh=h//NV; NE=NH*NV
    with open(dst,'w') as f:
        for ys in range(sh):
            for xs in range(sw):
                word=0
                for k in range(NE):
                    bx=k%NH; by=k//NH
                    word |= px[(by*sh+ys)*w + (bx*sw+xs)] << (8*k)
                f.write("%032X\n" % word)
    print("wrote %d words (%dx%d N_H=%d N_V=%d sw=%d sh=%d N_E=%d) to %s"%(sw*sh,w,h,NH,NV,sw,sh,NE,dst))
if __name__=="__main__": main()
```

- [ ] **Step 2: Back-compat check.** Regenerate the vertical feed two ways and confirm byte-identical (proves `N_V=1` unchanged):
```
python tools/make_strided_hex.py "JPEG_ENC_8f.sim/images/wide_256.pgm" /tmp/v_new.hex 16 1
python tools/make_strided_hex.py "JPEG_ENC_8f.sim/images/wide_256.pgm" /tmp/v_def.hex 16
cmp /tmp/v_new.hex /tmp/v_def.hex && echo "N_V default == N_V=1 OK"
cmp /tmp/v_new.hex "JPEG_ENC_8f.sim/images/wide_256_strided.hex" && echo "matches existing vertical feed OK"
```
Expected: both `OK` (the generalized tool at N_H=16,N_V=1 reproduces the existing vertical feed exactly).

- [ ] **Step 3: Commit.**
```bash
git add tools/make_strided_hex.py
git commit -m "feat(wide): make_strided_hex.py supports N_V (row/block striding); N_V=1 back-compatible"
```

## Task 3: Horizontal lossless sim gate (1×16)

**Files:** Create `JPEG_ENC_8f.sim/images/rom_wide_h1v16.hex`; temporarily set `tb_jls_wide.v` to horizontal.

- [ ] **Step 1: Generate the horizontal (row-strided) feed.**
```
python tools/make_strided_hex.py "JPEG_ENC_8f.sim/images/wide_256.pgm" "JPEG_ENC_8f.sim/images/rom_wide_h1v16.hex" 1 16
```
Expected: `wrote 4096 words (256x256 N_H=1 N_V=16 sw=256 sh=16 N_E=16 ...)`.

- [ ] **Step 2: Point the TB at horizontal.** In `JPEG_ENC_8f.srcs/sim_1/imports/FPGA Encoders/tb_jls_wide.v`, set the parameter defaults for this run: `N_H = 1`, `N_V = 16`, and `HEXFILE = "D:/techbistro/upwork/JPEG_Encoder_Project/JPEG_ENC_8f/JPEG_ENC_8f.sim/images/rom_wide_h1v16.hex"` (leave `N_E=16`, `IMG_W=256`, `IMG_H=256`).

- [ ] **Step 3: Run the sim.** From `JPEG_ENC_8f.sim/sim_1/behav/xsim/`:
```
xvlog --relax -prj tb_jls_wide_vlog.prj -log xvlog_h.log
xelab --debug typical --relax --mt 2 -L xil_defaultlib -L fifo_generator_v13_2_11 -L unisims_ver -L unimacro_ver -L secureip -L xpm --snapshot tb_jls_wide_behav xil_defaultlib.tb_jls_wide xil_defaultlib.glbl -log elaborate_h.log
xsim tb_jls_wide_behav -tclbatch run_quit.tcl -log simulate_h.log
```
Expected: `BENCHMARK_RESULT N_H=1 N_V=16 ... OUT_BYTES=<n>`, writes `output_h1v16_256x256.jls`. No `WATCHDOG`.

- [ ] **Step 4: Verify lossless (grid reassembly).** From project root:
```
python verify_lossless.py "JPEG_ENC_8f.sim/output_block/output_h1v16_256x256.jls" "JPEG_ENC_8f.sim/images/wide_256.pgm" 1 16
```
Expected: `16 chunks (expected 16), grid 1x16 ... LOSSLESS: exact match (256x256)`. If it hangs or mismatches, the likely cause is the `swathH` change (Task 1) or the row-striding formula (Task 2) — cross-check one strip: a full 256×16 sub-image encoded standalone should match lane 0.

- [ ] **Step 5: Commit** the horizontal ROM (the TB edit is temporary — it'll be restored to vertical in Task 7; do NOT commit the TB change here):
```bash
git add "JPEG_ENC_8f.sim/images/rom_wide_h1v16.hex"
git commit -m "test(wide): horizontal 1x16 bit-exact lossless (row-strips, 256x256)"
```

## Task 4: Horizontal timing-closed bitstream

**Files:** Create `JPEG_ENC_8f.sim/sim_1/behav/xsim/build_wide_mode.tcl`; copy the horizontal ROM into the on-chip ROM path.

**Interfaces:** Consumes `rom_wide_h1v16.hex`. Produces `jls_demo_top.bit` synthesized with `N_H=1,N_V=16`.

- [ ] **Step 1: Write `build_wide_mode.tcl`** (parameterized by `-tclargs <N_H> <N_V>`):
```tcl
# build_wide_mode.tcl  —  vivado -mode batch -source build_wide_mode.tcl -tclargs <N_H> <N_V>
# Builds the wide 16-lane jls_demo_top for the given split geometry. Activates the
# matching mode ROM at the fixed path axis_image_source reads (rom_wide.hex), sets
# the (N_H,N_V) integer generic on the top, and runs synth_1 + impl_1 -> bitstream.
set root "D:/techbistro/upwork/JPEG_Encoder_Project/JPEG_ENC_8f"
set NH [lindex $argv 0]
set NV [lindex $argv 1]
open_project $root/JPEG_ENC_8f.xpr
file copy -force $root/JPEG_ENC_8f.srcs/sources_1/new/rom_wide_h${NH}v${NV}.hex \
                 $root/JPEG_ENC_8f.srcs/sources_1/new/rom_wide.hex
set_property generic "N_H=$NH N_V=$NV" [get_filesets sources_1]
update_compile_order -fileset sources_1
reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { puts "MODE_SYNTH_FAILED"; return }
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
set ip [get_property PROGRESS [get_runs impl_1]]
puts "MODE_IMPL_PROGRESS: $ip  STATUS: [get_property STATUS [get_runs impl_1]]"
if {$ip ne "100%"} { puts "MODE_IMPL_FAILED"; return }
open_run impl_1
report_utilization    -file $root/mode_h${NH}v${NV}_util.rpt
report_timing_summary -file $root/mode_h${NH}v${NV}_timing.rpt
puts "MODE_DONE h${NH}v${NV} WNS=[get_property STATS.WNS [get_runs impl_1]] WHS=[get_property STATS.WHS [get_runs impl_1]]"
```
First stage the horizontal ROM as a source file so `file copy` has it (it lives in images/; copy it into sources_1/new):
```
cp "JPEG_ENC_8f.sim/images/rom_wide_h1v16.hex" "JPEG_ENC_8f.srcs/sources_1/new/rom_wide_h1v16.hex"
```

- [ ] **Step 2: Build horizontal.** From project root:
```
vivado -mode batch -source JPEG_ENC_8f.sim\sim_1\behav\xsim\build_wide_mode.tcl -tclargs 1 16 -log build_h1v16.vlog -nojournal
```
Expected: `MODE_DONE h1v16 WNS=<positive>`, `write_bitstream Complete!`, `jls_demo_top.bit` in `JPEG_ENC_8f.runs/impl_1/`. Confirm **WNS ≥ 0** in `mode_h1v16_timing.rpt` and clocks 32/32 MHz. (If WNS < 0: fall back to a lower clk via `clkwiz_3232.tcl`-style reconfigure — unlikely given vertical closed at +8.25 ns.)

- [ ] **Step 3: Commit** the build script, staged ROM, and reports:
```bash
git add "JPEG_ENC_8f.sim/sim_1/behav/xsim/build_wide_mode.tcl" "JPEG_ENC_8f.srcs/sources_1/new/rom_wide_h1v16.hex" mode_h1v16_util.rpt mode_h1v16_timing.rpt JPEG_ENC_8f.xpr
git commit -m "build(wide): timing-closed horizontal 1x16 bitstream (~512 MB/s)"
```

## Task 5: Block lossless sim gate (4×4)

**Files:** Create `JPEG_ENC_8f.sim/images/rom_wide_h4v4.hex`; temporarily set `tb_jls_wide.v` to block.

- [ ] **Step 1: Generate the block (block-strided) feed.**
```
python tools/make_strided_hex.py "JPEG_ENC_8f.sim/images/wide_256.pgm" "JPEG_ENC_8f.sim/images/rom_wide_h4v4.hex" 4 4
```
Expected: `wrote 4096 words (256x256 N_H=4 N_V=4 sw=64 sh=64 N_E=16 ...)`.

- [ ] **Step 2: Point the TB at block.** In `tb_jls_wide.v` set `N_H = 4`, `N_V = 4`, `HEXFILE = "D:/techbistro/upwork/JPEG_Encoder_Project/JPEG_ENC_8f/JPEG_ENC_8f.sim/images/rom_wide_h4v4.hex"`.

- [ ] **Step 3: Run the sim** (same commands as Task 3 Step 3, logs `*_b`). Expected: `BENCHMARK_RESULT N_H=4 N_V=4 ... OUT_BYTES=<n>`, writes `output_h4v4_256x256.jls`, no WATCHDOG.

- [ ] **Step 4: Verify lossless.**
```
python verify_lossless.py "JPEG_ENC_8f.sim/output_block/output_h4v4_256x256.jls" "JPEG_ENC_8f.sim/images/wide_256.pgm" 4 4
```
Expected: `16 chunks (expected 16), grid 4x4 ... LOSSLESS: exact match (256x256)`.

- [ ] **Step 5: Commit** the block ROM:
```bash
git add "JPEG_ENC_8f.sim/images/rom_wide_h4v4.hex"
git commit -m "test(wide): block 4x4 bit-exact lossless (64x64 blocks, 256x256)"
```

## Task 6: Block timing-closed bitstream

**Files:** reuse `build_wide_mode.tcl`; stage the block ROM as a source.

- [ ] **Step 1: Stage the block ROM** into sources_1/new (so `file copy` finds it):
```
cp "JPEG_ENC_8f.sim/images/rom_wide_h4v4.hex" "JPEG_ENC_8f.srcs/sources_1/new/rom_wide_h4v4.hex"
```

- [ ] **Step 2: Build block.** From project root:
```
vivado -mode batch -source JPEG_ENC_8f.sim\sim_1\behav\xsim\build_wide_mode.tcl -tclargs 4 4 -log build_h4v4.vlog -nojournal
```
Expected: `MODE_DONE h4v4 WNS=<positive>`, `write_bitstream Complete!`, `.bit` produced, WNS ≥ 0, clocks 32/32.

- [ ] **Step 3: Commit** reports + staged ROM:
```bash
git add "JPEG_ENC_8f.srcs/sources_1/new/rom_wide_h4v4.hex" mode_h4v4_util.rpt mode_h4v4_timing.rpt JPEG_ENC_8f.xpr
git commit -m "build(wide): timing-closed block 4x4 bitstream (~512 MB/s)"
```

## Task 7: Restore vertical defaults + document

**Files:** Restore `tb_jls_wide.v` + `rom_wide.hex` to vertical; update `BENCHMARKS.md`, `CLAUDE.md`.

- [ ] **Step 1: Restore vertical working state.** The TB was edited to block in Task 5 and `rom_wide.hex` was overwritten by the last build. Restore both to vertical (the committed default):
```bash
git checkout -- "JPEG_ENC_8f.srcs/sim_1/imports/FPGA Encoders/tb_jls_wide.v" "JPEG_ENC_8f.srcs/sources_1/new/rom_wide.hex"
```
(`rom_wide.hex` returns to the committed vertical ROM; `tb_jls_wide.v` returns to `N_H=16,N_V=1`.) Also reset the project generic back to the vertical default so the committed `.xpr` isn't left on block:
```
vivado -mode batch -source - <<'EOF'
open_project D:/techbistro/upwork/JPEG_Encoder_Project/JPEG_ENC_8f/JPEG_ENC_8f.xpr
set_property generic "N_H=16 N_V=1" [get_filesets sources_1]
EOF
```
(Or `reset_property generic [get_filesets sources_1]` to clear the override entirely — jls_demo_top defaults are already `N_H=16,N_V=1`.) Commit the `.xpr` if it changed.

- [ ] **Step 2: Document.** In `JPEG_ENC_8f.sim/output_block/BENCHMARKS.md`, extend the wide section: all **three** split directions now build to timing-closed ~512 MB/s bitstreams — vertical (16×1), **horizontal (1×16)**, **block (4×4)** — with a small table of each mode's WNS + utilization (from `mode_h1v16_*.rpt` / `mode_h4v4_*.rpt`) and the lossless-verified note (grid reassembly). In `CLAUDE.md`, add one line to the wide-build section: the wide encoder is mode-parameterized (`(N_H,N_V)` build generic + mode ROM), all three directions hardware-proven at 512 MB/s; note the wide architecture retires the old horizontal serial-swath caveat (all 16 row-lanes run concurrently).

- [ ] **Step 3: Commit.**
```bash
git add "JPEG_ENC_8f.sim/output_block/BENCHMARKS.md" CLAUDE.md JPEG_ENC_8f.xpr
git commit -m "docs: horizontal + block wide splitting hardware-proven at 512 MB/s"
```

---

## Self-Review (against spec)

**Spec coverage:**
- One RTL edit (splitter `swathH`) → Task 1. ✓
- `make_strided_hex.py` `N_V` generalization → Task 2. ✓
- Per-mode ROM + build-time `(N_H,N_V)` override → Tasks 4, 6 (build_wide_mode.tcl generic + ROM copy). ✓
- Horizontal (1×16) lossless + bitstream → Tasks 3, 4. ✓
- Block (4×4) lossless + bitstream → Tasks 5, 6. ✓
- Grid-reassembly lossless gate per mode → Tasks 3, 5 (`verify_lossless … N_H N_V`). ✓
- Timing-closed bitstream WNS ≥ 0 @ 32/32 → Tasks 4, 6. ✓
- Vertical build unaffected → Task 1 Step 4 regression + Task 7 restore. ✓
- Docs → Task 7. ✓
- LB_DEPTH unchanged (all strips ≤1024) → Global Constraints (no task needed). ✓

**Placeholder scan:** none — complete code for the RTL edit + tool + build TCL; exact commands + expected output for every gate. The one judgment call (WNS<0 fallback) has a concrete pointer (`clkwiz_3232.tcl`).

**Type/name consistency:** `swathH` used consistently (Task 1); `make_strided_hex.py … N_H [N_V]` signature matches its uses in Tasks 3/5; `rom_wide_h{NH}v{NV}.hex` naming consistent across generation (3/5), staging (4/6), and `build_wide_mode.tcl`'s `file copy`; `verify_lossless … <N_H> <N_V>` grid args match the modes; output filenames `output_h{N_H}v{N_V}_256x256.jls` consistent.

## Risks
- **Splitter off-by-one (swathH):** guarded by Task 1's vertical regression (must still be 9593 B) + the per-mode grid-reassembly gates.
- **Stride ↔ splitter mismatch:** same `(bx,by)` mapping in tool and splitter; the lossless gate catches garbling.
- **ROM-swap statefulness:** `build_wide_mode.tcl` overwrites `rom_wide.hex`; Task 7 restores it to the committed vertical ROM so the repo default stays vertical.
- **Horizontal timing (full-width line buffer, 256 deep here):** same logic that closed vertical at +8.25 ns; expected to close.
