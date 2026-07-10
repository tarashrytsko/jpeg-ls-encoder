# JPEG-LS Parallel Encoder Benchmark Results

## System Configuration
- **Target:** Xilinx Artix-7 (xc7a200tfbg676-2)
- **Clocks:** wr_clk = 150 MHz, rd_clk = 50 MHz
- **Architecture:** Streaming splitter + N parallel encoders + continuous-drain FIFO control
- **Mode:** NEAR=0 (lossless)
- **Input:** 8-bit grayscale satellite imagery (NASA Blue Marble)

## Benchmark Results (5 Encoders × 4 Chunks)

| Image | Pixels | Block Size | Output | Ratio | Throughput | Sim Time | Wall Time |
|---|---|---|---|---|---|---|---|
| 300×300 | 90K | 60×30 | 7.6 KB | 11.9:1 | 150 Mpix/s | 102 µs | ~1 min |
| 1500×1500 | 2.25M | 300×375 | 1.06 MB | 2.13:1 | 150 Mpix/s | 15 µs | ~10 min |
| 3000×3000 | 9M | 600×750 | 4.95 MB | 1.82:1 | 150 Mpix/s | 60 µs | ~30 min |
| 5000×5000 | 25M | 1000×1250 | 15.9 MB | 1.57:1 | 150 Mpix/s | 167 µs | ~2.5 hrs |
| 10000×10000 | 100M | 2000×2500 | 52.6 MB | 1.90:1 | 150 Mpix/s | 667 µs | ~10 hrs |
| 16000×5000 | 80M | 3200×1250 | 69.2 MB | 1.16:1 | 150 Mpix/s | 533 µs | ~8 hrs |

## Earlier Results (3 Encoders × 4 Chunks, Alternating Groups)

| Image | Block Size | Output | Ratio |
|---|---|---|---|
| 1500×1500 | 500×375 | 327 KB | **6.87:1** |
| 3000×3000 | 1000×750 | 1.88 MB | **4.78:1** |
| 5000×5000 | 1666×1250 | 5.78 MB | **4.32:1** |

## Key Findings

1. **Throughput is constant at 150 Mpix/s** regardless of image size (limited by rd_clk = 50 MHz per encoder)
2. **Block size significantly affects compression ratio:**
   - Block > 1000×1000 → 4–7:1 compression
   - Block 500–1000 → 2–4:1 compression
   - Block < 500 → 1–2:1 compression (header overhead dominates)
3. **Fewer encoders = better compression** (wider blocks = better prediction context)
4. **Image content matters:** uniform ocean regions compress 10:1+, detailed terrain compresses 1.2–2:1

## Recommended Configurations

| Image Size | Encoders | Chunks | Block Size | Expected Ratio |
|---|---|---|---|---|
| ≤3K | 3 | 4 | ~1000×750 | 4–7:1 |
| 5K–10K | 5 | 4 | ~1000–2000×1250–2500 | 2–4:1 |
| >10K | 5 | 4–8 | ~2000–3000×1250–1875 | 1.5–3:1 |

## Output File Structure

Each simulation produces `N_E × NUM_SWATHS` JLS files:
```
output_block/
├── enc0a.jls, enc0b.jls, enc0c.jls, enc0d.jls   (encoder 0, chunks a-d)
├── enc1a.jls, enc1b.jls, ...                      (encoder 1)
├── enc2a.jls, ...                                 (encoder 2)
├── enc3a.jls, ...                                 (encoder 3)
└── enc4a.jls, ...                                 (encoder 4)
```

Each file is an independent JPEG-LS image decodable with `JPEGLSdec.exe`.
The Java `custom_decoder` tool stitches all files into a single output PGM.

## Notes
- "b" slice files have a duplicate SOI byte (strip first 2 bytes before decoding)
- Line buffer depth: 16384 entries limits max encoder block width to 16384 pixels
- FIFO depth: 131072 entries — sufficient for streaming with continuous-drain architecture
- Pixel accuracy: 99.9%+ for evenly-divisible dimensions, ~0.06–0.1% prediction artifacts at block boundaries

---

# Splitting Mode Comparison — Block vs Vertical vs Horizontal

The encoder now benchmarks all three splitting directions, not just block. Mode is
selected purely by the `(N_H, N_V)` block-grid factorization (parameters on
`top_jls_vertical` / `tb_top_jls_vertical`; driven by the sweep script). With one
block per encoder (`N_E` encoders, `NUM_SLICES=1`):

For a block grid `a×b`, N_E = a·b encoders (one block each), and the three cut
directions at that parallelism are:

| Grid (N_E) | Block (N_H×N_V) | Vertical (N_E×1) | Horizontal (1×N_E) |
|------------|-----------------|------------------|--------------------|
| 2×2 (4)    | 2 × 2           | 4 × 1            | 1 × 4              |
| 3×3 (9)    | 3 × 3           | 9 × 1            | 1 × 9              |
| 4×5 (20)   | 4 × 5           | 20 × 1           | 1 × 20             |

## Results (NEAR=0 lossless, NASA Blue Marble grayscale) — all exact-match verified

Compression ratio (input pixels / output bytes), by grid × cut direction:

**300×300**
| Grid | Block | Vertical | Horizontal |
|------|------:|---------:|-----------:|
| 2×2  | 7.55:1 | 7.55:1 | 7.47:1 |
| 3×3  | 7.27:1 | 7.15:1 | 6.87:1 |
| 4×5  | 6.51:1 | 6.38:1 | 5.09:1 |

**1500×1500**
| Grid | Block | Vertical | Horizontal |
|------|------:|---------:|-----------:|
| 2×2  | 4.17:1 | 4.17:1 | 4.16:1 |
| 3×3  | 4.17:1 | 4.16:1 | 4.15:1 |
| 4×5  | 4.16:1 | 4.11:1 | 4.10:1 |

**5000×5000**
| Grid | Block | Vertical | Horizontal |
|------|------:|---------:|-----------:|
| 2×2  | 4.31:1 | 4.33:1 | 4.29:1 |
| 3×3  | 4.33:1 | 4.35:1 | 4.29:1 |
| 4×5  | 4.33:1 | 4.35:1 | 4.28:1 |

**16000×5000** (80 Mpix, 2×2 grid / N_E=4)
| Grid | Block (8000×2500) | Vertical (4000×5000) | Horizontal (16000×1250) |
|------|------:|---------:|-----------:|
| 2×2  | 3.30:1 | 3.31:1 | 3.29:1 |

All cells above (300², 1500², 5000² full 3×3×3 matrix + 16000×5000 2×2) were verified
**lossless** (exact pixel match) by decoding each slice (imagecodecs/CharLS) and
reassembling with `verify_lossless.py` — including the non-evenly-divisible cases
(5000/3, 5000/9).

> **Real-HW caveat for horizontal at large sizes.** In horizontal mode the read
> control drains one full-width swath at a time, so while one encoder runs the other
> N_V−1 encoders' rows stream in and must buffer. In *simulation* the FIFO model is
> effectively unbounded so it stays lossless, but on real hardware the 131072-deep
> input FIFO would fill and backpressure-stall hard once a swath exceeds the FIFO
> depth (e.g. a 16000×1250 = 20-Mpix swath ≫ 131072). Block/vertical keep all encoders
> draining concurrently and don't hit this. (Sim wall time already shows the cost:
> the 16000×5000 horizontal run took ~3.6 h vs ~2 h block / ~1.5 h vertical.)

## Findings
- **Parallelism (block count) dominates compression, not cut direction.** Going from
  4 blocks to 20 (more encoders) costs far more ratio than switching modes within a
  grid (300²: 7.55→6.51 across grids vs ≤1.5pt between modes of the same grid).
- **Block ≥ Vertical ≥ Horizontal**, and the gap widens as blocks shrink. At 1500²
  and 5000² (large blocks) all three are within ~2%; at 300² with the 4×5 grid the
  strips are tiny and horizontal (300×15 wide-short strips) drops to 5.09:1 vs block
  6.51:1 — short, wide strips lose vertical prediction context fastest.
- **The penalty for more encoders shrinks as the image grows.** At 5000² every block
  is ≥1000 px on a side regardless of grid, so all 9 cells collapse into a tight
  4.28–4.35:1 band — grid and cut direction barely matter once blocks are large. The
  fine-grid penalty only bites small images.
- Larger images compress less here (more high-detail terrain): ~7:1 @300², ~4.1:1
  @1500², ~4.3:1 @5000² (5000² rebounds slightly because its blocks are huge).
- Hardware throughput is `rd_clk`-limited (one pixel/cycle per encoder), independent
  of mode. In *simulation*, horizontal is dramatically the slowest (one encoder
  active per swath ⇒ least feed parallelism): the 5000² 1×20 horizontal took ~11.4 h
  vs ~40–90 min for block/vertical of the same image.

## How to run
```
JPEG_ENC_8f.sim/sim_1/behav/xsim/run_hv_benchmark.ps1 `
    -Images 300x300,1500x1500 -Grids 2x2,3x3,4x5 -Modes block,vertical,horizontal
```
Results append to `output_block/hv_benchmark_results.csv`. Verify any run with:
```
python verify_lossless.py output_block/output_hHvV_WxH.jls images/world_gray_WxH.pgm <N_H> <N_V>
```

## Architecture notes / constraints
- **Mode = geometry.** Vertical = `N_H=N_E, N_V=1`; Horizontal = `N_H=1, N_V=N_E`;
  Block = a roughly-square `a×b` grid (`a·b=N_E`, so a composite `N_E` — 4→2×2,
  9→3×3 — makes the grid differ from the vertical/horizontal degenerate cases).
- **One block per encoder.** SOF is issued once per row-swath, so an encoder can
  emit only one slice per swath it occupies. *Vertical chunking* (several columns to
  one encoder within a single swath) is therefore unsupported — so the legacy
  "5 enc × 4 chunk" table **cannot** be reproduced for vertical. Horizontal *can*
  chunk via extra swaths; block chunks via `N_V` rows.
- **Vertical-mode fix (`fifo_read_control.v`).** Vertical's narrow, bursty,
  drains-to-empty-every-row feeding exposed an async-FIFO empty-flag race: the read
  FSM counted `rd_en` pulses that returned no data ("phantom reads") and declared a
  swath done before the encoder had received all its pixels, so end-of-frame never
  fired and the slice never closed (hang). The FSM now counts delivered `fifo_valid`
  pulses and gates reads on `rd_cnt + in_flight < enc_pixels`, fully draining each
  FIFO without over-reading into the next swath. Block/horizontal (few/no phantoms)
  are unaffected.
- **Swath-height remainder fix (`encoder_wrapper.v`).** `swath_h = i_h/N_V` was a
  single uniform value, so when the image height wasn't divisible by `N_V` the last
  row of encoders was under-sized and dropped its remainder rows (broke 3×3 grids on
  5000×5000 and 1×9 horizontal on 300×300). Each encoder is now given its own
  `row_h[row]` with the remainder on the last swath — mirroring the `col_w` handling
  that columns already had. Evenly-divisible cases are unchanged.

---

# Clock Ratio (wr_clk : rd_clk) and the Output-Drain Fix

Clocks come from `clk_wiz_0` (200 MHz diff in): `wr_clk = clk` (input/FIFO-read side)
and `rd_clk` (encoder). Baseline is **wr_clk = 450 MHz, rd_clk = 150 MHz (3:1)**.

**Behavioral-sim note:** compression is identical at any absolute frequency; only the
**wr_clk : rd_clk ratio** changes functional behavior (async-FIFO fill/drain). Actual
max frequency on the Artix-7 is a synthesis/STA question, not a sim one.

## Output-drain evolution → full-rate, ratio-independent

The output-FIFO drain (`fifo_wrapper_output.v`) went through three versions as the
clock ratio was pushed down toward 1:1:

1. **Original (registered `rd_en = !empty`)** — fine at 3:1, but at **2:1** it
   over-read the near-empty FIFO (the async `empty` flag lags at a 2× read clock) and
   corrupted the stream (SOI dropped + words duplicated). That's why the project sat
   at 3:1. (Output-side twin of the input "phantom-read" bug.)
2. **1-outstanding throttle** — issue `rd_en` only when `!empty && !pending`, clear
   `pending` on `valid`. Fixed 2:1, but **halved the drain rate**, forcing `wr ≥ 2×rd`
   (2:1 floor; 1:1 overflowed).
3. **Full-rate, first-word-correct (current)** — `rd_en = ~empty` (combinational,
   full rate) **and `dout_valid` driven from the registered read-enable** rather than
   the IP's `valid` flag. The IP's `valid` skipped the *first* read at a 1:1 rate,
   dropping the leading `FFD8` of each multi-swath chunk. A probe confirmed the
   encoder output was always correct (`ENC0_OUT[0]=ffd8`) while the FIFO output
   started at `fff7`; a standard FIFO returns data one cycle after the read, so the
   registered `rd_en` is the correct valid strobe and captures every word.

Verified lossless, **all three modes**, at **1:1, 2:1, and 3:1** (300²; plus 1:1 at
1500² and 3000²). The `wr ≥ 2×rd` constraint is gone — the drain is correct at any
ratio down to 1:1.

## 4 Gb/s in + out — 1:1 at 500/500 MHz

With 1:1 working, set `clk_wiz_0` to **wr_clk = rd_clk = 500 MHz**. Input is one 8-bit
pixel/cycle = **500 MHz × 8 = 4 Gb/s**, and every split type runs at the encoder rate:

| Mode @ 3000² | Geometry | Encode time | Throughput |
|--------------|----------|-------------|------------|
| Block      | 2×2 | 18.01 ms | **500 Mpix/s = 4.00 Gb/s** |
| Vertical   | 4×1 | 18.01 ms | **500 Mpix/s = 4.00 Gb/s** |
| Horizontal | 1×4 | 18.02 ms | **499 Mpix/s = 3.99 Gb/s** |

(9 Mpix / ~18.0 ms = 500 Mpix/s.) Lossless across 300²/1500²/3000², all modes.
Throughput is input-limited (input = 500 Mpix/s), so all three modes converge to the
4 Gb/s input rate — horizontal is **no longer capped at input/2** now that the drain
runs full-rate at 1:1.

**Real-HW caveat.** 500 MHz for the JLS encoder is **not synthesizable on Artix-7**
(fabric tops out far lower for logic this complex), and 500 MHz here is the behavioral
`clk_wiz` *sim model* (the `.xci` synthesis config still says 450/150). On real
silicon, 4 Gb/s needs a clock that closes timing (it won't at 500 MHz) or a **wider
input datapath** (multiple pixels/cycle at a sane clock). What's real and portable is
the **drain fix** — it makes the output path correct at any wr:rd ratio, which is the
architectural enabler.

---

## Synthesis & Bitstream (real hardware, Artix-7 xc7a200tfbg676-2)

The encoder was refactored into a synthesizable AXI4-Stream IP (`jls_encoder_axis`) and
built to a **timing-closed bitstream** via the self-contained harness `jls_demo_top`
(on-chip `$readmemh` ROM AXIS source → IP → output pins). Lossless-only (NEAR removed).
Build: `build_synth.tcl` → `build_impl.tcl`; clock reconfigure via `build_fmax2.tcl`.

**Config:** `N_E=2`, `N_H=2`, `N_V=1` (two parallel vertical column-strip encoders).

| Metric | Result |
|---|---|
| Implementation | `impl_1` → `write_bitstream` Complete, `jls_demo_top.bit` (9.7 MB) |
| Clocks (closed) | `wr_clk` 60 MHz / `rd_clk` (encoder) 30 MHz (MMCM, VCO 990 MHz) |
| **WNS / WHS** | **+2.72 ns / +0.095 ns** (0 failing endpoints) |
| Utilization | LUT 5931 (4.4%), FF 3748 (1.4%), **BRAM 133 (36.4%)**, DSP 5 (0.7%) |
| Limiter | cross-domain CDC path; encoder logic has +11.6 ns intra slack (~46 MHz) |
| **Throughput** | **≈ 60 Mpix/s ≈ 480 Mb/s** (30 MHz × 2 parallel column encoders) |

BRAM (36%) is the gating resource — the two 16384×8 line buffers + the in/out FIFOs.
A conservative 33.33/10 MHz build also closes (WNS +3.5 ns). To go faster: declare the
two MMCM clocks asynchronous (CDC is FIFO/gray-code safe) to drop the cross-domain
limiter, then push toward the ~46 MHz encoder ceiling; or add more parallel encoders /
a wider input for higher aggregate throughput.

**Functional validation:** `tb_jls_demo_top` simulates the full harness; its output is
**byte-identical** to the proven AXIS path (`tb_jls_encoder_axis`) on the same 64×64
image (1011 bytes), and the AXIS refactor reproduces the pre-refactor lossless output
**exactly** at 300²/1500² across all split modes (incl. under ~50% `tready`
backpressure). So synthesis changed no encoding behavior.

---

## Wide 16-Lane Encoder — 512 MB/s (Artix-7 xc7a200tfbg676-2)

A 16-lane vertical column-strip configuration (`N_E=16`, `N_H=16`, `N_V=1`) was built
to a timing-closed bitstream using the same `jls_demo_top` harness. Input is a 128-bit
wide AXI4-Stream (16 pixels/cycle, column-strided — byte k carries strip k's pixel),
feeding a widened lockstep splitter; per-lane async FIFOs are retained (dual-clock
infrastructure kept but both run at the same frequency). Lossless-only (NEAR=0).

| Metric | Result |
|---|---|
| Config | N_E=16, N_H=16, N_V=1 (vertical column strips) |
| Input | 128-bit AXIS, 16 px/cycle, column-strided |
| Clocks | wr_clk = rd_clk = **32 MHz** (1:1, MMCM) |
| **WNS / WHS** | **+8.25 ns / +0.048 ns** (0 failing endpoints) |
| LUT | 39576 (29.4%) |
| FF | ~25012 (9.3%) |
| **BRAM** | **40 (11.0%** of 365) |
| DSP | 19 (2.6%) |
| **Throughput** | **16 lanes × 32 MHz = 512 Mpix/s = 512 MB/s ≈ 4.1 Gb/s** |
| Bitstream | `JPEG_ENC_8f.runs/impl_1/jls_demo_top.bit` |
| Build TCL | `build_wide_synth.tcl` → `build_impl.tcl`; clock: `clkwiz_3232.tcl` |

**How it fits on-chip (BRAM).** Naive 16-lane scaling of the 2-lane design would have
consumed ~860 BRAM (well over the 365 available). Actual usage is 40 BRAM (11%) through
two measures: (1) per-lane input FIFOs shrunk from depth 131072 to 512 and output FIFOs
from 65536 to 2048 (safe because 1:1 clocking eliminates the deep-buffer CDC need), and
(2) the encoder line buffer was parameterized (`LB_DEPTH=1024`) to the strip width
rather than the full image width — sufficient for a max image width of 16384 with 16
strips (16384/16=1024 per strip).

**Why 1:1 clocks.** With a 128-bit (16-pixel) input bus, the host feeds 16 pixels every
wr_clk cycle — exactly matching the 16 encoder lanes each consuming one pixel per
rd_clk cycle. A 2:1 ratio (wr > rd) would flood the shallow input FIFOs and starve the
encoders; this was verified to fail in practice. 1:1 is the natural frequency ratio for
a wide design where input bandwidth equals lane consumption bandwidth.

**Verification.** Lossless operation confirmed via 16-strip reassembly
(`verify_lossless.py ... 16 1`) on a 256×256 test image (exact pixel match after
decode). The self-contained `jls_demo_top` (on-chip ROM source) produced output
byte-identical (9593 bytes) to the proven AXIS-fed path, confirming synthesis preserved
all encoding behavior.

## Wide 16-Lane — All Three Split Directions Synthesizable at 512 MB/s (Artix-7 xc7a200tfbg676-2)

The wide 16-lane design is **mode-parameterized**: the same RTL builds vertical, horizontal,
or block splitting by setting the build-time `(N_H, N_V)` generic (`N_H·N_V = N_E = 16`, one
grid block per lane) and swapping in a matching strided input ROM. All three directions were
taken to **timing-closed bitstreams** at 32/32 MHz (1:1). Throughput is identical in every
direction — **16 lanes × 32 MHz = 512 Mpix/s = 512 MB/s ≈ 4.1 Gb/s** — because the parallelism
(16 independent encoder lanes, 1 px/cycle each, fed 16 px/cycle over a 128-bit AXIS bus) does
not change; only *which* sub-image each lane encodes changes.

| Mode | (N_H, N_V) | Per-lane sub-image (256²) | WNS / WHS | LUT | FF | BRAM | DSP | Bitstream |
|---|---|---|---|---|---|---|---|---|
| **Vertical** | 16 × 1 | 16 × 256 (column strip) | **+8.25 / +0.048 ns** | 39576 (29.4%) | 25012 (9.3%) | 40 (11.0%) | 19 (2.6%) | — (baseline) |
| **Horizontal** | 1 × 16 | 256 × 16 (row strip) | **+8.446 / +0.034 ns** | 39647 (29.5%) | 24663 (9.2%) | 40 (11.0%) | 19 (2.6%) | `bitstreams/jls_demo_top_h1v16.bit` |
| **Block** | 4 × 4 | 64 × 64 | **+8.636 / +0.047 ns** | 40300 (29.9%) | 24597 (9.1%) | 40 (11.0%) | 21 (2.8%) | `bitstreams/jls_demo_top_h4v4.bit` |

All three: **0 failing endpoints**, resource footprint within ~0.5% of each other (same
encoder logic; only splitter routing and the input ROM differ). Preserved bitstreams and
per-mode `mode_h{N_H}v{N_V}_util.rpt` / `_timing.rpt` live in `output_block/bitstreams/`.

**One RTL, one build entry point.** `build_wide_mode.tcl` takes the direction as arguments:

```
vivado -mode batch -source build_wide_mode.tcl -tclargs <N_H> <N_V>
```

It copies the mode ROM (`rom_wide_h<N_H>v<N_V>.hex`) into the synthesized `rom_wide.hex`,
overrides the `(N_H, N_V)` generic on `jls_demo_top`, and runs `synth_1` + `impl_1` →
`write_bitstream`. Vertical = `-tclargs 16 1`, horizontal = `-tclargs 1 16`, block = `-tclargs 4 4`.
The mode ROMs are produced by `tools/make_strided_hex.py <in.pgm> <out.hex> <N_H> <N_V>`
(column-strided for `N_V=1`, row-strided for `N_H=1`, block-strided otherwise).

**Lossless verification (256²).** Each direction's AXIS-fed sim (`tb_jls_wide`, 16-lane capture)
reassembles bit-exact via `verify_lossless.py … <N_H> <N_V>`:

| Mode | Output bytes (256²) | Grid reassembly |
|---|---|---|
| Vertical 16×1 | 9593 | LOSSLESS exact |
| Horizontal 1×16 | 9226 | LOSSLESS exact |
| Block 4×4 | 9056 | LOSSLESS exact |

> **Read-side fix enabling horizontal/block.** The original read controller drained encoder
> lanes swath-by-swath (one subset active per swath). That deadlocked the wide *lockstep* feed
> for `N_V > 1`: the splitter presents all 16 lanes concurrently, so any lane not in the active
> swath filled its FIFO, back-pressured the shared input, and starved the active swath.
> `fifo_read_control.v` was rewritten to a single-pass **all-lanes-concurrent** drain
> (`enc_pix[e] = col_w[e%N_H] · swath_h[e/N_H]`), which reduces to the previous per-lane count
> at `N_V=1` (vertical unchanged, still 9593 B).

### Block-mode size sweep (300 / 1500 / 3000) — synthesizable IP, lossless

The on-chip-ROM *demo* bitstream is BRAM-limited to 256² (a 1500² block ROM would need ~2.25 MB,
exceeding device BRAM), so larger images are validated by driving the **synthesizable IP core**
(`jls_encoder_axis` — the exact core inside every bitstream above) over its 128-bit AXIS input.
Block 4×4 is the natural fit: it only requires `W,H` divisible by 4 (300/1500/3000 all qualify),
and every per-lane strip width (75 / 375 / 750) stays within the encoder's `LB_DEPTH=1024` line
buffer, so no resynthesis is needed.

| Image | Grid | Per-lane block | Output bytes | Ratio | Lossless (grid reassembly) |
|---|---|---|---|---|---|
| 300 × 300   | 4×4 | 75 × 75   | 12,650    | 7.11:1 | exact match |
| 1500 × 1500 | 4×4 | 375 × 375 | 540,125   | 4.17:1 | exact match |
| 3000 × 3000 | 4×4 | 750 × 750 | 1,884,408 | 4.78:1 | exact match |

Feeds generated with `make_strided_hex.py world_gray_<N>x<N>.pgm blk4x4_<N>.hex 4 4`; verified
with `verify_lossless.py … 4 4`. Throughput remains 512 MB/s (16 lanes × 32 MHz) at every size.

> **Divisibility note.** The 16-lane single-direction modes need one dimension divisible by 16:
> vertical needs `W % 16 == 0`, horizontal needs `H % 16 == 0`. 300/1500/3000 are **not** ÷16,
> so those sizes are exercised in **block 4×4** (÷4), which covers all three exactly. To run them
> vertical/horizontal you would crop to the nearest ÷16 (e.g. 300→288, 1500→1488, 3000→2992).

### 5000-scale sweep (all three directions) + real max throughput

All three split directions verified lossless at ~5000 scale (16-lane AXIS-fed IP, grid
reassembly). Vertical/horizontal need a dimension ÷16 → run at 4992² (nearest multiple of 16);
block needs ÷4 → runs at native 5000². `LB_DEPTH` raised to 8192 for the sims (horizontal's
full-width 4992 strips; block's 1250 strips).

| Mode | Image | Per-lane sub-image | Output bytes | Ratio | Lossless |
|---|---|---|---|---|---|
| Vertical 16×1 | 4992×4992 | 312×4992 | 5,730,774 | 4.35:1 | exact |
| Horizontal 1×16 | 4992×4992 | 4992×312 | 5,816,262 | 4.28:1 | exact |
| Block 4×4 | 5000×5000 | 1250×1250 | 5,776,389 | 4.33:1 | exact |

The three agree within ~1.6 % (block *area* dominates, not aspect ratio).

**Real maximum synthesizable throughput (fmax sweep, vertical = tightest-slack = floor for all
modes).** MMCM reconfigured to 1:1 clocks above 32 MHz, re-implemented through route each time:

| Clock | Encoder WNS | Result | Throughput (16 lanes) |
|---|---|---|---|
| 42.1 MHz | +1.643 ns | closes | 673.7 MB/s |
| 44.4 MHz | +0.369 ns | closes | 711.1 MB/s |
| 47.1 MHz | +0.325 ns | closes | 752.9 MB/s |
| 50.0 MHz | +0.268 ns | closes | 800.0 MB/s |
| **53.3 MHz** | **+0.159 ns** | **closes (max)** | **853.3 MB/s ≈ 6.83 Gb/s** |
| 57.1 MHz | −1.018 ns | fails | — |
| 61.5 MHz | −2.365 ns | fails | — |

**fmax = 53.33 MHz → real max ≈ 853 MB/s ≈ 6.83 Gb/s** (0 failing endpoints; +67 % over the
512 MB/s shipped design point). Script: `build_fmax_wide.tcl -tclargs <DIV>` (f = 800/DIV).
See `docs/RTL_HW_IMPLEMENTATION.md` for the full RTL + HW reference.
