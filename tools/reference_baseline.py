#!/usr/bin/env python3
"""Reference-software compression baseline (reviewer Req 3) + corpus CR model (Req 9).

For every image and split grid (N_H x N_V) this computes
  * CharLS (ISO/IEC 14495-1 reference-class library, via imagecodecs) on the FULL
    frame = the single-core software baseline the reviewer asked for;
  * CharLS on exactly the same N_H x N_V blocks the hardware lanes encode
    (software model of the partitioned stream);
  * the hardware result (sum of per-lane .jls bytes) where an RTL output exists,
    plus a per-lane entropy-coded-segment comparison HW vs CharLS;
  * context codecs on the full frame: JPEG 2000 reversible 5/3 (OpenJPEG),
    JPEG-XL lossless (libjxl, effort 7), PNG (zlib level 9).
Every codec output is decoded and checked for exact reconstruction.
CharLS single-thread encode throughput is also measured on this host.

Usage: python tools/reference_baseline.py [--hwdir DIR ...] [--only PREFIX]
Writes eval/baseline/reference_baseline.csv and .md
"""
import os, sys, csv, time, glob, argparse, platform
import numpy as np
import imagecodecs as ic

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
from prepare_corpus import read_pgm  # noqa: E402

IMG = os.path.join(ROOT, 'JPEG_ENC_8f.sim', 'images')
OB = os.path.join(ROOT, 'JPEG_ENC_8f.sim', 'output_block')
CORPUS = os.path.join(ROOT, 'eval', 'corpus')
OUT = os.path.join(ROOT, 'eval', 'baseline')

GRIDS = [(12, 1), (1, 12), (4, 3), (16, 1), (1, 16), (4, 4)]


def split_chunks(jls):
    """Per-lane JPEG-LS streams (SOI..EOI), last SOI before each EOI."""
    out, pos = [], 0
    while True:
        e = jls.find(b'\xff\xd9', pos)
        if e < 0:
            break
        s = jls.rfind(b'\xff\xd8', pos, e)
        out.append(jls[s:e + 2]); pos = e + 2
    return out


def scan_bytes(stream):
    """Bytes of the entropy-coded segment (after the SOS header, excluding EOI)."""
    i = 2
    while True:
        assert stream[i] == 0xFF, 'marker expected'
        m = stream[i + 1]
        ln = (stream[i + 2] << 8) | stream[i + 3]
        i += 2 + ln
        if m == 0xDA:
            return len(stream) - 2 - i


def blocks(a, nh, nv):
    h, w = a.shape
    bw, bh = w // nh, h // nv
    for r in range(nv):
        for c in range(nh):
            yield a[r*bh:(r+1)*bh, c*bw:(c+1)*bw]


def enc_check(fn_enc, fn_dec, a):
    e = fn_enc(a)
    d = fn_dec(e)
    if d.ndim == 3:
        d = d[..., 0]
    assert d.shape == a.shape and (d == a).all(), 'round-trip mismatch'
    return len(e)


def hw_file(name, nh, nv, hwdirs):
    for d in hwdirs:
        p = os.path.join(d, '%s__h%dv%d.jls' % (name, nh, nv))
        if os.path.exists(p):
            return p
    if name.startswith('bm_'):                         # existing Blue Marble RTL outputs
        w = name.split('_')[1]
        p = os.path.join(OB, 'output_h%dv%d_%s.jls' % (nh, nv, w))
        if os.path.exists(p):
            return p
    return None


def load_images(only):
    ims = []
    for s in ['300x300', '1500x1500', '3000x3000', '4992x4992', '5000x5000']:
        ims.append(('bm_' + s, os.path.join(IMG, 'world_gray_%s.pgm' % s), 'Blue Marble', 8))
    for f in sorted(glob.glob(os.path.join(CORPUS, '*.pgm'))):
        n = os.path.splitext(os.path.basename(f))[0]
        if n.startswith('aer_'):
            ims.append((n, f, 'USC-SIPI Aerials', 8))
        elif n.endswith('_12b'):
            ims.append((n, f, 'Sentinel-2 L1C', 12))
        elif n.endswith('_16b'):
            ims.append((n, f, 'Sentinel-2 L1C', 16))
    return [t for t in ims if not only or any(t[0].startswith(o) for o in only)]


def charls_throughput():
    a = read_pgm(os.path.join(IMG, 'world_gray_4992x4992.pgm'))
    best = 1e9
    for _ in range(3):
        t = time.perf_counter(); ic.jpegls_encode(a); best = min(best, time.perf_counter() - t)
    return a.size / best / 1e6


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--hwdir', action='append', default=[os.path.join(ROOT, 'eval', 'hw')])
    ap.add_argument('--only', action='append')
    ap.add_argument('--no-context', action='store_true', help='skip J2K/JXL/PNG')
    args = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    rows, lane_rows = [], []
    for name, path, src, bpp in load_images(args.only):
        a = read_pgm(path)
        h, w = a.shape
        rawb = a.size * bpp / 8.0
        full = enc_check(ic.jpegls_encode, ic.jpegls_decode, a)
        row = dict(image=name, source=src, bpp=bpp, W=w, H=h, raw_bytes=int(rawb),
                   charls_full=full, cr_charls_full=round(rawb / full, 4))
        if not args.no_context:
            j2k = enc_check(lambda x: ic.jpeg2k_encode(x, reversible=True), ic.jpeg2k_decode, a)
            jxl = enc_check(lambda x: ic.jpegxl_encode(x, lossless=True, effort=7), ic.jpegxl_decode, a)
            png = enc_check(lambda x: ic.png_encode(x, level=9), ic.png_decode, a)
            row.update(j2k_full=j2k, cr_j2k=round(rawb / j2k, 4), jxl_full=jxl,
                       cr_jxl=round(rawb / jxl, 4), png_full=png, cr_png=round(rawb / png, 4))
        for nh, nv in GRIDS:
            if w % nh or h % nv:
                continue
            tag = 'h%dv%d' % (nh, nv)
            cl = [ic.jpegls_encode(b) for b in blocks(a, nh, nv)]
            row['charls_' + tag] = sum(len(c) for c in cl)
            row['cr_charls_' + tag] = round(rawb / row['charls_' + tag], 4)
            hf = hw_file(name, nh, nv, args.hwdir)
            if hf:
                hw = open(hf, 'rb').read()
                ch = split_chunks(hw)
                ok = len(ch) == nh * nv
                if ok:
                    for k, (c, b) in enumerate(zip(ch, blocks(a, nh, nv))):
                        d = ic.jpegls_decode(c)
                        d = d[..., 0] if d.ndim == 3 else d
                        ok = ok and d.shape == b.shape and (d == b).all()
                        lane_rows.append(dict(image=name, grid=tag, lane=k, hw_bytes=len(c),
                                              hw_scan=scan_bytes(c), charls_bytes=len(cl[k]),
                                              charls_scan=scan_bytes(cl[k]),
                                              scan_diff=scan_bytes(c) - scan_bytes(cl[k])))
                row['hw_' + tag] = len(hw)
                row['cr_hw_' + tag] = round(rawb / len(hw), 4)
                row['hw_lossless_' + tag] = 'exact' if ok else 'FAIL'
                row['hw_vs_charls_full_pct_' + tag] = round(100.0 * (len(hw) - full) / full, 3)
        rows.append(row)
        print(name, {k: v for k, v in row.items() if k.startswith('cr_')})
    keys = []
    for r in rows:
        for k in r:
            if k not in keys:
                keys.append(k)
    with open(os.path.join(OUT, 'reference_baseline.csv'), 'w', newline='') as f:
        wr = csv.DictWriter(f, fieldnames=keys); wr.writeheader(); wr.writerows(rows)
    if lane_rows:
        with open(os.path.join(OUT, 'lane_hw_vs_charls.csv'), 'w', newline='') as f:
            wr = csv.DictWriter(f, fieldnames=list(lane_rows[0])); wr.writeheader(); wr.writerows(lane_rows)
    tp = charls_throughput()
    with open(os.path.join(OUT, 'charls_throughput.txt'), 'w') as f:
        f.write('CharLS %s single-thread encode, 4992x4992 8-bit Blue Marble, best of 3\n' % ic.charls_version()
                if hasattr(ic, 'charls_version') else 'CharLS single-thread encode, 4992x4992 8-bit, best of 3\n')
        f.write('host: %s | %s\n' % (platform.processor(), platform.platform()))
        f.write('throughput: %.1f Mpixel/s = %.1f MB/s\n' % (tp, tp))
    print('CharLS throughput %.1f MB/s' % tp)


if __name__ == '__main__':
    main()
