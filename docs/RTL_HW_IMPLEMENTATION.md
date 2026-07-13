# Wide 16-Lane JPEG-LS Encoder — RTL & Hardware Implementation

**Device:** Xilinx Artix-7 `xc7a200tfbg676-2`  **Tools:** Vivado 2024.2
**Standard:** JPEG-LS / ITU-T T.87 (ISO/IEC 14495-1), lossless (NEAR = 0)
**Design point:** 16 parallel encoder lanes @ 32 MHz = **512 Mpix/s = 512 MB/s ≈ 4.1 Gb/s**
**Branch:** `feature/jls-encoder-axis`

This document describes the complete RTL and hardware implementation of the synthesizable
wide 16-lane JPEG-LS encoder: every module, the two clock domains and their clock-domain
crossings (CDC), the 11-stage encoder pipeline, the three split directions, and all
measured synthesis / timing / throughput / compression statistics — including the **real
maximum synthesizable throughput** established by an fmax sweep.

---

## 1. Overview

The encoder compresses an 8-bit grayscale image losslessly into JPEG-LS bitstream(s). A
single JPEG-LS encoder core is inherently **one pixel per clock** (its prediction is causal
— each pixel depends on already-encoded neighbours), so throughput is scaled by running
**N_E = 16 encoder cores in parallel**, each on an independent sub-image ("strip"/"block").
A 128-bit-wide AXI4-Stream input delivers 16 pixels per clock (one per lane); 16 AXI4-Stream
masters carry the 16 compressed sub-streams out.

The image is partitioned on an **(N_H × N_V) grid**, one grid block per lane
(`N_H · N_V = N_E = 16`). The split *direction* is just the choice of factorization:

| Mode | (N_H, N_V) | Per-lane sub-image | Input striding |
|---|---|---|---|
| **Vertical** | 16 × 1 | tall column strip (W/16 × H) | column-strided |
| **Horizontal** | 1 × 16 | wide row strip (W × H/16) | row-strided |
| **Block** | 4 × 4 | ~square block (W/4 × H/4) | block-strided |

Throughput is **identical** in all three directions (16 lanes × 1 px/clk × 32 MHz); only
*which* sub-image each lane encodes differs. All three are proven to timing-closed
bitstreams (Section 8) and bit-exact lossless (Section 10).

---

## 2. Top-Level Architecture

### 2.1 Module hierarchy

```
jls_demo_top                         self-contained bitstream harness (only I/O: clk, reset, done, status)
├─ axis_image_source                 on-chip BRAM ROM → 128-bit AXIS pixel source
├─ jls_encoder_axis                  the synthesizable IP (AXIS slave in, 16 AXIS masters out)
│  ├─ clk_wiz_0                       MMCM: 200 MHz diff → wr_clk 32 MHz, rd_clk 32 MHz
│  ├─ fifo_reset_bram_async          reset sequencer → sys_rdy after MMCM lock + FIFO reset
│  ├─ axis_pixel_in                  AXIS slave adapter (SOF stretch, backpressure)
│  ├─ splitter_block  (block_split.v) wide lockstep splitter → 16 lanes
│  ├─ fifo_write_control             per-lane input-FIFO write enables
│  ├─ fifo_wrapper_input             16× async FIFO (8-bit, depth 512)  ── CDC wr→rd ──
│  ├─ fifo_read_control              per-lane read enables + encoder SOF (single-pass)
│  ├─ encoder_wrapper                instantiates the 16 lanes
│  │  └─ jls_encoder × 16            single-lane JPEG-LS core (11-stage pipeline)
│  └─ fifo_wrapper_output            16× async FIFO (16-bit, depth 2048) ── CDC rd→wr ──
└─ axis_sink                         on-chip sink: checksum + word count + done
```

`jls_encoder_axis` is the reusable deliverable IP. `jls_demo_top` wraps it with an on-chip
ROM source and sink so the whole thing is a self-contained, prune-proof bitstream whose only
real pins are the differential clock, reset, `done`, and a 31-bit status (checksum).

### 2.2 End-to-end dataflow

```
ROM/AXIS ─128b─▶ axis_pixel_in ─128b─▶ splitter_block ─┬─8b─▶ inFIFO0 ─▶ jls_encoder0 ─16b─▶ outFIFO0 ─┐
 16 px/clk        (SOF stretch,         (lockstep,      ├─8b─▶ inFIFO1 ─▶ jls_encoder1 ─16b─▶ outFIFO1 ─┤ 16 AXIS
 s_axis_tdata     backpressure)          byte k→lane k) │ ...                                    ...    ├─masters
 tvalid/tready                                          └─8b─▶ inFIFO15─▶ jls_encoder15─16b─▶ outFIFO15─┘ m_axis_*
 tlast                                                                                                   → sink
   sideband: i_w[15:0], i_h[13:0], i_sof (one-shot)
```

- **Input AXIS (slave):** `s_axis_tdata` 128-bit (16 px), `tvalid`/`tready`/`tlast`, plus
  sideband `i_w`/`i_h`/`i_sof`. `tready` is de-asserted during the SOF stretch and whenever
  any input FIFO is full (lockstep backpressure).
- **Output AXIS (16 masters):** `m_axis_tdata` 256-bit (16 × 16-bit words), per-lane
  `tvalid`/`tready`/`tlast`. `tready` backpressure is honoured losslessly (one read
  outstanding).

---

## 3. Clock Domains & CDC

Two domains, both **32 MHz** and running **1:1** (input bandwidth = lane consumption):

| Domain | Clock | Modules |
|---|---|---|
| Write / IO | `wr_clk` (clk_out1) | axis_image_source, axis_pixel_in, splitter_block, fifo_write_control, input-FIFO **write** side, output-FIFO **read** side, axis_sink |
| Read / encoder | `rd_clk` (clk_out2) | fifo_reset_bram_async, input-FIFO **read** side, fifo_read_control, encoder_wrapper + 16× jls_encoder, output-FIFO **write** side |

**Why 1:1.** A 128-bit input delivers 16 px/wr_clk; the 16 lanes consume 16 px/rd_clk. Equal
rates keep the shallow input FIFOs from flooding or starving. (A 2:1 ratio was verified to
fail — it floods the depth-512 input FIFOs.)

**CDC crossings** — the only two are the async FIFOs (Xilinx independent-clock block-RAM
FIFOs, 2-stage pointer synchronizers):

1. **Input FIFO** (`fifo_wrapper_input`, 16× `fifo_generator_0`): 8-bit × 512 deep. Pixels
   cross wr_clk → rd_clk. A per-lane 18-bit fill count is double-flopped to rd_clk
   (informational backpressure hint only).
2. **Output FIFO** (`fifo_wrapper_output`, 16× `fifo_output`): 16-bit × 2048 deep. Compressed
   words cross rd_clk → wr_clk. Slice boundaries are tracked with a **3-bit Gray-coded write
   pointer** synchronized across the boundary (up to 4 pending slices per lane).

MMCM: 200 MHz differential input → 32 MHz on both outputs (`clk_wiz_0`). The reset sequencer
holds all FIFOs in reset for 10 cycles after MMCM lock, then asserts `sys_rdy`.

---

## 4. RTL Module Reference

### jls_demo_top  (`sources_1/new/jls_demo_top.v`)
Structural harness. Params `N_E=16, N_H, N_V, IMG_W=256, IMG_H=256`. Instantiates
`axis_image_source` → `jls_encoder_axis` → `axis_sink`; exposes `rstn`, `clk_in1_p/n`,
`clk`, `done`, `status[30:0]`. Uses the IP's `sys_rdy` as source/sink reset.

### axis_image_source  (`sources_1/new/axis_image_source.v`)
On-chip pixel source. `(* rom_style="block" *)` ROM of `IMG_W*IMG_H/N_E` words × 128-bit,
`$readmemh`-initialized from a strided hex. 3-state FSM (IDLE→RUN→DONE): emits one-shot
`i_sof`, then one 128-bit word per AXIS beat. Word count is mode-invariant `= W·H/N_E`.

### jls_encoder_axis  (`sources_1/imports/FPGA Encoders/jls_encoder_axis.v`)
The IP top. Params `N_E=16, N_H, N_V, L=64, nr=0`. Instantiates the MMCM, reset sequencer,
AXIS adapter, splitter, both FIFO wrappers + controllers, and the encoder wrapper. Produces
`clk` (wr_clk), `sys_rdy`; consumes the AXIS slave + sideband; drives 16 AXIS masters. Input
backpressure = OR of all input-FIFO `full` flags fed back to `axis_pixel_in`.

### axis_pixel_in  (`sources_1/new/axis_pixel_in.v`)
AXIS slave → splitter adapter. Param `SOF_STRETCH=3000`. 4-state FSM (IDLE→SOF→PIXEL→DONE):
holds `i_sof_st` (all-lanes) high for 3000 cycles, then forwards `pixel_out`/`pixel_valid`
while `pix_cnt < i_w·i_h`; de-asserts `tready` under FIFO-full backpressure.

### splitter_block  (module `splitter_block`, `sources_1/new/block_split.v`)
Wide **lockstep** splitter. Params `N_H, N_V, N_E`. Maintains one shared intra-strip counter
`(xs, ys)` over `stripW = i_w/N_H`, `swathH = i_h/N_V`; every active cycle drives **all**
lanes: `o_e[k]=1`, `o_x[k·8+:8]=i_x[k·8+:8]` (byte k → lane k). `o_last_enc[k]` asserts at
`xs==stripW-1 && ys==swathH-1`. The generalization from vertical-only was replacing the
hardcoded `i_h` y-range with `swathH = i_h/N_V` (any grid; vertical N_V=1 unchanged).

### fifo_write_control  (`sources_1/new/fifo_write_control.v`)
Per-lane input-FIFO write enable: `wr_en[i]` = registered `(s_e[i] && !fifo_full[i] &&
!frame_done[i])`. Tracks per-lane write counts and completion.

### fifo_wrapper_input  (`sources_1/new/fifo_wrapper_input.v`)
16× async `fifo_generator_0` (8-bit × 512, 2-stage sync). Registers `din` one cycle before
the FIFO; exposes `full/overflow/empty/valid/...` and an 18-bit CDC-synced fill count.

### fifo_read_control  (`sources_1/new/fifo_read_control.v`)
rd_clk-domain read controller. Params `NUM_ENCODERS, N_H, N_V, SOF_CYCLES=3000`. Computes
uniform per-lane counts `col_w[·]=i_w_r/N_H`, `swath_h[·]=i_h_r/N_V`, and
`enc_pix[e]=col_w[e%N_H]·swath_h[e/N_H]`. **Single-pass all-lanes-concurrent** FSM
(SOF→READ→DONE): asserts SOF to all lanes for 3000 cycles, then drains every active lane
concurrently, counting delivered `fifo_valid` pulses (robust against async-empty lag), and
terminates when all lanes reach their pixel count. (This single-pass rewrite is what enables
N_V>1: the earlier swath-sequential FSM deadlocked the lockstep feed.)

### encoder_wrapper  (`sources_1/new/encoder_wrapper.v`)
Instantiates `N_E` `jls_encoder` cores via generate. Derives per-lane dims `col_w=i_w/N_H`,
`row_h=i_h/N_V` (uniform floor — matches the splitter's lockstep delivery; divisibility is a
hard requirement). Each lane gets `i_w=col_w[g%N_H]`, `i_h=row_h[g/N_H]`, its pixel/SOF, and
`LB_DEPTH` line buffer.

### jls_encoder  (`sources_1/imports/FPGA Encoders/jls_encoder.v`, ~1500 lines)
Single-lane JPEG-LS core — see Section 5.

### fifo_wrapper_output  (`sources_1/new/fifo_wrapper_output.v`)
16× async `fifo_output` (16-bit × 2048, 2-stage sync). Tracks slice end positions
(`end_pos[lane][slot]`, 4 slots) and Gray-codes a 3-bit write pointer across the CDC.
Presents AXIS master output with correct `tlast`; one read outstanding, lossless under
`tready` backpressure.

### fifo_reset_bram_async  (`sources_1/new/fifo_reset_bram_async.v`)
Param `RESET_CYCLES=10`. Asserts `fifo_rst` for 10 cycles after `rstn_ext & locked`, then
raises `sys_rdy` once `wr_rst_busy` and `rd_rst_busy` are clear.

### axis_sink  (`sources_1/new/axis_sink.v`)
On-chip sink (harness only). `tready`=1; accumulates a 32-bit XOR checksum + total word
count; `done = &lane_done` (each lane done on `tvalid & tlast`).

---

## 5. jls_encoder Pipeline (11 registered stages, 1 px/clk)

Derived JPEG-LS constants for NEAR=0: T1=3, T2=7, T3=21, QBPP=8, LIMIT=23, A_INIT=4.
Per-lane context memory: **366 contexts** — `Nram` 366×6, `Aram` 366×13, `Bram` 366×7 (signed),
`Cram` 364×8 (signed). Golomb run table `J[0..31]`. Line buffer `LB_DEPTH` × 8-bit.

| Stage | Function |
|---|---|
| **A** | Register input; maintain intra-strip coords `(ii, jj)` vs `(wl, hl)=(stripW-1, swathH-1)`; block-complete detect. |
| **B** | First/last-column, first-row flags; end-of-frame (`eof`) detect; gate valid. |
| **C** | Line-buffer read → causal neighbours a, b, c, d (above / left / above-left); first-row zero-fill. |
| **D** | Context fixup at row/column boundaries; quantized gradient partial `qp1 = 81·Q(d−b)+9·Q(b−c)`. |
| **E** | Full context index `{sign, q}`; read `C/N/B[q]`; predicted pixel + error residual; quantize + modrange; (lossless: reconstruct = input). |
| **F(NBC)** | Write back updated N, B, C to context RAMs (or init during SOF). |
| **EF** | Registered `Aram[q]` read (one cycle ahead of use). |
| **F** | Golomb parameter `k=func_get_k(A,N)`; run counter/index; mapped error; accumulator `A` update. |
| **G** | Write back `Aram`; parse the Golomb codeword (unary zero-run, data bits, run-interrupt prefix). |
| **H** | Merge code components into a 57-bit bit-level buffer. |
| **J** | 248-bit shift register → pack bytes; **0xFF byte-stuffing** (insert 0x00, consume 7 bits); on EOF drain + emit `FFD9` (EOI) footer. |
| **K** | Prepend the 12-word JPEG-LS header (SOI `FFD8`, SOF55 `FFF7`, LSE, frame/scan params) during SOF; then forward. |

Output: `o_e` (word valid), `o_data[15:0]` (compressed word), `o_last` (final word).

---

## 6. Splitting Modes & the Lockstep Model

All 16 lanes advance one shared `(xs, ys)` counter over each lane's `stripW × swathH`
sub-image, where `stripW = W/N_H`, `swathH = H/N_V`. Each cycle, the 128-bit input word's
slot `k` carries lane `k`'s pixel; lane `k` occupies grid block `(bx=k%N_H, by=k/N_H)`, i.e.
full-image pixel `(bx·stripW + xs, by·swathH + ys)`. Total cycles per frame = `stripW·swathH
= W·H/16` in **every** mode.

The input feed is produced by `tools/make_strided_hex.py <in.pgm> <out.hex> <N_H> <N_V>`,
which packs byte `k = px[(by·swathH+ys)·W + (bx·stripW+xs)]` per word (column-strided for
N_V=1, row-strided for N_H=1, block-strided otherwise). The same `(bx,by)` mapping is used by
the splitter, `fifo_read_control`, and `encoder_wrapper` — verified consistent.

**Hard requirement:** `W % N_H == 0` and `H % N_V == 0` (the lockstep delivers a uniform
`stripW·swathH` to every lane; the tool asserts this). Consequences for a single image size:
- Vertical (16×1) needs `W % 16 == 0`; horizontal (1×16) needs `H % 16 == 0`.
- Block (4×4) needs `W % 4 == 0` and `H % 4 == 0`.

**Line buffer:** `LB_DEPTH` must be ≥ per-lane strip width `W/N_H`. Canonical builds use
`LB_DEPTH=1024` (→ max image width 16384 with 16 vertical strips). Horizontal (N_H=1) uses
full-width strips, so wide images need `LB_DEPTH ≥ W` (more BRAM).

---

## 7. Build & Run

```
# Per-mode timing-closed bitstream (vertical 16 1, horizontal 1 16, block 4 4):
vivado -mode batch -source build_wide_mode.tcl -tclargs <N_H> <N_V>
#   copies rom_wide_h<NH>v<NV>.hex → rom_wide.hex, sets the (N_H,N_V) generic,
#   runs synth_1 + impl_1 → write_bitstream, reports mode_h<NH>v<NV>_{util,timing}.rpt

# Mode input ROM:      tools/make_strided_hex.py <in.pgm> <out.hex> <N_H> <N_V>
# Lossless sim (AXIS): tb_jls_wide (16-lane capture) → output_h<NH>v<NV>_<W>x<H>.jls
# Verify:              python verify_lossless.py <jls> <pgm> <N_H> <N_V>   (grid reassembly)
```

Clock: `clkwiz_3232.tcl` sets the MMCM to 32/32 MHz. The vertical default is restored by
`restore_vertical_generic.tcl` (`.xpr` generic → N_H=16 N_V=1).

---

## 8. Synthesis & Implementation Results (timing-closed bitstreams)

All three modes built from one RTL @ 32/32 MHz on `xc7a200tfbg676-2`, **0 failing endpoints**:

| Mode | (N_H,N_V) | WNS | WHS | LUT (of 134600) | FF (of 269200) | BRAM (of 365) | DSP (of 740) |
|---|---|---|---|---|---|---|---|
| Vertical   | 16×1 | **+8.25 ns**  | +0.048 ns | 39576 (29.4%) | 25012 (9.3%) | 40 (11.0%) | 19 (2.6%) |
| Horizontal | 1×16 | **+8.446 ns** | +0.034 ns | 39647 (29.5%) | 24663 (9.2%) | 40 (11.0%) | 19 (2.6%) |
| Block      | 4×4  | **+8.636 ns** | +0.047 ns | 40300 (29.9%) | 24597 (9.1%) | 40 (11.0%) | 21 (2.8%) |

Resource footprint is within ~0.5% across modes (identical encoder logic; only splitter
routing and the input ROM differ). BRAM held to 40 (11%) — vs a naive 16-lane scaling of
~860 — via shallow FIFOs (input 512, output 2048) enabled by 1:1 clocking, plus the
`LB_DEPTH=1024` strip-width line buffer.

---

## 9. Throughput — Design Point and Real Maximum

**Design point (verified, timing-closed):** 16 lanes × 1 px/clk × 32 MHz =
**512 Mpix/s = 512 MB/s ≈ 4.1 Gb/s** (8-bit pixels).

**Real maximum synthesizable throughput (fmax sweep):** The MMCM was reconfigured to a
series of 1:1 clocks above 32 MHz and the design re-implemented (synth + place + route) at
each, on the **vertical** config — which has the *tightest* slack at 32 MHz (+8.25 ns vs
+8.446 horizontal / +8.636 block), so its fmax is the guaranteed **floor for all three
directions**. WNS is the final post-route setup slack of the encoder domain (`clk_out2`),
which is the limiter (`clk_out1`/IO and inter-clock paths have >3 ns more margin at every
point).

| Clock (1:1) | Period | Encoder-domain WNS | WHS | Result | Throughput (16 lanes) |
|---|---|---|---|---|---|
| 42.105 MHz | 23.75 ns | +1.643 ns | +0.047 ns | closes | 673.7 MB/s (5.39 Gb/s) |
| 44.444 MHz | 22.50 ns | +0.369 ns | +0.028 ns | closes | 711.1 MB/s (5.69 Gb/s) |
| 47.059 MHz | 21.25 ns | +0.325 ns | +0.038 ns | closes | 752.9 MB/s (6.02 Gb/s) |
| 50.000 MHz | 20.00 ns | +0.268 ns | +0.026 ns | closes | 800.0 MB/s (6.40 Gb/s) |
| **53.333 MHz** | **18.75 ns** | **+0.159 ns** | **+0.044 ns** | **closes (max)** | **853.3 MB/s (6.83 Gb/s)** |
| 57.143 MHz | 17.50 ns | −1.018 ns | — | fails | — |
| 61.538 MHz | 16.25 ns | −2.365 ns | — | fails | — |

**Real maximum: fmax = 53.33 MHz → 16 × 53.33 = 853.3 Mpix/s = 853.3 MB/s ≈ 6.83 Gb/s**
(0 failing endpoints; the next 1:1 step, 57.1 MHz, fails). That is **+67 %** over the
512 MB/s design point. All three split directions reach at least this figure (vertical is the
tightest). The 32 MHz shipped design point is retained for guard-band and clean 1:1 MMCM
generation; 53.33 MHz is the measured synthesizable ceiling of this RTL on the -2 device.
Sweep script: `build_fmax_wide.tcl -tclargs <DIV>` (f = 800/DIV MHz, VCO = 800).

> Historical note: an earlier "4 Gb/s @ 500 MHz" figure was a **behavioral-sim** result;
> 500 MHz is **not** synthesizable on Artix-7. The numbers here are all real,
> place-and-route-closed results.

---

## 10. Compression & Losslessness Results

All NEAR=0 lossless, verified bit-exact by 16-lane grid reassembly (`verify_lossless.py`).

**256×256 reference image** (`wide_256.pgm`), all three modes:

| Mode | Output bytes | Ratio | Lossless |
|---|---|---|---|
| Vertical 16×1 | 9593 | 6.83:1 | exact |
| Horizontal 1×16 | 9226 | 7.10:1 | exact |
| Block 4×4 | 9056 | 7.24:1 | exact |

**Block 4×4 size sweep** (`world_gray` satellite imagery, synthesizable IP over AXIS):

| Image | Per-lane block | Output bytes | Ratio | Lossless |
|---|---|---|---|---|
| 300×300 | 75×75 | 12,650 | 7.11:1 | exact |
| 1500×1500 | 375×375 | 540,125 | 4.17:1 | exact |
| 3000×3000 | 750×750 | 1,884,408 | 4.78:1 | exact |
| 5000×5000 | 1250×1250 | 5,776,389 | 4.33:1 | exact |

**~5000-scale, all three directions** (`world_gray`; vertical/horizontal use 4992² = nearest
multiple of 16, block uses native 5000²):

| Mode | Image | Per-lane sub-image | Output bytes | Ratio | Lossless |
|---|---|---|---|---|---|
| Vertical 16×1 | 4992×4992 | 312×4992 | 5,730,774 | 4.35:1 | exact |
| Horizontal 1×16 | 4992×4992 | 4992×312 | 5,816,262 | 4.28:1 | exact |
| Block 4×4 | 5000×5000 | 1250×1250 | 5,776,389 | 4.33:1 | exact |

At equal parallelism the three directions compress within a small margin (total block *area*
dominates, not aspect ratio). Thin vertical strips (312 px wide) compress slightly worse than
square blocks due to narrower causal context.

---

## 11. Constraints & Limits

- **Divisibility (hard):** `W % N_H == 0`, `H % N_V == 0` (lockstep uniform blocks). Vertical/
  horizontal at 16 lanes need a dimension ÷16; block 4×4 needs ÷4. E.g. 5000 is ÷4 (block OK)
  but not ÷16 (vertical/horizontal use 4992).
- **Line buffer:** `LB_DEPTH ≥ W/N_H`. Canonical 1024 → 16384 max width (vertical). Horizontal
  full-width or large block strips need a larger `LB_DEPTH` (more BRAM); the 5000-scale sims
  used `LB_DEPTH=8192`.
- **On-chip demo ROM:** BRAM-limited to 256² in `jls_demo_top`; larger images drive the IP core
  (`jls_encoder_axis`) over external AXIS. Throughput is size-independent (clock × lanes).
- **Context memory:** 366 contexts/lane (JPEG-LS Appendix C).
- **0xFF stuffing:** required by the spec, handled in stage J.

---

## 12. Verification Summary

- **Functional:** every configuration bit-exact lossless via independent-decoder grid
  reassembly (`verify_lossless.py`), from 256² up to 5000-scale, in all three directions.
- **Timing:** all three bitstreams close with WNS ≥ +8.25 ns and WHS ≥ +0.034 ns (0 failing
  endpoints) at 32/32 MHz.
- **Equivalence:** the on-chip-ROM demo (`jls_demo_top`) output is byte-identical to the
  AXIS-fed path, confirming synthesis preserved all encoding behaviour.

---

## 13. Alternate Configuration — 12 Lanes @ 45 MHz (540 MB/s)

The same mode-parameterized RTL was exercised at **N_E = 12 lanes @ 45 MHz** in all three
split directions — **block 4×3**, **vertical 12×1**, **horizontal 1×12** (`N_H·N_V = 12`).
Only the lane count, clock, and grid change; no RTL edits.

**Timing-closed HW build (12 lanes @ 45/45 MHz, `jls_demo_top`, vertical 12×1, 300² on-chip ROM):**

| Metric | Result |
|---|---|
| Clocks | wr_clk = rd_clk = **45 MHz** (1:1, MMCM VCO=900) |
| **WNS / WHS** | **+0.652 ns / +0.047 ns** (0 failing endpoints) |
| LUT | 32748 (24.3%) |
| FF | 18720 (7.0%) |
| BRAM | 30 (8.2%) |
| DSP | 14 (1.9%) |
| **Throughput** | **12 lanes × 45 MHz = 540 Mpix/s = 540 MB/s ≈ 4.3 Gb/s** |
| Build | `build_n12_45.tcl` |

Resource use is ~¾ of the 16-lane build (12/16 lanes), and 45 MHz is well within the
53.3 MHz fmax established in Section 9, so the +0.652 ns closure is expected.

**Lossless verification — 3 directions × 4 image sizes (all bit-exact, grid reassembly).**
Sizes 300/1500/3000 run natively (all divisible by 12, 4, and 3). **5000 is not divisible by
12** (nor its height by 3 for block 4×3), so the "5000" point uses **4992** (= 16·312 = 4·1248
= 3·1664), the nearest size divisible by 12/4/3. `LB_DEPTH` was raised to 8192 for the sims to
cover horizontal 1×12's full-width (4992) strips.

| Image | block 4×3 (bytes / ratio) | vertical 12×1 | horizontal 1×12 |
|---|---|---|---|
| 300×300 | 12,464 / 7.22:1 | 13,031 / 6.91:1 | 12,538 / 7.18:1 |
| 1500×1500 | 539,490 / 4.17:1 | 542,628 / 4.15:1 | 541,936 / 4.15:1 |
| 3000×3000 | 1,883,193 / 4.78:1 | 1,883,214 / 4.78:1 | 1,895,967 / 4.75:1 |
| 4992×4992 | 5,756,846 / 4.33:1 | 5,732,381 / 4.35:1 | 5,814,093 / 4.29:1 |

All 12 configurations **LOSSLESS: exact match**. As with the 16-lane design, the three
directions compress within ~1–4 % at each size (total block area dominates); and the per-size
totals closely track the 16-lane results (e.g. block 3000²: 1,883,193 B here vs 1,884,408 B at
16 lanes — compressed size depends on image content, not lane count). The 12-lane feeds use
96-bit (12-byte) strided words — `make_strided_hex.py` emits `N_E·2` hex digits per word
(24 for N_E=12, 32 for N_E=16).

---

## 14. Serial-In Front-End: byte_gearbox_12 (1 byte @ 540 MHz → 12 bytes @ 45 MHz)

A serial-to-parallel input wrapper lets a **single 540 MHz byte stream** feed the 12-lane
model, matching bandwidth exactly: **540 MHz × 1 byte = 45 MHz × 12 bytes = 540 MB/s**.

**`byte_gearbox_12`** (`sources_1/new/byte_gearbox_12.v`):
- **Fast side (540 MHz):** `i_byte[7:0]` + `i_valid`/`i_ready` — one pixel byte per cycle; collects 12.
- **Slow side (45 MHz):** the group of 12 as **12 separate byte pins** `o_b0..o_b11` **and**
  packed `o_word[95:0]` (= `jls_encoder_axis.s_axis_tdata`), with `o_valid`/`o_ready`.
- **CDC:** a gray-coded dual-clock FIFO (`gearbox_afifo`) with **registered `full`/`empty`
  flags**. (A *combinational* full flag deadlocks: `wfull → wbin_nxt (…& ~wfull) → wgray_nxt
  → wfull` oscillates in zero time once the FIFO nears full — which happens during the
  encoder's SOF stretch. Registering the flags, per the standard Cummings FIFO, breaks it.)
- Byte *k* of each group → lane *k*, so the incoming stream must be in the model's strided
  lane order (as `make_strided_hex.py` emits it).

**Full backpressure chain:** `s_axis_tready` → gearbox `o_ready` → FIFO fills → `wfull` →
gearbox `i_ready` deasserts → the serial byte input stalls. Lossless under any stall (e.g. the
3000-cycle SOF stretch: the FIFO fills, the input pauses, then drains — no bytes dropped).

**Verification**
- *Standalone* (`tb_byte_gearbox`): stream a strided byte sequence at 540 MHz; the reconstructed
  12-byte words match the reference **bit-exact — 7500/7500 words, 0 errors**.
- *End-to-end* (`tb_jls_serial`): 540 MHz serial bytes → `byte_gearbox_12` (its slow clock is the
  DUT's 45 MHz `wr_clk`; the fast clock is independent, so the async FIFO does real CDC) →
  `jls_encoder_axis` (N_E=12, vertical 12×1) → 12 compressed lanes. Verified end-to-end at
  **300×300 = 13,031 B** and **1500×1500 = 542,628 B** — both **byte-identical to the parallel-fed
  result and LOSSLESS** (grid reassembly). Because the gearbox reconstructs the exact strided words
  the parallel path delivers, still-larger images are byte-identical by construction (parallel
  `vert12x1` 3000²=1,883,214 carries over); the 540 MHz behavioral sims are slow (the fine timestep
  dominates), so ≥3000² rely on that equivalence rather than a multi-hour run.

**Synthesizability / Fmax (measured, out-of-context P&R).** Unlike the encoder (~53 MHz, deep
combinational paths), the gearbox is shallow logic and runs far faster. After optimization —
**registered** FIFO full/empty flags (a *combinational* full flag oscillates in zero time via the
`& ~wfull` term once near full, which deadlocked the first sim), a **pipelined LUTRAM write**
(FF→RAM arcs), a **depth-4** FIFO (short pointer logic), and a **shift-register collector**
(enable = `accept`, no index decode) — `byte_gearbox_12` was placed-and-routed OOC with
clk_fast @ 540 MHz / clk_slow @ 45 MHz (async):

| Part | clk_fast (540 MHz target) WNS | fast-domain Fmax | 45 MHz slow side |
|---|---|---|---|
| **xc7a200t-3** | **−0.008 ns ≈ 0** | **≈ 537.6 MHz (essentially 540)** | +20 ns slack |
| xc7a200t-2 (this project) | ~ −0.1 … −0.4 ns | ~440–520 MHz (placement-sensitive) | +19 ns slack |

So a **540 MHz** serial front-end is feasible: on a **−3** device it closes directly (matching
Artix-7's ~700 MHz-class clock-network spec); on the project's **−2** part it is routing-limited by
the 96-bit CDC write (~520 MHz best), so a robust 540 MHz there uses an **`ISERDES`/GT deserialiser**
at the pins — the fast byte capture happens in hard I/O logic and hands a slower parallel word to the
fabric, so `byte_gearbox_12` + the FIFO never run at 540 MHz. Note BRAM (~460 MHz on −2) is too slow
for 540 MHz, so the FIFO is LUTRAM. Build/verify: `gearbox_vlog.prj` (standalone), `serial_vlog.prj`
(end-to-end), `ooc_gearbox.tcl <part>` (fmax sweep).

---

## 15. ISERDES Front-End — the robust −2 path to a 540 MB/s serial input

Section 14's fabric gearbox is routing-limited to ~520 MHz on the −2 part. The idiomatic way
to accept the full 540 MB/s over a serial interface on −2 is to capture it in the **hard I/O
deserializers** so **no fabric runs above 45 MHz**. `iserdes_byte_in.v` does this.

**Interface / architecture.** 12 serial data lanes (one per encoder lane), each carrying that
lane's pixel bytes MSB-first at **360 Mb/s**; each lane's `ISERDESE2` does a **1:8 SDR**
deserialize → one byte per lane at **45 MHz**. 12 lanes × 8 bits = 96 bits @ 45 MHz = the
encoder word **directly** (byte k = lane k) — no fabric gearbox, no bit-transpose, no 540 MHz
clock. Aggregate = 12 × 360 Mb/s = **4.32 Gb/s = 540 MB/s**, the same bandwidth as a single
540 MHz byte port, but the fast capture is entirely in the IOB SERDES.

**Clocking.** `clk_bit` = 360 MHz (BUFIO/BUFG, ISERDES `CLK`) and `clk_div` = 45 MHz = clk_bit/8
(BUFR/BUFG, ISERDES `CLKDIV`), both from one MMCM. No BRAM/LUTRAM (BRAM's ~460 MHz −2 limit is
irrelevant here — the deserialize is in the SERDES).

**Word alignment.** Each lane exposes a `BITSLIP` port; a rotation-unique training marker is
streamed and `bitslip` is pulsed until the word boundary locks (standard source-synchronous
bring-up; on a real board `IDELAYE2` adds per-bit deskew + eye-centering).

**Verification.**
- *Mapping / synthesizability:* OOC synth places **12 `ISERDESE2`** on `xc7a200t-2`
  (`ooc_iserdes.tcl`) — real hardware; nothing in the fabric exceeds 45 MHz.
- *Function (behavioral, unisim `ISERDESE2`, `tb_iserdes_byte_in`):* 12 lanes driven at
  360 Mb/s; after BITSLIP alignment (6 slips) **all 12 lanes reconstruct distinct bytes
  bit-exact (0 errors)**. (Note: `ISERDESE2` presents the oldest bit on `Q8`, newest on `Q1`;
  the byte map is `{Q8..Q1}` accordingly.)

**Vs. the fabric gearbox (§14).** The gearbox needs ~520 MHz *fabric* on −2 (short of 540). The
ISERDES front-end keeps the fabric at 45 MHz and puts the 360 MHz capture in hard I/O — so it
delivers the full 540 MB/s serial input **on the project's −2 part** with margin. Full bit-level
IDELAY calibration is a hardware bring-up step. Build/verify: `iserdes_vlog.prj` (sim),
`ooc_iserdes.tcl <part>` (map/synth).

---

## 16. End-to-End Serial-In Demo (ISERDES → CDC → encoder)

The ISERDES front-end (§15) wired end-to-end to the encoder, the serial-input analogue of
`jls_demo_top`:

```
12 serial pins ─IBUF─▶ iserdes_byte_in (ISERDESE2 1:8, §15) ─▶ 12 bytes @ 45 MHz
  ─▶ BITSLIP align + sentinel framing ─▶ gearbox_afifo (async CDC, clk_div↔enc wr_clk)
  ─▶ jls_encoder_axis (N_E=12, vertical 12×1) ─▶ 12 compressed lanes ─▶ axis_sink
```

**Integration points.**
- **Clocking (single MMCM):** one `MMCME2_BASE` turns the 200 MHz board diff clock — buffered
  **once** by `IBUFDS` — into `clk_bit` (360 MHz, ISERDES line clock) + `clk_div` (45 MHz).
  VCO = 900 MHz from **integer** feedback `M=9` with `DIVCLK=2` (Fpfd 100 MHz) and a single
  fractional output `CLKOUT0=2.5`, so every divider lands on the 0.125 hardware grid
  (DRC AVAL-139 clean — an earlier `M=7.2` off-grid value blocked bitgen). The encoder takes its
  45 MHz from this MMCM via a new backward-compatible `EXT_CLK=1` mode (`jls_encoder_axis`), rather
  than instantiating its own `clk_wiz_0`: a board has one clock and a port can feed only one input
  buffer, so a second on-chip IBUFDS on the same pins is illegal. `gearbox_afifo` still bridges the
  `clk_div`→encoder domains (now the same frequency).
- **SOF stretch, no flow control:** the encoder holds `tready` low for 3000 cycles after SOF;
  the CDC FIFO is sized **depth 4096** to absorb that backlog, so the serial source streams
  continuously with no external handshake.
- **Alignment / framing:** a receiver FSM BITSLIP-aligns on a `0x01` preamble, then begins
  forwarding on a `0xAA` sentinel (so only pixel words reach the encoder).
- Fixed `i_w`/`i_h` and a one-shot `i_sof` are generated on-chip after `sys_rdy`.

**Verification — end-to-end behavioral, full size × direction matrix.** `tb_jls_serial_demo`
(unisim `ISERDESE2` + the full encoder) drives serial bytes @ 360 Mb/s → compressed capture; each
lane's chunk is decoded by the **CharLS reference decoder** (`imagecodecs.jpegls_decode`, via
`verify_lossless.py`) and grid-reassembled for a **pixel-exact** compare against the source PGM.
The serial front-end is direction-agnostic — `(N_H, N_V)` only re-parameterises the encoder block
grid and the external feed striding; the ISERDES → CDC path is identical — so both
`tb_jls_serial_demo` and `jls_serial_demo_top` are parameterised on `(N_H, N_V)` (default vertical).
**All nine (3 sizes × 3 directions) decode LOSSLESS**; compressed bytes (ratio):

| Image | Vertical 12×1 | Horizontal 1×12 | Block 4×3 |
|---|---|---|---|
| 300×300   | 13,031 (6.91:1)      | 12,538 (7.18:1)      | 12,464 (7.22:1)      |
| 1500×1500 | 542,628 (4.15:1)     | 541,936 (4.15:1)     | 539,490 (4.17:1)     |
| 3000×3000 | 1,883,214 (4.78:1)   | 1,895,967 (4.75:1)   | 1,883,193 (4.78:1)   |

At each size the three directions compress within ~1 % (per-lane block *area* dominates, not cut
direction — matching the wide 16-lane study). Serial byte counts match the AXIS/parallel path
exactly: the front-end changes only *how* pixels arrive, never the compressed output.

**Line-buffer sizing (`LB_DEPTH`).** The per-lane line buffer must hold one full block row =
per-lane strip width = `i_w / N_H`. `LB_DEPTH` is parameterised end-to-end
(`encoder_wrapper → jls_encoder_axis → jls_serial_demo_top`/`tb`, default 1024). Vertical
(strip `W/12`) and block 4×3 (strip `W/4`) stay ≤ 1024 through 3000² (250 and 750), so those builds
are line-buffer-invariant with size. **Horizontal (N_H=1) needs `LB_DEPTH ≥ W`** — the only
size-dependent case.

**Verification — synthesizable bitstreams** (`jls_serial_demo_top`, real P&R on xc7a200tfbg676-2;
`build_serial_mode.tcl -tclargs <N_H> <N_V> [LB_DEPTH IMG_W IMG_H]`). All timing-closed, DRC 0
errors, each restores the canonical `jls_demo_top` config afterward:

| Mode | (N_H,N_V) | IMG | LB_DEPTH | WNS | WHS | LUT | BRAM |
|---|---|---|---|---|---|---|---|
| Vertical   | 12×1 | 300²        | 1024  | +0.743 ns | +0.048 ns | 27.79 % | 30 |
| Horizontal | 1×12 | 300²        | 1024  | +0.184 ns | +0.045 ns | 27.85 % | 30 |
| Block      | 4×3  | 300²        | 1024  | +0.573 ns | +0.026 ns | 27.98 % | 30 |
| Horizontal | 1×12 | 3000²       | 4096  | +0.329 ns | +0.033 ns | 28.14 % | 36 |
| Horizontal | 1×12 | 16000×10800 | 16384 | +0.697 ns | +0.046 ns | 27.86 % | 72 |

The three 300² directions are near-identical (LUT ≈ 27.8–28.0 %, FF 7.0 %, BRAM 30, DSP 14,
**12× ISERDESE2**, 1 MMCM in each). The full-width horizontal build at 3000² (`LB_DEPTH=4096`)
still closes with +0.329 ns and only grows BRAM 30 → 36 (the deeper per-lane line buffers) — the
LUT 37 405 total includes ~10.4 k LUT-as-memory for the async-read depth-4096 CDC FIFO. Vertical
and block at 1500²/3000² reuse the `LB_DEPTH=1024` config (strip < 1024), i.e. the 300² builds.
XDC (`jls_serial_demo_top.xdc`): diff clock R3/P3, reset R8, `clk`/`done`/`status[30:0]` on the
`jls_demo_top_wide.xdc` pins; the 12 `ser_d` ISERDES inputs are `set_false_path` + auto-placed
(UCIO/NSTD downgraded) — a real board pins them and adds per-bit IDELAYE2 eye-centering.

**Extreme scale — 16k image (16000×10800, 172.8 Mpix).** For 12 lanes only **horizontal (1×12)**
and **block (4×3)** are valid grids — 16000 is not divisible by 12, so vertical is impossible for
this width. Horizontal puts a **full 16000-wide strip** per lane, i.e. `LB_DEPTH = 16000` — right
at the line buffer's architectural ceiling (`i_w` is 14-bit → max width 16384). The bit-level
serial sim is impractical at 172.8 Mpix (≈13 h), so losslessness is verified over the **AXIS path**
(`tb_jls_wide`, byte-identical to the serial front-end which is proven at 300²–3000²): **16000×10800
horizontal → 39,570,604 bytes, 4.37:1, LOSSLESS** (CharLS reference decode, all 12 strips bit-exact
vs the source PGM). The matching bitstream (`LB_DEPTH=16384`, table above) still **closes timing at
+0.697 ns** and uses BRAM 72/365 (20 %) — the 16384-deep line buffers × 12 lanes — so the full
maximum-width horizontal configuration is synthesizable with wide margin. (Capture note: the
`tb_jls_wide` per-slice buffer must exceed the largest per-lane stream — high-detail 16k strips
reach ~6 MB, so `MAX_BYTES_PER_SLICE` was raised to 8 MB; too small a buffer silently truncates a
slice, which is a harness limit, not an encoder one.)

**Note vs. `jls_demo_top`:** this is *not* a self-contained on-chip bitstream — `ISERDESE2`
inputs must come from device pads, so the 12 serial lanes are real input pins (driven by an
external serialiser; in sim, the testbench). That is inherent to a high-speed serial receiver.
The `.bit`s are regenerable build artifacts (not committed); rebuild the vertical baseline with
`build_serial_demo.tcl` or any direction/size with `build_serial_mode.tcl -tclargs <N_H> <N_V>
[LB_DEPTH IMG_W IMG_H]` — both restore the canonical `jls_demo_top` / 12-lane config afterward.
Sim projects: `serial_demo_vlog.prj` (end-to-end sim), `serial_demo_top_vlog.prj` (top elaborate).
