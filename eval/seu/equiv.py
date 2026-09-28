import sys, os, subprocess, filecmp
sys.path.insert(0, 'tools')
import seu_inject as S
from concurrent.futures import ThreadPoolExecutor
H = 'D:/techbistro/upwork/JPEG_Encoder_Project/JPEG_ENC_8f/eval/hw'
cases = [('t12', 12, 12, 1), ('t16', 16, 12, 1), ('n16', 16, 12, 1), ('n12', 12, 4, 3), ('t16', 16, 1, 12)]
def one(c):
    name, bpp, nh, nv = c
    tag = '%s__h%dv%d' % (name, nh, nv)
    q = lambda g: '"%s"' % g.replace('"', '\\"')
    gen = ['N_E=12', 'N_H=%d' % nh, 'N_V=%d' % nv, 'IMG_W=300', 'IMG_H=300', 'MAX_BYTES_PER_SLICE=60000',
           'LB_DEPTH=1024', 'BPP=%d' % bpp, 'HEXFILE="%s/hex/%s.hex"' % (H, tag)]
    sn = 'eq_' + tag
    cmd = ' '.join(['"%s/xelab.bat"' % S.BIN, '--debug off --relax --mt 2',
                    '-L xil_defaultlib -L fifo_generator_v13_2_11 -L unisims_ver -L unimacro_ver -L secureip -L xpm'] +
                   ['-generic_top %s' % q(g) for g in gen] + ['--snapshot %s xil_defaultlib.tb_jls_seu xil_defaultlib.glbl' % sn])
    S.run(cmd, os.path.join(S.WD, 'elab_%s.log' % sn))
    of = '%s/equiv_%s.jls' % (H, tag)
    S.run('%s/xsim.bat %s -R -testplusarg "outfile=%s"' % (S.BIN, sn, of), os.path.join(S.WD, 'sim_%s.log' % sn))
    same = os.path.exists(of) and filecmp.cmp(of, '%s/%s.jls' % (H, tag), shallow=False)
    return tag, same
with ThreadPoolExecutor(2) as ex:
    for t, ok in ex.map(one, cases):
        print(t, 'BYTE-IDENTICAL to pre-shortcut RTL' if ok else 'DIFFERENT/MISSING')
