# Design: Horizontal + Block Wide-Splitting at ~4 Gb/s

**Date:** 2026-06-27
**Status:** Approved (pending spec review)
**Target device:** Xilinx Artix-7 `xc7a200tfbg676-2`
**Builds on:** the wide 16-lane vertical design
(`2026-06-26-wide-16lane-jpegls-500mbs-design.md`) — `jls_encoder_axis` / `jls_demo_top`,
128-bit wide input, 16 lanes @ 32 MHz = 512 MB/s, timing-closed (WNS +8.25 ns). Branch
`feature/jls-encoder-axis`.

## Problem / Context

The wide 16-lane encoder reaches ~4 Gb/s in hardware but **only for VERTICAL splitting**
(column-strips). Two things are vertical-specific: (1) the wide lockstep splitter's intra-strip
y-range is hardcoded to `i_h` (assumes `N_V=1`), and (2) the 128-bit input ROM is column-strided
(slot k = column-strip k's pixel). Everything else — `encoder_wrapper` (already derives
`col_w=i_w/N_H`, `row_h=i_h/N_V` for any grid), `axis_image_source` (streams the ROM in order,
stride-agnostic), the FIFOs, the sink, `jls_demo_top` — is already grid-parametric.

Throughput is **identical in all split directions**: 16 lanes × 32 MHz = 512 Mpix/s = 512 MB/s,
because the parallelism (16 independent encoder lanes, 1 px/cycle each, fed 16 px/cycle) is the
same; only *which* sub-image each lane encodes changes.

## Goal

From a **single mode-parameterized RTL**, produce **two timing-closed bitstreams** —
**horizontal** (`N_H=1, N_V=16`, row-strips) and **block** (`N_H=4, N_V=4`, 64×64 blocks) — each
**bit-exact lossless** and **~512 MB/s** on `xc7a200tfbg676-2`.

## Non-Goals / Out of Scope

- Higher throughput than 512 MB/s (parallelism is fixed at 16 lanes).
- Full-size (e.g. 16384-wide) horizontal builds — noted as an `LB_DEPTH` parameter bump
  (≈64 BRAM for full-width line buffers, fits) but not built; the demo stays 256×256.
- Changing the encoder math, the AXIS interface, or the vertical build (all unchanged).
- Non-square block factorizations (2×8 / 8×2) — 4×4 chosen.

## Decisions (settled during brainstorming)

| Decision | Choice |
|---|---|
| Modes to build | **Both** horizontal (`1×16`) and block (`4×4`) |
| Block factorization | **4×4** (square, 64×64 blocks) |
| RTL strategy | **One mode-parameterized RTL**; per-mode via build-time `(N_H,N_V)` + ROM |
| Striding | **One generalized tool** `make_strided_hex.py (…, N_H, N_V)` |
| Demo image | **256×256** (all modes ≤1024 strip width → `LB_DEPTH=1024` unchanged) |
| Lanes / clock | `N_E=16` @ 32/32 MHz (1:1) in all modes → 512 MB/s |

## Architecture

### The lockstep model (mode-agnostic)
All 16 lanes advance a shared intra-strip counter `(xs, ys)` over each lane's sub-image of
`stripW × swathH` where `stripW = i_w/N_H`, `swathH = i_h/N_V`. Each cycle the 128-bit input
delivers, in slot `k`, lane `k`'s pixel at the current `(xs, ys)`. Lane `k` occupies block
position `(bx, by)` with `bx = k % N_H`, `by = k / N_H`; its full-image pixel is
`(bx*stripW + xs, by*swathH + ys)`. Total cycles = `stripW*swathH = W*H/16` in every mode.

### 1 — RTL change: generalize the splitter y-range (`block_split.v`)
The only RTL edit. Add:
```verilog
    wire [13:0] swathH = i_h / N_V;   // per-lane height
```
and replace the two uses of `i_h` in the intra-strip logic:
- counter: `ys` wraps at `swathH-1` (was `i_h-1`);
- `frame_active` end-of-frame test and `o_last_enc`: `xs==stripW-1 && ys==swathH-1`
  (was `... && ys==i_h-1`).
`stripW = i_w/N_H` is already present. After this the splitter handles any `(N_H,N_V)` in
lockstep. No port or width changes.

### 2 — Mode-parameterized striding (`make_strided_hex.py`, tool only)
Add an `N_V` argument (default 1 for back-compat). For each cycle word at `(ys, xs)` (ys outer,
xs inner — matching the splitter's counter, so ROM `addr = ys*stripW + xs`):
```
byte k = px[(by*swathH + ys)*W + (bx*stripW + xs)]   # bx=k%N_H, by=k/N_H
word   = OR_k( byte_k << (8*k) )                       # emitted as %032X
```
This yields column-strided (`N_V=1`), row-strided (`N_H=1`), and block-strided layouts from one
tool. `stripW=W/N_H`, `swathH=H/N_V`. `axis_image_source` streams the resulting words in order
(stride-agnostic — no RTL change; its word count `N = W*H/N_E` is already mode-invariant).

### 3 — Per-mode builds (one RTL, build-time params)
`N_E=16` always; `N_H*N_V=16` (one block per lane). Per mode, set `jls_demo_top`'s `(N_H,N_V)`
(via a synth-fileset generic override in the build TCL) and regenerate `rom_wide.hex` with the
matching stride:

| Mode | N_H | N_V | Per-lane sub-image (256²) | Line buf |
|---|---|---|---|---|
| Horizontal | 1 | 16 | 256 × 16 (row-strip) | 256 |
| Block | 4 | 4 | 64 × 64 | 64 |

Both ≤ `LB_DEPTH=1024`. Each mode → own `synth_1` + `impl_1` → `jls_demo_top.bit`.

## File-level change plan

**Modified**
- `JPEG_ENC_8f.srcs/sources_1/new/block_split.v` — add `swathH`, generalize `ys`/`o_last`.
- `tools/make_strided_hex.py` — add `N_V` arg + general `(bx,by)` striding formula.

**New**
- Per-mode ROM hexes: `rom_wide_h1v16.hex`, `rom_wide_h4v4.hex` (+ matching TB feed hexes).
- Build TCL: `build_wide_synth_mode.tcl` (or per-mode `build_horiz_synth.tcl` /
  `build_block_synth.tcl`) that sets the `(N_H,N_V)` generic + points at the mode ROM.

**Unchanged** (verified grid-parametric): `jls_encoder_axis.v`, `axis_pixel_in.v`,
`axis_image_source.v`, `axis_sink.v`, `jls_demo_top.v`, `encoder_wrapper.v`, `fifo_*`, the XDC
(same clk/reset/status pins), `clk_wiz` (32/32).

## Verification (per mode)

1. **Lossless gate:** generate the mode-strided feed, run `tb_jls_wide` (AXIS-fed) capturing 16
   lanes → `output_h{N_H}v{N_V}_256x256.jls`; `verify_lossless.py … <N_H> <N_V>` reassembles the
   grid → **bit-exact match**. Cross-check: the on-chip demo sim (`tb_jls_demo_wide`, mode ROM)
   output byte-matches the AXIS-fed output (confirms `axis_image_source` + the mode ROM).
2. **HW gate:** `impl_1 → write_bitstream` with **WNS ≥ 0** at 32/32 MHz; report util + throughput
   (~512 MB/s). Same encoder logic that closed vertical at +8.25 ns.

Done for each of horizontal and block.

## Risks / Mitigations

- **Splitter generalization off-by-one** (swathH vs i_h) — guarded by the per-mode lossless gate
  (grid reassembly); vertical (`N_V=1`) must still pass (swathH = i_h/1 = i_h, unchanged behavior).
- **Striding-tool ↔ splitter mismatch** (slot k must equal lane k's `(bx,by)` pixel) — the same
  `(bx,by)` mapping is used in the tool and implied by the splitter's slot→lane routing; the
  lossless gate catches any mismatch (garbled reassembly).
- **Timing at N_H=1 horizontal** (full-width line buffers, larger RAM) — for 256² the line buffer
  is only 256 deep; same encoder logic, expect closure like vertical. If marginal, the WB-style
  fallback (lower clock / fewer lanes) applies, but +8.25 ns vertical slack makes this unlikely.
- **Regression:** the vertical build must remain intact — the tool's `N_V` default is 1 and the
  splitter reduces to the current behavior at `N_V=1`.

## Done =
Two timing-closed bitstreams (horizontal `1×16`, block `4×4`) on `xc7a200tfbg676-2`, each
bit-exact lossless (grid reassembly) at ~512 MB/s, from one mode-parameterized RTL — with the
vertical build unaffected.
