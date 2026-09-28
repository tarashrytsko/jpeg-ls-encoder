#!/usr/bin/env python3
"""SEU fault-injection campaign (reviewer Req 8).

Two campaigns, both on the real RTL output of the 12-lane encoder:

 1. RTL state upsets  (python tools/seu_inject.py rtl [--trials 24] [--jobs 2])
    xsim runs tb_jls_seu (tb_jls_wide + a single bit flip) on the 12-lane vertical build,
    300x300 Blue Marble, flipping one random bit of one lane's context RAM (A, B, C, N)
    or line buffer after a random pixel count. Each faulty stream is CharLS-decoded and
    compared with the source: masked / silent pixel corruption / decode failure, number of
    corrupted pixels, and whether any OTHER lane changed (containment).

 2. Compressed-stream upsets (python tools/seu_inject.py stream [--trials 2000])
    Single bit flips in the entropy-coded data (output FIFO / mass memory / downlink),
    for the same image encoded as 1 stream (single core) vs the 12-lane and 16-lane HW
    streams: fraction of the frame corrupted per upset.

Results: eval/seu/rtl_injection.csv, eval/seu/stream_injection.csv, eval/seu/summary.txt
"""
import os, sys, csv, random, subprocess, argparse
from concurrent.futures import ThreadPoolExecutor
import numpy as np
import imagecodecs as ic

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
from prepare_corpus import read_pgm  # noqa: E402
from reference_baseline import split_chunks, blocks, scan_bytes  # noqa: E402

BIN = 'C:/Xilinx/Vivado/2024.2/bin'
WD = os.path.join(ROOT, 'eval', 'seu', 'xsim')
OUT = os.path.join(ROOT, 'eval', 'seu')
PGM = os.path.join(ROOT, 'JPEG_ENC_8f.sim', 'images', 'world_gray_300x300.pgm')
HEX = os.path.join(ROOT, 'JPEG_ENC_8f.sim', 'images', 'vert12x1_300.hex').replace('\\', '/')
GOLD = os.path.join(ROOT, 'eval', 'ref_8bit', 'output_h12v1_300x300.jls')
NE, NH, NV, W, H = 12, 12, 1, 300, 300
TGT = {0: ('A', 366, 13), 1: ('B', 366, 7), 2: ('C', 364, 8), 3: ('N', 366, 6), 4: ('LB', W // NH, 8)}


def run(cmd, log):
    with open(log, 'w') as f:
        return subprocess.run(cmd, cwd=WD, stdout=f, stderr=subprocess.STDOUT).returncode


def elaborate(snap='seu12'):
    q = lambda g: '"%s"' % g.replace('"', '\\"')
    gen = ['N_E=%d' % NE, 'N_H=%d' % NH, 'N_V=%d' % NV, 'IMG_W=%d' % W, 'IMG_H=%d' % H,
           'MAX_BYTES_PER_SLICE=20000', 'LB_DEPTH=2048', 'HEXFILE="%s"' % HEX]
    cmd = ' '.join(['"%s/xelab.bat"' % BIN, '--debug off --relax --mt 2',
                    '-L xil_defaultlib -L fifo_generator_v13_2_11 -L unisims_ver -L unimacro_ver -L secureip -L xpm'] +
                   ['-generic_top %s' % q(g) for g in gen] + ['--snapshot %s xil_defaultlib.tb_jls_seu xil_defaultlib.glbl' % snap])
    return run(cmd, os.path.join(WD, 'elab_%s.log' % snap))


def analyse(jls_bytes, src, gold_chunks, lane):
    """-> (outcome, corrupted_pixels_in_lane, other_lanes_changed)"""
    ch = split_chunks(jls_bytes)
    if len(ch) != len(gold_chunks):
        return 'framing_lost', (H * W) // NE, True
    other = any(ch[k] != gold_chunks[k] for k in range(len(ch)) if k != lane)
    if ch[lane] == gold_chunks[lane]:
        return 'masked', 0, other
    b = list(blocks(src, NH, NV))[lane]
    try:
        d = ic.jpegls_decode(ch[lane])
        d = d[..., 0] if d.ndim == 3 else d
        if d.shape != b.shape:
            return 'decode_error', b.size, other
        bad = int((d != b).sum())
        return ('silent_corruption' if bad else 'stream_changed_pixels_ok'), bad, other
    except Exception:
        return 'decode_error', b.size, other


def campaign_rtl(trials, jobs, seed):
    os.makedirs(os.path.join(OUT, 'inj'), exist_ok=True)
    # One snapshot per worker: concurrent xsim runs of the SAME snapshot share its
    # run directory and clobber each other's plusargs/outputs.
    import queue
    snaps = queue.Queue()
    for j in range(jobs):
        sn = 'seu12_w%d' % j
        if not os.path.exists(os.path.join(WD, 'xsim.dir', sn)):
            assert elaborate(sn) == 0, 'elaboration failed (see eval/seu/xsim/elab_%s.log)' % sn
        snaps.put(sn)
    src = read_pgm(PGM)
    gold = split_chunks(open(GOLD, 'rb').read())
    rng = random.Random(seed)
    plan = []
    for tgt, (nm, depth, bits) in TGT.items():
        lo = 1 if nm == 'C' else 0
        for t in range(trials):
            plan.append(dict(id='%s_%02d' % (nm, t), tgt=tgt, name=nm, lane=rng.randrange(NE),
                             addr=rng.randrange(lo, lo + depth), bit=rng.randrange(bits),
                             pix=rng.randrange(1, (W * H) // NE)))

    def one(p):
        of = os.path.join(OUT, 'inj', p['id'] + '.jls').replace('\\', '/')
        if os.path.exists(of):
            os.remove(of)
        sn = snaps.get()
        args = ['%s/xsim.bat' % BIN, sn, '-R'] + ['-testplusarg', 'seu_lane=%d' % p['lane'],
               '-testplusarg', 'seu_tgt=%d' % p['tgt'], '-testplusarg', 'seu_addr=%d' % p['addr'],
               '-testplusarg', 'seu_bit=%d' % p['bit'], '-testplusarg', 'seu_pix=%d' % p['pix'],
               '-testplusarg', 'outfile=%s' % of]
        cmd = ' '.join('"%s"' % a if ('=' in a or ' ' in a) else a for a in args)
        run(cmd, os.path.join(OUT, 'inj', p['id'] + '.log'))
        snaps.put(sn)
        if not os.path.exists(of):
            r = dict(p, outcome='no_output_hang', corrupted_px=(W * H) // NE, other_lanes_changed='?')
        else:
            o, n, other = analyse(open(of, 'rb').read(), src, gold, p['lane'])
            r = dict(p, outcome=o, corrupted_px=n, other_lanes_changed=other)
        r['lane_px'] = (W * H) // NE
        r['frame_frac'] = r['corrupted_px'] / float(W * H)
        print(r, flush=True)
        return r

    with ThreadPoolExecutor(jobs) as ex:
        rows = list(ex.map(one, plan))
    with open(os.path.join(OUT, 'rtl_injection.csv'), 'w', newline='') as f:
        wr = csv.DictWriter(f, fieldnames=list(rows[0])); wr.writeheader(); wr.writerows(rows)
    return rows


def flip_trials(streams, blks, trials, rng, full_px):
    """Flip one random bit in the entropy-coded data of one stream (streams weighted by
    their scan size, i.e. a uniformly random bit of the stored compressed frame)."""
    sizes = [scan_bytes(s) for s in streams]
    offs = [len(s) - 2 - n for s, n in zip(streams, sizes)]
    tot = sum(sizes)
    res = []
    for _ in range(trials):
        r = rng.randrange(tot * 8)
        k = 0
        while r >= sizes[k] * 8:
            r -= sizes[k] * 8; k += 1
        s = bytearray(streams[k]); s[offs[k] + r // 8] ^= 1 << (r % 8)
        try:
            d = ic.jpegls_decode(bytes(s))
            d = d[..., 0] if d.ndim == 3 else d
            bad = int((d != blks[k]).sum()) if d.shape == blks[k].shape else blks[k].size
            kind = 'ok' if bad == 0 else 'corrupt'
        except Exception:
            bad, kind = blks[k].size, 'decode_error'
        res.append((bad / float(full_px), kind))
    return res


def campaign_stream(trials, seed):
    rng = random.Random(seed)
    rows = []
    for img, pgm in [('bm_300x300', PGM),
                     ('bm_1500x1500', os.path.join(ROOT, 'JPEG_ENC_8f.sim', 'images', 'world_gray_1500x1500.pgm'))]:
        src = read_pgm(pgm)
        h, w = src.shape
        cfgs = [('1 lane (single core)', 1, 1, [ic.jpegls_encode(src)])]
        for nh, nv in [(12, 1), (4, 3), (1, 12), (16, 1), (4, 4)]:
            f = os.path.join(ROOT, 'eval', 'ref_8bit', 'output_h%dv%d_%dx%d.jls' % (nh, nv, w, h))
            if os.path.exists(f):
                cfgs.append(('%d lanes h%dv%d (RTL)' % (nh * nv, nh, nv), nh, nv, split_chunks(open(f, 'rb').read())))
        for label, nh, nv, streams in cfgs:
            blks = list(blocks(src, nh, nv))
            res = flip_trials(streams, blks, trials, rng, src.size)
            fr = np.array([r[0] for r in res])
            kinds = [r[1] for r in res]
            rows.append(dict(image=img, config=label, lanes=nh * nv, trials=trials,
                             mean_frame_frac=round(float(fr.mean()), 5), median_frame_frac=round(float(np.median(fr)), 5),
                             p95_frame_frac=round(float(np.percentile(fr, 95)), 5), max_frame_frac=round(float(fr.max()), 5),
                             decode_errors=kinds.count('decode_error'), masked=kinds.count('ok')))
            print(rows[-1], flush=True)
    with open(os.path.join(OUT, 'stream_injection.csv'), 'w', newline='') as f:
        wr = csv.DictWriter(f, fieldnames=list(rows[0])); wr.writeheader(); wr.writerows(rows)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('mode', choices=['rtl', 'stream', 'elab'])
    ap.add_argument('--trials', type=int, default=24)
    ap.add_argument('--jobs', type=int, default=2)
    ap.add_argument('--seed', type=int, default=2026)
    a = ap.parse_args()
    if a.mode == 'elab':
        sys.exit(elaborate())
    if a.mode == 'rtl':
        campaign_rtl(a.trials, a.jobs, a.seed)
    else:
        campaign_stream(a.trials, a.seed)


if __name__ == '__main__':
    main()
