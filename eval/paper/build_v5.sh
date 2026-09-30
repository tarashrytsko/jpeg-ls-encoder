#!/usr/bin/env bash
# build_v5.sh <V4.docx> <out.docx>: V4 -> update_v4_tables.py -> revise_v5.py -> repack
set -e
H="$(cd "$(dirname "$0")" && pwd)"; ROOT="$H/../.."
W="${TMPDIR:-/tmp}/v5_build_$$"; rm -rf "$W"; mkdir -p "$W"
python -c "import sys,zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$1" "$W"
( cd "$ROOT" && PYTHONIOENCODING=utf8 python eval/paper/update_v4_tables.py "$W" && PYTHONIOENCODING=utf8 python eval/paper/revise_v5.py "$W" && PYTHONIOENCODING=utf8 python eval/paper/format_v5.py "$W" && PYTHONIOENCODING=utf8 python eval/paper/condense_v5.py "$W" )
python "$H/repack_docx.py" "$W" "$2"
rm -rf "$W"
