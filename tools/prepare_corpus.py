#!/usr/bin/env python3
"""Build the multi-texture / multi-bit-depth evaluation corpus (reviewer Req 9).

Sources (downloaded to ../datasets, not committed):
  * USC-SIPI "Aerials" volume (sipi.usc.edu/database, aerials.zip): 8-bit aerial /
    satellite photographs (urban, suburban, farmland, coast, airport, ...). Colour
    images are reduced to their green band (one real sensor band, no colour mixing).
  * Sentinel-2A MSI L1C tile T36RUU, 2023-06-02 (Cairo / Nile delta / Eastern Desert,
    0 % cloud; Copernicus data via the public GCS mirror gcp-public-data-sentinel-2),
    bands B04 (red) and B08 (NIR), 10 m, uint16 DN = rho*10000 + 1000 (baseline >= 04.00).

Outputs (eval/corpus):
  aer_<id>.pgm            8-bit, cropped to a multiple of 12 (lane divisibility)
  s2_<name>_16b.pgm       native L1C DN in a 16-bit container (P=16, MAXVAL 65535)
  s2_<name>_12b.pgm       DN - 1000 (documented radiometric offset removed, lossless);
                          only emitted when the tile fits in 12 bits (max < 4096)
16-bit PGMs are big-endian (Netpbm P5 with maxval > 255).
"""
import os, sys, glob
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DS = os.path.join(os.path.dirname(ROOT), 'datasets')
OUT = os.path.join(ROOT, 'eval', 'corpus')

# 1500x1500 (15 km) Sentinel-2 crops chosen for distinct textures (row0, col0, band)
S2_TILES = {
    'nile_agri':    (0,    1500, 'B04'),   # Nile-delta smallholder fields + villages
    'cairo_urban':  (6000, 3000, 'B04'),   # dense urban Cairo, river, bridges
    'pivot_fields': (1500, 9000, 'B04'),   # centre-pivot irrigation on desert
    'desert':       (9000, 7500, 'B04'),   # Eastern Desert, wadis
    'nile_agri_nir': (0,   1500, 'B08'),   # same area, NIR band (different statistics)
    'nile_branch':  (1500, 1500, 'B04'),   # Nile branch, canals, towns
    'delta_west':   (4500, 0,    'B04'),   # western delta fields / desert margin
}
S2_SIZE = 1500


def write_pgm(path, a):
    a = np.ascontiguousarray(a)
    h, w = a.shape
    if a.dtype == np.uint8:
        mx, data = 255, a.tobytes()
    else:
        mx, data = 65535, a.astype('>u2').tobytes()
    with open(path, 'wb') as f:
        f.write(b'P5\n%d %d\n%d\n' % (w, h, mx))
        f.write(data)


def read_pgm(path):
    d = open(path, 'rb').read()
    toks, i = [], 2
    while len(toks) < 3:
        while d[i:i+1].isspace():
            i += 1
        if d[i:i+1] == b'#':
            while d[i:i+1] != b'\n':
                i += 1
            continue
        j = i
        while not d[j:j+1].isspace():
            j += 1
        toks.append(int(d[i:j])); i = j
    w, h, mx = toks
    i += 1
    if mx < 256:
        return np.frombuffer(d[i:i+w*h], np.uint8).reshape(h, w)
    return np.frombuffer(d[i:i+2*w*h], '>u2').reshape(h, w).astype(np.uint16)


def crop12(a):
    h, w = a.shape
    return a[:h - h % 12, :w - w % 12]


def main():
    os.makedirs(OUT, exist_ok=True)
    for f in sorted(glob.glob(os.path.join(DS, 'aerials', 'aerials', '*.tiff'))):
        im = Image.open(f)
        a = np.asarray(im)
        if a.ndim == 3:
            a = a[..., 1]
        a = crop12(a.astype(np.uint8))
        name = 'aer_' + os.path.splitext(os.path.basename(f))[0].replace('.', '_')
        write_pgm(os.path.join(OUT, name + '.pgm'), a)
        print(name, a.shape)
    bands = {}
    for name, (r0, c0, band) in S2_TILES.items():
        if band not in bands:
            npy = os.path.join(DS, 's2_%s.npy' % band)
            if os.path.exists(npy):
                bands[band] = np.load(npy)
            else:                                # decode the original L1C JPEG 2000 band
                import imagecodecs
                jp2 = glob.glob(os.path.join(DS, 'T36RUU_*_%s.jp2' % band))[0]
                bands[band] = imagecodecs.jpeg2k_decode(open(jp2, 'rb').read())
        t = bands[band][r0:r0+S2_SIZE, c0:c0+S2_SIZE].astype(np.uint16)
        write_pgm(os.path.join(OUT, 's2_%s_16b.pgm' % name), t)
        t12 = t.astype(np.int32) - 1000
        fits = t12.min() >= 0 and t12.max() < 4096
        if fits:
            write_pgm(os.path.join(OUT, 's2_%s_12b.pgm' % name), t12.astype(np.uint16))
        print('s2_' + name, t.shape, 'min', t.min(), 'max', t.max(), 'std %.0f' % t.std(),
              '12-bit:' + ('yes' if fits else 'no (max-1000=%d)' % t12.max()))


if __name__ == '__main__':
    main()
