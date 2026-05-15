# Technical Debt — JPEG_ENC_8f

Readability and code quality issues found across the synthesizable source files.

---

## Critical — Dead / Duplicate Code

### `jls_encoder2.v`

- **Lines 411–431**: The section banner `// Pipeline stage a: update a_ii / a_jj per block` is copy-pasted **7 times consecutively** with no code between them.
- **Lines 572–578 and 595–600**: The `block_done_r_d` delayed-register `always` block is written **twice**. Two flip-flops driving the same signal — latent synthesis bug.
- **Lines 481–516**: Two complete copies of the same `a_ii_i`/`a_jj_i` always block, both fully commented out.
- **Lines 449–459, 581–593**: Large commented-out always blocks — earlier drafts of coordinate logic.
- **Lines 327–336**: Debug `pixel_count` counter left in synthesizable source, with the stale comment `// Add this inside your module`.
- **Lines 626–627**: Wire `last_pixel_block` declared but its `assign` is commented out — never driven or read.
- **Line 1189**: `j_last_pending` assigned but never read anywhere.

### `fifo_reset_bram_async.v`

- **Line 20**: `reset_active` declared and initialized but never assigned or read.
- **Line 34**: `reset_count <= reset_count;` — no-op self-assignment; does nothing but obscures intent.

### `encoder_wrapper.v`

- **Lines 47–63**: `slice_index[]` and `slice_global` are tracked but never output or used.
- **Lines 42–81**: `total_slices`, `remaining_lines_last_encoder`, `full_slices_for_encoder`, `total_lines_for_encoder` — all computed but none are actually passed to the encoder instances (which receive raw `s_w`/`s_h`).

### `fifo_wrapper_input.v`

- **Lines 34–35**: `rd_data_count_flat` / `wr_data_count_flat` declared but never assigned. The FIFO ports connect to undeclared scalar names instead — likely a synthesis warning/error.
- **Line 16**: Commented-out port `o_last_enc` left in the port list.
- **Lines 25–26**: `almost_empty` appears in the port list twice; a commented-out duplicate sits directly below.

---

## Moderate — Confusing Style

### `jls_encoder2.v`

- **Line 3**: Module header comment reads `Module : jls_encoder` but the module name is `jls_encoder2`.
- **Lines 795–803**: Several `reg` signals (`s`, `q`, `rt`, `runi`, etc.) are annotated `// not real register`. These are combinational variables mis-declared as `reg`. Should use a `_t` suffix or be declared inside the `always` block to make the intent clear.
- **Lines 1336–1337**: Inline commented-out revision artifacts: `//+16'd1};` left in the `jls_wl`/`jls_hl` assignments.
- **Lines 436–447**: Inconsistent indentation inside the `always @(posedge clk)` reset block.
- **Line 1386**: `assign o_data = {k_data[15:8], k_data[7:0]}` — concatenation of a signal with its own bytes in the same order; equivalent to `assign o_data = k_data`.

### `fifo_write_control.v`

- **Lines 42–87**: Inline comments embed hardcoded example values (`460 / 3 = 153`, `blk_x_start[0]=0`, etc.) that describe only one specific image resolution. The logic is generic; comments imply it is fixed.
- **Line 14**: `encoder_sel` input port annotated `// currently unused`.

### `fifo_read_control.v`

- **Line 2**: Banner comment `// FINAL - COPY READY` — development artifact, should be removed.
- **Lines 135–155**: `S_READ` case body has different indentation from `S_SOF`, `S_GAP`, and `S_DONE`.
- **Loop variables `a`, `b`, `e`**: Single-letter names inside multi-level geometry loops make the block-splitting logic hard to follow.

### `block_split.v`

- **Lines 110–118**: A manual `clog2` function is defined locally even though `$clog2()` is already used in the module's own port declarations. The local version is redundant.

### `fifo_reset_bram_async.v`

- **Line 22**: Stale development comment `//reg sys_rdy;` left in.
- **Line 28**: Redundant condition — `(rstn_ext && locked==1)` is checked after the `if (~rstn_ext || ~locked)` branch already covers the negative case; the `&&` guard is always true here.

---

## Minor — Inconsistencies

- **`timescale` mismatch**: `jls_encoder2.v`, `block_split.v`, `fifo_wrapper_input.v`, and `fifo_reset_bram_async.v` use `` `timescale 1ps/1ps ``; all other modules use `` `timescale 1ns/1ps ``. Should be uniform across the project.
- **`image_generator.v`**: The `stage` variable uses magic numbers (0, 1, 2) with no named `localparam` constants.

---

## Fix Priority

| Priority | Item | File | Lines |
|----------|------|------|-------|
| High | Duplicate `always` block for `block_done_r_d` | `jls_encoder2.v` | 572–578, 595–600 |
| High | 7× repeated section banner | `jls_encoder2.v` | 411–431 |
| High | Undeclared FIFO count wires | `fifo_wrapper_input.v` | 34–35, 67–68 |
| High | Debug `pixel_count` counter in RTL | `jls_encoder2.v` | 327–336 |
| Medium | Dead computed signals in wrapper | `encoder_wrapper.v` | 42–81 |
| Medium | No-op self-assignment | `fifo_reset_bram_async.v` | 34 |
| Medium | `reg` variables annotated "not real register" | `jls_encoder2.v` | 795–803 |
| Medium | Unused `encoder_sel` port | `fifo_write_control.v` | 14 |
| Low | `timescale` inconsistency across files | all | — |
| Low | `o_data` redundant byte-swap concat | `jls_encoder2.v` | 1386 |
| Low | Magic numbers in `stage` FSM | `image_generator.v` | 33, 82–90 |
| Low | Local `clog2` function duplicates `$clog2` | `block_split.v` | 110–118 |
