#!/usr/bin/env python3
"""
Verify a concatenated multi-slice JPEG-LS output against the source image.

The parallel encoder splits the image into an N_H x N_V grid of blocks
(block_idx = row*N_H + col, encoder = block_idx % N_E). With one block per
encoder (NUM_SLICES=1) the testbench writes the slices in block_idx order, so
chunk i in the .jls reassembles at block (row=i//N_H, col=i%N_H).

Usage:
    python verify_lossless.py <output.jls> <input.pgm> <N_H> <N_V>
"""
import sys
import numpy as np
import imagecodecs


def read_pgm(path):
    with open(path, 'rb') as f:
        data = f.read()
    # Parse P5 header: magic, width, height, maxval (whitespace/comment tolerant)
    idx = 0
    tokens = []
    assert data[:2] == b'P5', f'{path} is not a P5 PGM'
    idx = 2
    while len(tokens) < 3:
        while idx < len(data) and data[idx] in b' \t\r\n':
            idx += 1
        if idx < len(data) and data[idx:idx+1] == b'#':       # comment line
            while idx < len(data) and data[idx] not in b'\r\n':
                idx += 1
            continue
        start = idx
        while idx < len(data) and data[idx] not in b' \t\r\n':
            idx += 1
        tokens.append(int(data[start:idx]))
    w, h, _maxval = tokens
    idx += 1  # single whitespace after maxval
    pix = np.frombuffer(data[idx:idx + w * h], dtype=np.uint8).reshape(h, w)
    return pix


def split_chunks(jls):
    soi = [i for i in range(len(jls) - 1) if jls[i] == 0xFF and jls[i + 1] == 0xD8]
    eoi = [i for i in range(len(jls) - 1) if jls[i] == 0xFF and jls[i + 1] == 0xD9]
    # Encoders processing swaths >=1 emit a duplicate SOI header (a known quirk,
    # see BENCHMARKS.md). Pair each EOI with the LAST SOI that precedes it (after
    # the previous EOI) so the duplicate header is stripped.
    chunks, prev = [], -1
    for e in eoi:
        cands = [s for s in soi if prev < s <= e]
        if not cands:
            continue
        chunks.append(jls[cands[-1]:e + 2])
        prev = e
    return chunks


def main():
    jls_path, pgm_path, n_h, n_v = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
    src = read_pgm(pgm_path)
    H, W = src.shape
    with open(jls_path, 'rb') as f:
        jls = f.read()

    chunks = split_chunks(jls)
    expected = n_h * n_v
    print(f'{jls_path}: {len(chunks)} chunks (expected {expected}), grid {n_h}x{n_v}, image {W}x{H}')
    if len(chunks) != expected:
        print(f'  FAIL: chunk count {len(chunks)} != {expected}')
        return 1

    recon = np.zeros((H, W), dtype=np.uint8)
    blk_w, blk_h = W // n_h, H // n_v
    for i, ch in enumerate(chunks):
        dec = imagecodecs.jpegls_decode(ch)
        if dec.ndim == 3:
            dec = dec[..., 0]
        row, col = i // n_h, i % n_h
        y0, x0 = row * blk_h, col * blk_w
        bh, bw = dec.shape
        recon[y0:y0 + bh, x0:x0 + bw] = dec
        # last row/col carry the remainder (block_split gives the remainder to the last block)
        ew = (W - (n_h - 1) * blk_w) if col == n_h - 1 else blk_w
        eh = (H - (n_v - 1) * blk_h) if row == n_v - 1 else blk_h
        if (bw, bh) != (ew, eh):
            print(f'  WARN chunk {i}: decoded {bw}x{bh}, expected {ew}x{eh}')

    if recon.shape == src.shape and np.array_equal(recon, src):
        print(f'  LOSSLESS: exact match ({W}x{H})')
        return 0
    diff = np.abs(recon.astype(int) - src.astype(int))
    nmis = int((diff != 0).sum())
    print(f'  MISMATCH: {nmis} pixels differ ({100.0*nmis/(W*H):.4f}%), max |diff|={int(diff.max())}')
    return 2


if __name__ == '__main__':
    sys.exit(main())
