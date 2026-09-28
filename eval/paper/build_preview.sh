#!/usr/bin/env bash
# build_preview.sh <out.docx> [PREVIEW=1]: fresh unpack of V4 -> update tables -> repack
set -e
S="C:/Users/admin/AppData/Local/Temp/claude/D--techbistro-upwork-JPEG-Encoder-Project-JPEG-ENC-8f/3ee642f1-327a-4dcb-b9cb-b0ffe6074885/scratchpad"
rm -rf "$S/v5p"; mkdir -p "$S/v5p"
python -c "import zipfile; zipfile.ZipFile(r'C:/Users/admin/Downloads/Hrytsko_DESSERT_V4.docx').extractall(r'$S/v5p')"
PYTHONIOENCODING=utf8 python eval/paper/update_v4_tables.py "$S/v5p"
python eval/paper/repack_docx.py "$S/v5p" "$1"
