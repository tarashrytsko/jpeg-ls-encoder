#!/usr/bin/env python3
"""RTL evaluation matrix for reviewer Req 9 (textures x bit depths x split directions).

Elaborates each (image, grid, BPP) snapshot sequentially and simulates up to --jobs
snapshots in parallel (tools/run_rtl_sim.py). Each output is CharLS-decoded and grid-
reassembled against the source (lossless check). Results -> eval/hw/matrix_results.csv.
  python tools/run_matrix.py [--jobs 2] [--set aer|b12|b16|all]
"""
import os, sys, csv, subprocess, argparse, re
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
C = os.path.join(ROOT, 'eval', 'corpus')
RUN = [sys.executable, os.path.join(ROOT, 'tools', 'run_rtl_sim.py'), 'run']
GRIDS = [(12, 1), (1, 12), (4, 3)]

SETS = {
    'aer': [('aer_2_2_17', 8), ('aer_2_2_13', 8), ('aer_2_2_09', 8), ('aer_3_2_25', 8), ('aer_wash-ir', 8)],
    'b12': [('s2_nile_agri_12b', 12), ('s2_nile_agri_nir_12b', 12), ('s2_nile_branch_12b', 12),
            ('s2_delta_west_12b', 12)],
    'b16': [('s2_cairo_urban_16b', 16), ('s2_pivot_fields_16b', 16), ('s2_desert_16b', 16),
            ('s2_nile_agri_16b', 16), ('s2_nile_agri_nir_16b', 16)],
}


def pgm_w(path):
    with open(path, 'rb') as f:
        t = f.read(40).split()
    return int(t[1])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--jobs', type=int, default=2)
    ap.add_argument('--set', default='all')
    a = ap.parse_args()
    items = []
    for k in (['aer', 'b12', 'b16'] if a.set == 'all' else a.set.split(',')):
        items += SETS[k]
    out = os.path.join(ROOT, 'eval', 'hw', 'matrix_results.csv')
    done = set()
    if os.path.exists(out):
        done = {(r['image'], r['grid']) for r in csv.DictReader(open(out)) if r['lossless'] == 'exact'}
    pool = ThreadPoolExecutor(a.jobs)
    futs = []

    def sim(args, key):
        r = subprocess.run(RUN + args + ['--run-only'], capture_output=True, text=True)
        m = re.search(r'RESULT (\S+) bpp=(\d+) (\d+)x(\d+) h(\d+)v(\d+) bytes=(\d+) CR=([\d.]+) lossless=(.*)', r.stdout)
        row = dict(image=key[0], grid=key[1], bpp='', W='', H='', bytes='', cr='', lossless='FAILED')
        if m:
            row.update(bpp=m[2], W=m[3], H=m[4], bytes=m[7], cr=m[8], lossless=m[9].strip())
        print(row, flush=True)
        return row

    for name, bpp in items:
        pgm = os.path.join(C, name + '.pgm')
        w = pgm_w(pgm)
        for nh, nv in GRIDS:
            key = (name, 'h%dv%d' % (nh, nv))
            if key in done:
                continue
            strip = w // nh
            lb = 1024 if strip <= 1024 else 1 << (strip - 1).bit_length()
            args = [name, pgm, str(nh), str(nv), '--bpp', str(bpp), '--lb', str(lb)]
            e = subprocess.run(RUN + args + ['--elab-only'], capture_output=True, text=True)
            if e.returncode:
                print('ELAB FAIL', key, e.stdout[-300:], flush=True); continue
            futs.append(pool.submit(sim, args, key))
    rows = [f.result() for f in futs]
    new = not os.path.exists(out)
    with open(out, 'a', newline='') as f:
        wr = csv.DictWriter(f, fieldnames=['image', 'grid', 'bpp', 'W', 'H', 'bytes', 'cr', 'lossless'])
        if new:
            wr.writeheader()
        wr.writerows(rows)


if __name__ == '__main__':
    main()
