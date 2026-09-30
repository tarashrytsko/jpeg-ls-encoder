#!/usr/bin/env python3
"""Supplementary software measurements for the V5 revision (reviewer R7 / E3, CR claim).

1. Near-lossless CR (CharLS, full frame, NEAR = 0..3; max |error| = NEAR verified) on the
   evaluation corpus -> eval/baseline/near_lossless.csv. Software reference only: the
   hardware IP is lossless (NEAR = 0) and BPP > 8 requires NEAR = 0.
2. CharLS CPU throughput, 1 process vs. one process per physical core, 4992x4992 8-bit
   Blue Marble split into 12 vertical strips (same partition as the 12-lane hardware)
   -> eval/baseline/charls_multicore.txt
"""
import os, sys, csv, glob, time, platform
from multiprocessing import Pool, cpu_count
import numpy as np
import imagecodecs as ic

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
from prepare_corpus import read_pgm  # noqa: E402

OUT = os.path.join(ROOT, 'eval', 'baseline')


def near_lossless():
    ims = [('bm_1500x1500', os.path.join(ROOT, 'JPEG_ENC_8f.sim', 'images', 'world_gray_1500x1500.pgm'), 8)]
    for f in sorted(glob.glob(os.path.join(ROOT, 'eval', 'corpus', '*.pgm'))):
        n = os.path.splitext(os.path.basename(f))[0]
        ims.append((n, f, 12 if n.endswith('_12b') else 16 if n.endswith('_16b') else 8))
    rows = []
    for name, path, bpp in ims:
        a = read_pgm(path)
        row = dict(image=name, bpp=bpp)
        for near in range(4):
            e = ic.jpegls_encode(a, level=near)
            d = ic.jpegls_decode(e)
            err = int(np.abs(d.astype(np.int64) - a.astype(np.int64)).max())
            assert err <= near, (name, near, err)
            row['cr_near%d' % near] = round(a.size * bpp / 8.0 / len(e), 4)
        rows.append(row)
        print(row, flush=True)
    with open(os.path.join(OUT, 'near_lossless.csv'), 'w', newline='') as f:
        wr = csv.DictWriter(f, fieldnames=list(rows[0])); wr.writeheader(); wr.writerows(rows)


def _enc(strip):
    return len(ic.jpegls_encode(strip))


def multicore():
    a = read_pgm(os.path.join(ROOT, 'JPEG_ENC_8f.sim', 'images', 'world_gray_4992x4992.pgm'))
    strips = [np.ascontiguousarray(s) for s in np.hsplit(a, 12)]
    best1 = min(_time(lambda: [_enc(s) for s in strips]) for _ in range(3))
    ncore = int(os.environ.get('NCORE', '6'))
    with Pool(ncore) as p:
        p.map(_enc, strips)                                   # warm-up
        bestn = min(_time(lambda: p.map(_enc, strips)) for _ in range(3))
    txt = ('CharLS %s via imagecodecs %s, 4992x4992 8-bit Blue Marble, 12 vertical strips, best of 3\n'
           'host: %s, %d logical CPUs, %s\n'
           '1 process : %.1f Mpixel/s\n'
           '%d processes: %.1f Mpixel/s\n' % (
               'charls-2.4.3', ic.__version__, platform.processor(), cpu_count(), platform.platform(),
               a.size / best1 / 1e6, ncore, a.size / bestn / 1e6))
    open(os.path.join(OUT, 'charls_multicore.txt'), 'w').write(txt)
    print(txt)


def _time(fn):
    t = time.perf_counter(); fn(); return time.perf_counter() - t


if __name__ == '__main__':
    what = sys.argv[1] if len(sys.argv) > 1 else 'all'
    if what in ('all', 'near'):
        near_lossless()
    if what in ('all', 'cpu'):
        multicore()
