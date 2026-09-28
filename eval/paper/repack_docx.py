#!/usr/bin/env python3
"""repack_docx.py <unpacked_dir> <out.docx> — zip an unpacked .docx ([Content_Types].xml first)."""
import os, sys, zipfile
src, out = sys.argv[1], sys.argv[2]
files = []
for dp, _, fs in os.walk(src):
    for f in fs:
        files.append(os.path.relpath(os.path.join(dp, f), src).replace(os.sep, '/'))
files.sort(key=lambda p: (p != '[Content_Types].xml', not p.startswith('_rels/'), p))
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for p in files:
        z.write(os.path.join(src, p), p)
print('wrote', out, len(files), 'parts')
