#!/usr/bin/env python3
"""Run the jls_encoder_axis RTL (tb_jls_wide) on one image / split / bit depth and verify.

  python tools/run_rtl_sim.py compile
  python tools/run_rtl_sim.py run <name> <in.pgm> <N_H> <N_V> [--bpp 8] [--lb 1024] [--elab-only|--run-only]

Output: eval/hw/<name>__h<NH>v<NV>.jls (+ .log). Verification decodes every lane with
CharLS (imagecodecs) and reassembles the grid against the source image (lossless check).
Snapshots are named after the output so several runs can execute concurrently once
elaborated (compile once, elaborate sequentially, simulate in parallel).
"""
import os, sys, subprocess, argparse
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
from prepare_corpus import read_pgm  # noqa: E402
from reference_baseline import split_chunks, blocks  # noqa: E402

XSIM = os.path.join(ROOT, 'JPEG_ENC_8f.sim', 'sim_1', 'behav', 'xsim')
HW = os.path.join(ROOT, 'eval', 'hw')
BIN = 'C:/Xilinx/Vivado/2024.2/bin'
LIBS = ['-L', 'xil_defaultlib', '-L', 'fifo_generator_v13_2_11', '-L', 'unisims_ver',
        '-L', 'unimacro_ver', '-L', 'secureip', '-L', 'xpm']


def sh(cmd, log):
    with open(log, 'w') as f:
        r = subprocess.run(cmd, cwd=XSIM, stdout=f, stderr=subprocess.STDOUT, shell=False)
    return r.returncode


def compile_all():
    rc = sh([BIN + '/xvlog.bat', '--relax', '-prj', 'wide_axis_vlog.prj'], os.path.join(XSIM, 'xvlog_bpp.log'))
    print('xvlog rc', rc)
    return rc


def verify(jls_path, pgm, nh, nv):
    import imagecodecs as ic
    a = read_pgm(pgm)
    ch = split_chunks(open(jls_path, 'rb').read())
    if len(ch) != nh * nv:
        return False, 'chunks %d != %d' % (len(ch), nh * nv)
    for k, (c, b) in enumerate(zip(ch, blocks(a, nh, nv))):
        d = ic.jpegls_decode(c)
        d = d[..., 0] if d.ndim == 3 else d
        if d.shape != b.shape or not (d == b).all():
            return False, 'lane %d mismatch' % k
    return True, 'exact'


def run(name, pgm, nh, nv, bpp, lb, elab=True, sim=True):
    os.makedirs(os.path.join(HW, 'hex'), exist_ok=True)
    a = read_pgm(pgm)
    h, w = a.shape
    ne = nh * nv
    tag = '%s__h%dv%d' % (name, nh, nv)
    hexf = os.path.join(HW, 'hex', tag + '.hex').replace('\\', '/')
    out = os.path.join(HW, tag + '.jls').replace('\\', '/')
    snap = 'sn_' + tag.replace('-', '_')
    if elab:
        subprocess.run([sys.executable, os.path.join(ROOT, 'tools', 'make_strided_hex.py'), pgm, hexf,
                        str(nh), str(nv)], check=True, stdout=subprocess.DEVNULL)
        maxb = int(w * h * (2 if bpp > 8 else 1) / ne * 1.3) + 4096
        gen = ['N_E=%d' % ne, 'N_H=%d' % nh, 'N_V=%d' % nv, 'IMG_W=%d' % w, 'IMG_H=%d' % h,
               'MAX_BYTES_PER_SLICE=%d' % maxb, 'HEXFILE="%s"' % hexf, 'BPP=%d' % bpp,
               'LB_DEPTH=%d' % lb, 'OUTFILE="%s"' % out]
        # cmd.exe (the .bat wrapper) splits on '=', so each generic is passed quoted,
        # with string values as \"...\" -> xelab sees HEXFILE="D:/..."
        q = lambda g: '"%s"' % g.replace('"', '\\"')
        cmd = ' '.join(['"%s/xelab.bat"' % BIN, '--debug off --relax --mt 2'] + LIBS +
                       ['-generic_top %s' % q(g) for g in gen] +
                       ['--snapshot', snap, 'xil_defaultlib.tb_jls_wide', 'xil_defaultlib.glbl'])
        rc = sh(cmd, os.path.join(HW, tag + '.elab.log'))
        if rc:
            print(tag, 'ELAB FAILED rc', rc); return None
    if sim:
        if os.path.exists(out):
            os.remove(out)
        rc = sh([BIN + '/xsim.bat', snap, '-R'], os.path.join(HW, tag + '.sim.log'))
        if not os.path.exists(out):
            print(tag, 'NO OUTPUT (rc %d)' % rc); return None
        ok, msg = verify(out, pgm, nh, nv)
        raw = w * h * bpp / 8.0
        n = os.path.getsize(out)
        print('RESULT %s bpp=%d %dx%d h%dv%d bytes=%d CR=%.4f lossless=%s' % (name, bpp, w, h, nh, nv, n, raw / n, msg))
        return ok
    return True


def main():
    if sys.argv[1] == 'compile':
        sys.exit(compile_all())
    ap = argparse.ArgumentParser()
    ap.add_argument('mode'); ap.add_argument('name'); ap.add_argument('pgm')
    ap.add_argument('nh', type=int); ap.add_argument('nv', type=int)
    ap.add_argument('--bpp', type=int, default=8); ap.add_argument('--lb', type=int, default=1024)
    ap.add_argument('--elab-only', action='store_true'); ap.add_argument('--run-only', action='store_true')
    a = ap.parse_args()
    r = run(a.name, os.path.abspath(a.pgm), a.nh, a.nv, a.bpp, a.lb,
            elab=not a.run_only, sim=not a.elab_only)
    sys.exit(0 if r else 1)


if __name__ == '__main__':
    main()
