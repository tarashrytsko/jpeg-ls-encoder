# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Xilinx Vivado FPGA project implementing a **JPEG-LS lossless/near-lossless image encoder** with a parallel 3-encoder architecture. Target device: Xilinx Artix-7 (xc7a200tfbg676-2).

Standard: JPEG-LS (ISO/IEC 14495). Test images use `.pgm` (Netpbm P5) format; output is `.jls` bitstream.

## Build & Simulation

This project uses the **Vivado GUI/TCL flow** — there is no Makefile or CMake.

**Open project:**
```
vivado JPEG_ENC_8f.xpr
```

**Run synthesis (TCL console inside Vivado):**
```tcl
launch_runs synth_1
wait_on_run synth_1
```

**Run implementation:**
```tcl
launch_runs impl_1 -to_step write_bitstream
wait_on_run impl_1
```

**Run simulation (xsim):**
```tcl
launch_simulation
run all
```

Simulation scripts for other simulators (modelsim, questa, activehdl, riviera) are in `JPEG_ENC_8f.ip_user_files/sim_scripts/`.

**Single testbench run from command line:**
```bash
xsim JPEG_ENC_8f.sim/sim_1/behav/xsim/tb_jls_encoder.wdb -R
```

## Source Layout

```
JPEG_ENC_8f.srcs/
  sources_1/new/        ← Active user modules (edit these)
  sources_1/imports/    ← Legacy imported modules
  sim_1/imports/        ← Testbench
  constrs_1/imports/new/top_jls_vertical.xdc  ← Pin/timing constraints
JPEG_ENC_8f.gen/        ← Generated IP (BRAM, FIFO, Clock Wizard) — do not edit
JPEG_ENC_8f.runs/       ← Build artifacts
```

## Architecture

### Encoding Pipeline

```
External pixels
      │
      ▼
block_split.v          ← Maps (x,y) coordinates → encoder block index
      │
      ▼ (3 streams)
fifo_wrapper_input.v   ← 3× async input FIFOs (CDC: wr_clk → rd_clk)
      │
      ▼
fifo_read_control.v    ← FSM gating FIFO reads: SOF→READ→GAP→DONE
      │
      ▼
encoder_wrapper.v      ← Instantiates N_E=3 jls_encoder2 cores
      │
      ▼ (3 streams)
fifo_wrapper_output.v  ← 3× async output FIFOs (16-bit compressed words)
      │
      ▼
Compressed JPEG-LS bitstream (3 parallel segments)
```

`image_generator.v` provides test pixels from a BRAM (`blk_mem_gen_0`) during simulation. `fifo_reset_bram_async.v` sequences FIFO resets against clock lock, asserting `sys_rdy` when safe to start.

### jls_encoder2.v — Core Algorithm (1392 lines)

The heart of the design. Implements a **10-stage pipeline** processing one pixel per clock cycle:

| Stage | Function |
|-------|----------|
| A | Pixel coordinate generation (ii, jj) |
| B | Line/frame flags (fc, lc, nfr) |
| C | Line buffer read → context pixels (a, b, c, d) |
| D | Context fixup, quantized prediction (qp1) |
| E | Error computation and reconstruction loop |
| F | Context RAM update (N, B, C tables); run/regular decision; Golomb k |
| G | Golomb coding |
| H | Bitstream merge (57-bit shift register) |
| J | Byte output with 0xFF stuffing |
| K | JPEG-LS header/footer insertion (FFD8/FFD9 markers) |

Key parameters:
- `NEAR` — 0 = lossless, 1–7 = near-lossless tolerance
- `N_E` — number of parallel encoders (default 3)
- `L` — slice height in lines (default 64)
- 366 contexts per encoder, each holding N/A/B/C tables

### Block Geometry

The image is divided into a **3×3 grid** (3 horizontal × 3 vertical blocks). The 9 blocks are distributed across 3 encoders. `fifo_write_control.v` maps pixel (x,y) → encoder block and tracks exact pixel counts per slice. `fifo_read_control.v` mirrors this on the read side.

### Synthesizable AXI4-Stream IP (real hardware)

The design is now a **synthesizable AXI4-Stream IP**, `jls_encoder_axis` (the former
`top_jls_vertical`), and a self-contained bitstream wrapper `jls_demo_top`:

- `jls_encoder_axis` — AXIS **slave** (8-bit pixel in: `s_axis_tdata/tvalid/tready/tlast`)
  + N_E AXIS **masters** (16-bit compressed out), with sideband `i_w`/`i_h`/`i_sof`.
  **Lossless only** (`NEAR` fixed at 0; no near-lossless port). The sim-only file reader
  `image_generator` is replaced by `axis_pixel_in` (AXIS slave → splitter, same FSM); the
  output FIFO drain (`fifo_wrapper_output`) is a proper AXIS master with `tready`
  backpressure (one read outstanding, lossless under stall).
- `jls_demo_top` — synthesis/impl top: an on-chip `axis_image_source` (BRAM/`$readmemh`
  ROM, 64×64) feeds the IP; compressed output goes to pins. Real I/O is only the diff
  clock (R3/P3), reset (R8), and the `o_e`/`o_last`/`o_data` outputs (XDC:
  `constrs_1/imports/new/jls_demo_top.xdc`). See `output_block/BENCHMARKS.md`.
- The testbench `tb_jls_encoder_axis` drives the AXIS slave from a PGM; `tb_jls_demo_top`
  simulates the full harness (its output is byte-identical to the AXIS path).

### Clock Domains

Two synthesizable configurations exist; both use `clk_wiz_0` (MMCM) clocking and the
same `jls_demo_top` harness. Pick the one that matches the lane count.

**2-lane build (N_E=2, N_H=2, N_V=1 — original)**

| Domain | Synthesizable | Usage |
|--------|---------------|-------|
| `wr_clk` (`clk`) | **60 MHz** | AXIS/IO + FIFO read side |
| `rd_clk` | **30 MHz** | Encoder operation |
| `clk_in` | 200 MHz differential | Board input → `clk_wiz_0` |

Both clocks come from `clk_wiz_0` (MMCM, VCO 990 MHz). This **timing-closed** build
runs `wr_clk` 60 MHz / `rd_clk` 30 MHz, **WNS +2.72 ns, WHS +0.095 ns** → `jls_demo_top.bit`.
All CDC uses async FIFOs + gray-code/2-FF synchronizers. The encoder *logic* has ~+11.6 ns
intra-domain slack at 30 MHz (~46 MHz headroom); the limiter at 60/30 is the cross-domain
CDC path. Throughput ≈ **60 Mpix/s ≈ 480 Mb/s** (30 MHz × 2 parallel column encoders).
Build: `build_synth.tcl` → `build_impl.tcl`; clock: `build_fmax2.tcl`.

**16-lane wide build (N_E=16, N_H=16, N_V=1 — wide configuration)**

Input is a 128-bit AXI4-Stream (16 pixels/cycle, column-strided). Clocks run 1:1
because the input bandwidth (16 px/cycle × wr_clk) equals lane consumption (16 lanes ×
1 px/cycle × rd_clk) — a 2:1 ratio floods the shallow input FIFOs and was verified to
fail. Per-lane FIFO depths were shrunk and the line buffer parameterized to strip width
(`LB_DEPTH=1024`), cutting BRAM from a naive ~860 to 40 (11%).

| Domain | Synthesizable | Usage |
|--------|---------------|-------|
| `wr_clk` = `rd_clk` | **32 MHz** | Both sides (1:1), MMCM |
| `clk_in` | 200 MHz differential | Board input → `clk_wiz_0` |

**WNS +8.25 ns, WHS +0.048 ns** (0 failing endpoints). Utilization: LUT 39576 (29.4%),
FF ~25012 (9.3%), BRAM 40 (11%), DSP 19 (2.6%). Throughput: **16 × 32 MHz = 512 Mpix/s
= 512 MB/s ≈ 4.1 Gb/s** — a genuinely synthesizable 4 Gb/s result (not the earlier
sim-only 500 MHz figure). Verified lossless via 16-strip reassembly on a 256×256 image.
Build: `build_wide_synth.tcl` → `build_impl.tcl`; clock: `clkwiz_3232.tcl`.

> The earlier **4 Gb/s @ 500 MHz** figure was a **behavioral-sim / architectural** result
> — **500 MHz is not synthesizable on Artix-7.** The 16-lane 32 MHz build above is the
> first real synthesizable path to ~4.1 Gb/s on this device.

**All three split directions are HW-proven (mode-parameterized, one RTL).** The same wide
design builds vertical / horizontal / block by setting the build-time `(N_H, N_V)` generic
(`N_H·N_V=16`) and swapping the strided input ROM — all timing-closed at 512 MB/s:

| Mode | (N_H,N_V) | WNS | LUT | BRAM | DSP | Bitstream |
|---|---|---|---|---|---|---|
| Vertical   | 16×1 | +8.25 ns  | 39576 | 40 | 19 | (baseline) |
| Horizontal | 1×16 | +8.446 ns | 39647 | 40 | 19 | `output_block/bitstreams/jls_demo_top_h1v16.bit` |
| Block      | 4×4  | +8.636 ns | 40300 | 40 | 21 | `output_block/bitstreams/jls_demo_top_h4v4.bit` |

One build entry point: `vivado -mode batch -source build_wide_mode.tcl -tclargs <N_H> <N_V>`
(vertical `16 1`, horizontal `1 16`, block `4 4`). It copies the mode ROM into `rom_wide.hex`,
sets the generic, and runs synth+impl→bitstream. Mode ROMs come from
`tools/make_strided_hex.py <in.pgm> <out.hex> <N_H> <N_V>`. The read controller drains all 16
lanes concurrently (`fifo_read_control.v`, single-pass), required because the wide splitter
feeds every lane each cycle in lockstep. **Block 4×4 size sweep** (synthesizable IP via the
AXIS harness, lossless): 300²→7.11:1, 1500²→4.17:1, 3000²→4.78:1, 5000²→4.33:1. **~5000-scale
all three directions** (lossless): vertical 16×1 @4992²→4.35:1, horizontal 1×16 @4992²→4.28:1,
block 4×4 @5000²→4.33:1 (within ~1.6%). See `output_block/BENCHMARKS.md`.
The on-chip-ROM demo bitstream is BRAM-limited to 256²; larger images drive the IP core over AXIS
(strip width ≤ `LB_DEPTH`; canonical 1024, raised to 8192 for the 5000-scale sims). Single-direction
modes need one dim ÷16 (vertical `W%16`, horizontal `H%16`); block only needs `W,H % N_H,N_V`, so
300/1500/3000/5000 use block 4×4 (÷4), and vertical/horizontal use 4992 (÷16).

**Real max synthesizable throughput.** An fmax sweep (MMCM reconfigured 1:1 above 32 MHz,
re-implemented through route, on the tightest-slack vertical config → floor for all modes) closes
at **53.33 MHz** (encoder-domain WNS +0.159 ns, 0 failing endpoints; 57.1 MHz fails). So the real
maximum is **16 × 53.33 = 853 Mpix/s ≈ 853 MB/s ≈ 6.83 Gb/s** — **+67 %** over the 512 MB/s shipped
design point. The 32 MHz point is retained for guard-band; sweep via `build_fmax_wide.tcl -tclargs
<DIV>` (f = 800/DIV). Full RTL + HW reference: `docs/RTL_HW_IMPLEMENTATION.md`.

## Key Design Constraints

- **Line buffer depth:** 16384 entries (2^14) — limits max image width.
- **Context memory:** 366 entries × (N+A+B+C fields) per encoder — sized for JPEG-LS Appendix C.
- **0xFF byte stuffing:** Required by JPEG-LS spec; handled in Stage J of the pipeline.
- **Golomb J-table:** 32-entry lookup hardcoded in the encoder.
- The XDC file maps the differential clock to pins R3/P3, single-ended clock to E17, and reset to R8.

## Optimal Encoder/Chunk Configuration

Benchmarked compression ratios for different configurations (NEAR=0 lossless, satellite imagery):

| Image Size | Encoders | Chunks | Block Size | Compression | Throughput |
|---|---|---|---|---|---|
| 1500×1500 | 3 | 4 | 500×375 | **6.87:1** | 148 Mpix/s |
| 1500×1500 | 5 | 10 | 300×150 | 2.13:1 | 150 Mpix/s |
| 3000×3000 | 3 | 4 | 1000×750 | **4.78:1** | 150 Mpix/s |
| 3000×3000 | 5 | 10 | 600×300 | 1.82:1 | 150 Mpix/s |
| 5000×5000 | 3 | 4 | 1666×1250 | **4.32:1** | 150 Mpix/s |

**Recommended configurations by image size:**

| Image Size | Best Config | Block Size | Expected Ratio |
|---|---|---|---|
| ≤3K | 3 enc × 4 chunks | ~1000×750 | 4–7:1 |
| 5K–10K | 5 enc × 4 chunks | ~1000–2000 × 1250–2500 | 3–5:1 |
| >10K | 5 enc × 8 chunks | ~2000–3000 × 1250–1875 | 3–4:1 |

**Key findings:**
- Block size > 500×500 is critical for good compression (>4:1)
- Fewer chunks = better compression (larger context windows, less header overhead)
- More encoders = faster throughput but each needs its own FIFO + encoder instance
- Sweet spot: block size ~1000×1000 gives best compression-to-resource ratio

## Splitting Modes (block / vertical / horizontal)

The split direction is just the `(N_H, N_V)` block-grid factorization, parameterized
on `top_jls_vertical`/`tb_top_jls_vertical`. With one block per encoder:
**vertical** = `N_H=N_E, N_V=1` (tall column strips); **horizontal** = `N_H=1, N_V=N_E`
(wide row strips); **block** = a roughly-square `a×b` grid (`a·b=N_E`).
Benchmark all three with `JPEG_ENC_8f.sim/sim_1/behav/xsim/run_hv_benchmark.ps1`;
verify losslessness with `verify_lossless.py`. See `output_block/BENCHMARKS.md` for
results — at equal parallelism the three directions compress within ~1% (total block
*area* dominates, not aspect ratio).

Constraint: SOF is issued once per row-swath, so an encoder emits one slice per swath.
*Vertical chunking* (multiple columns per encoder in one swath) is unsupported — vertical
runs one block per encoder only. Horizontal/block can chunk via `N_V` swaths.

## Testbench

`sim_1/imports/FPGA Encoders/tb_top_jls_vertical.v` drives the full parallel system:
- Streams pixels from PGM file via `image_generator.v` (no BRAM needed)
- Captures per-encoder JLS output files (EOI byte-detection for slice boundaries)
- Supports configurable N_E (encoders) and NUM_SLICES (chunks per encoder)
- Output files: `enc{0..N_E-1}{a..j}.jls` in `JPEG_ENC_8f.sim/output_block/`

`sim_1/imports/FPGA Encoders/tb_jls_encoder.v` drives a single encoder:
- Loads a `.pgm` file and streams pixels via AXI-Stream-like handshake (`i_e`/`i_last`).
- Configurable `NEAR` parameter and bubble insertion (randomized gaps to stress flow control).
- Captures compressed output to a `.jls` file for validation.
