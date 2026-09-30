#!/usr/bin/env python3
"""Final V5 condensation pass (runs after format_v5.py).

Tables (11 -> 9):
  * Table II (device resources) removed; one sentence in Section VI instead
  * Tables V (16-lane, by direction) and VI (by lane count / bit depth) merged into one
    utilization + WNS table; values are read from the two tables, WNS of the 12-lane builds
    from Table III
  * Table III: "Single core (fmax)" row removed (it restated the 16-lane fmax-sweep row)
  * best/worst Table: Blue Marble rows removed (identical to the Table IV rows)
  * every "Table N" reference in the body text renumbered
Prose: Section IV condensed to one paragraph; Section V cyclic-scheduling sentences removed
(each lane encodes exactly one block in the implemented design) and the generic FIFO/CDC
paragraph shortened; framing sentences in Sections I and III trimmed; Section VI opening
merged and corrected (demo ROM size).
usage: python eval/paper/condense_v5.py <unpacked_dir>
"""
import os, re, sys
from xml.sax.saxutils import escape

D = sys.argv[1]
DOC = os.path.join(D, 'word', 'document.xml')
x = open(DOC, encoding='utf8').read()
TRUN = r'<w:t(?: [^>]*)?>([^<]*)</w:t>'


def paras():
    return list(re.finditer(r'<w:p[ >].*?</w:p>', x, re.S))


def vis(p):
    return ''.join(re.findall(TRUN, p))


def find_par(txt):
    for m in paras():
        if txt in vis(m.group(0)):
            return m.start(), m.end()
    raise KeyError(txt[:60])


def replace_text(old, new):
    global x
    a, b = find_par(old)
    p = x[a:b]
    ts = [(m.start(1), m.end(1)) for m in re.finditer(TRUN, p)]
    starts, pos = [], 0
    for s, e in ts:
        starts.append(pos); pos += e - s
    flat = ''.join(p[s:e] for s, e in ts)
    k = flat.index(old)
    j0 = max(i for i, s in enumerate(starts) if s <= k)
    j1 = max(i for i, s in enumerate(starts) if s < k + len(old))
    assert 'fldChar' not in p[ts[j0][0]:ts[j1][1]], 'spans a field: ' + old[:40]
    head = p[ts[j0][0]:ts[j0][1]][:k - starts[j0]]
    tail = p[ts[j1][0]:ts[j1][1]][k + len(old) - starts[j1]:]
    for j in range(j1, j0 - 1, -1):
        s, e = ts[j]
        p = p[:s] + (head + escape(new) + tail if j == j0 else '') + p[e:]
    x = x[:a] + p.replace('<w:t>', '<w:t xml:space="preserve">') + x[b:]


def set_paragraph(key, text):
    global x
    a, b = find_par(key)
    p = x[a:b]
    assert 'fldChar' not in p, 'paragraph has fields: ' + key
    m = re.search(r'<w:r>(<w:rPr>.*?</w:rPr>)?', p)
    rpr = (m.group(1) or '') if m else ''
    head = p[:p.index('</w:pPr>') + 8] if '</w:pPr>' in p else p[:p.index('>') + 1]
    x = x[:a] + head + '<w:r>%s<w:t xml:space="preserve">%s</w:t></w:r></w:p>' % (rpr, escape(text)) + x[b:]


def delete_paragraph(key, allow_ref=None):
    """Delete a paragraph; a paragraph with fields is deleted only if every field is a REF
    to the bookmark allow_ref (a citation that stays cited elsewhere)."""
    global x
    a, b = find_par(key)
    p = x[a:b]
    if 'fldChar' in p:
        instr = re.findall(r'<w:instrText[^>]*>([^<]*)</w:instrText>', p)
        assert allow_ref and all(allow_ref in i for i in instr if i.strip()), 'refuse to delete: ' + key
    assert 'bookmarkStart' not in p, 'paragraph holds a bookmark: ' + key
    x = x[:a] + x[b:]


def tables():
    return [(m.start(), x.index('</w:tbl>', m.start()) + 8) for m in re.finditer(r'<w:tbl>', x)]


def rows_of(k):
    a, b = tables()[k]
    return re.findall(r'<w:tr[ >].*?</w:tr>', x[a:b], re.S)


def cells_txt(row):
    return [vis(c) for c in re.findall(r'<w:tc>.*?</w:tc>', row, re.S)]


def delete_rows(k, pred):
    global x
    a, b = tables()[k]
    t = x[a:b]
    for r in re.findall(r'<w:tr[ >].*?</w:tr>', t, re.S)[1:]:
        if pred(cells_txt(r)):
            t = t.replace(r, '', 1)
    x = x[:a] + t + x[b:]


def caption_span(k):
    a, _ = tables()[k]
    p0 = x.rfind('<w:p ', 0, a)
    return p0, a


def strip_ids(s):
    return re.sub(r' w14:(paraId|textId)="[0-9A-F]+"', '', s)


def set_par_text(par, text):
    m = re.search(r'<w:r>(<w:rPr>.*?</w:rPr>)?', par)
    rpr = (m.group(1) or '') if m else ''
    head = par[:par.index('</w:pPr>') + 8] if '</w:pPr>' in par else par[:par.index('>') + 1]
    return head + '<w:r>%s<w:t xml:space="preserve">%s</w:t></w:r></w:p>' % (rpr, escape(text))


def build_table(tbl, rows, widths):
    tblpr = re.search(r'<w:tblPr>.*?</w:tblPr>', tbl, re.S).group(0)
    tblpr = re.sub(r'<w:tblW [^>]*/>', '<w:tblW w:w="%d" w:type="dxa"/>' % sum(widths), tblpr)
    trs = re.findall(r'<w:tr[ >].*?</w:tr>', tbl, re.S)
    tr_open = re.match(r'<w:tr[^>]*>', trs[0]).group(0)
    trpr = (re.search(r'<w:trPr>.*?</w:trPr>', trs[0], re.S) or [''])[0] if '<w:trPr>' in trs[0] else ''
    hcell = re.findall(r'<w:tc>.*?</w:tc>', trs[0], re.S)[0]
    bcell = re.findall(r'<w:tc>.*?</w:tc>', trs[1], re.S)[0]
    out = ['<w:tbl>', tblpr, '<w:tblGrid>' + ''.join('<w:gridCol w:w="%d"/>' % w for w in widths) + '</w:tblGrid>']
    for ri, r in enumerate(rows):
        tmpl = hcell if ri == 0 else bcell
        out.append(strip_ids(tr_open) + trpr)
        for ci, txt in enumerate(r):
            c = re.sub(r'<w:tcW w:w="\d+"', '<w:tcW w:w="%d"' % widths[ci], tmpl)
            par = re.search(r'<w:p[ >].*?</w:p>', c, re.S).group(0)
            c = c.replace(par, set_par_text(strip_ids(par), txt))
            out.append(c)
        out.append('</w:tr>')
    return ''.join(out) + '</w:tbl>'


# ----------------------------------------------------------------- identify tables by caption
def caption_text(k):
    a, b = caption_span(k)
    return vis(x[a:b])


def idx(prefix):
    hits = [k for k in range(len(tables())) if caption_text(k).startswith(prefix)]
    assert len(hits) == 1, (prefix, hits)
    return hits[0]


assert len(tables()) == 11, len(tables())

# 1. best/worst table: drop the Blue Marble rows (they repeat the direction table)
delete_rows(idx('BEST AND WORST IMAGE'), lambda c: c[0].startswith('Blue Marble'))

# 2. merge the two utilization tables
kV, kVI, kIII = idx('POST-IMPLEMENTATION RESOURCE UTILIZATION BY SPLIT'), idx('POST-IMPLEMENTATION RESOURCE UTILIZATION BY LANE'), idx('TIMING-CLOSED THROUGHPUT')
wns12 = {}
for c in (cells_txt(r) for r in rows_of(kIII)[1:]):
    m = re.match(r'12-lane, (\d+)-bit', c[0])
    if m:
        wns12[m.group(1)] = c[2]
merged = [['Configuration', 'LUT (%)', 'FF (%)', 'BRAM (%)', 'DSP (%)', 'WNS (ns)']]
for c in (cells_txt(r) for r in rows_of(kVI)[1:]):
    m = re.match(r'12 lanes @ 45 MHz, (\d+)-bit', c[0])
    if m:
        merged.append(['12 lanes @ 45 MHz, vertical 12×1, %s-bit' % m.group(1)] + c[1:5] + [wns12[m.group(1)]])
for c in (cells_txt(r) for r in rows_of(kV)[1:]):
    name, grid = c[0].split(' (')
    merged.append(['16 lanes @ 32 MHz, %s %s, 8-bit' % (name.lower(), grid.rstrip(')'))] + c[1:6])
assert len(merged) == 7, merged
aV, bV = tables()[kV]
x = x[:aV] + build_table(x[aV:bV], merged, [2000, 560, 560, 560, 560, 560]) + x[bV:]
ca, cb = caption_span(kV)
x = x[:ca] + set_par_text(x[ca:cb], 'POST-IMPLEMENTATION RESOURCE UTILIZATION AND WORST NEGATIVE SLACK') + x[cb:]
ca, _ = caption_span(kVI)
_, bVI = tables()[kVI]
x = x[:ca] + x[bVI:]

# 3. throughput table: drop the "Single core (fmax)" row (restated the 16-lane sweep)
delete_rows(idx('TIMING-CLOSED THROUGHPUT'), lambda c: c[0].startswith('Single core'))

# 4. device-resource table -> sentence
kII = idx('ARTIX-7 PROTOTYPING PLATFORM')
ca, _ = caption_span(kII)
_, bII = tables()[kII]
nxt = re.match(r'<w:p[ >].*?</w:p>', x[bII:], re.S)
if nxt and not vis(nxt.group(0)).strip():
    bII += nxt.end()                                     # empty spacer paragraph after the table
x = x[:ca] + x[bII:]
assert len(tables()) == 9, len(tables())

# the only text reference to the removed Table II becomes the device sentence (before renumbering)
replace_text(' Table II lists the key parameters of the target platform.',
             ' The device provides 134,600 LUTs, 269,200 flip-flops, 365 Block-RAM tiles of 36 Kb (13.1 Mb) and 740 '
             'DSP slices.')

# ----------------------------------------------------------------- renumber "Table N" in the text
NEW = {'I': 'I', 'III': 'II', 'IV': 'III', 'V': 'IV', 'VI': 'IV', 'VII': 'V', 'VIII': 'VI', 'IX': 'VII', 'X': 'VIII', 'XI': 'IX'}
rx = re.compile(r'\b(Tables?) ([IVX]+)\b(?: and ([IVX]+)\b)?')


def ren(m):
    a = NEW[m.group(2)]
    if not m.group(3):
        return '%s %s' % (m.group(1), a)
    b = NEW[m.group(3)]
    return 'Table %s' % a if a == b else 'Tables %s and %s' % (a, b)


body_end = min(m.start() for m in paras() if '<w:pStyle w:val="references"/>' in m.group(0))
def fix_t(m):
    return m.group(1) + rx.sub(ren, m.group(2)) + m.group(3)
x = re.sub(r'(<w:t(?: [^>]*)?>)([^<]*)(</w:t>)', fix_t, x[:body_end]) + x[body_end:]

# ----------------------------------------------------------------- text that described the old tables
set_paragraph('A key question for parallelization is the resource overhead',
    'A key question for parallelization is the resource overhead of hosting multiple cores. Table IV reports the '
    'post-route utilization and worst negative slack of the 12-lane builds at 8, 12 and 16 bit and of the 16-lane '
    'build in all three split directions; the small differences between directions come only from splitter '
    'routing, not from the encoder logic, which is identical.')
replace_text('The 12- and 16-bit builds (Table IV) roughly double', 'The 12- and 16-bit builds roughly double')
replace_text('Table IV list the builds of the parameterized RTL', 'Table IV lists the builds of the parameterized RTL')
set_paragraph('Compression was evaluated on grayscale Earth-observation imagery',
    'Compression was evaluated in all three split directions on grayscale NASA Blue Marble imagery from 300×300 to '
    '5000×5000 pixels (and one 16000×5000 frame) and, in Section VI-B, on aerial and Sentinel-2 imagery at 8, 12 and '
    '16 bit. Throughput and timing were characterised on the synthesized 12-lane (45 MHz) and 16-lane (32 MHz) builds '
    'and by the implementation-frequency sweep. The on-chip demonstration harness stores its test image in Block RAM '
    'and is therefore limited to a few hundred pixels per side (256×256 or 300×300 in the builds reported); larger '
    'images are streamed into the encoder IP over an AXI4-Stream interface, so throughput equals lanes × clock '
    'independently of image size.')
delete_paragraph('Because throughput is set by the lane count and clock and not by image size, evaluation')

# ----------------------------------------------------------------- Section IV -> one paragraph
replace_text(') is rooted in the LOCO-I (LOw COmplexity LOssless COmpression for Images) algorithm. Unlike '
             'transform-based codecs such as JPEG 2000, which rely on computationally intensive discrete wavelet '
             'transforms, JPEG-LS uses a non-linear predictor that exploits local spatial correlations without transform '
             'overhead, making it well-suited for resource-constrained FPGA implementations. The algorithm switches '
             'between two primary modes based on local image characteristics: Regular Mode and Run Mode.',
             ') is based on the LOCO-I algorithm. Each pixel is predicted from its causal neighbours a (left), b (above), '
             'c (above-left) and d (above-right) by the median edge detector (ŷ = min(a, b) if c ≥ max(a, b), '
             'max(a, b) if c ≤ min(a, b), and a + b − c otherwise). The local gradients select one of 365 contexts, '
             'whose statistics A, B, C and N correct the prediction bias and set the parameter k of the Golomb-Rice code '
             'for the residual; smooth regions are coded in run mode. Because the context statistics are updated after '
             'every pixel, each pixel depends on its predecessor (a read-after-write dependency), which limits a single '
             'core to one pixel per clock and motivates spatial parallelization.')
REF4 = '_Ref197465886'
for k in ['Causal Template and Prediction', 'For each pixel to be compressed, the algorithm uses a causal template',
          'Context Modeling and Parameter Update', 'The local gradients are quantized into 365 possible contexts',
          'Entropy Coding', 'The bias-corrected prediction error is mapped']:
    delete_paragraph(k, allow_ref=REF4)
assert REF4 in x, 'reference [4] lost its last field citation'

# ----------------------------------------------------------------- Section V: generic / inaccurate sentences
set_paragraph('The use of multiple cores implemented on an FPGA',
    'Running N independent encoder cores in parallel raises the throughput N-fold; each core needs its own input '
    'FIFO and a clock-domain crossing (CDC) to the rest of the system.')
replace_text(' The cores operate cyclically – after completing the processing of their stripe, a core transitions to '
             'the next unprocessed stripe.', '')
replace_text(' The number of cores must be sufficient so that after completing the processing of its column, the i-th '
             'core can transition to the next unprocessed one.', '')

# ----------------------------------------------------------------- Sections I and III: framing sentences
replace_text('The modern landscape of Earth Observation (EO) is characterized by a rapid escalation in the resolution '
             'and spectral depth of optical sensor payloads. Advanced satellite systems are currently capable of '
             'producing massive volumes of raw data that far exceed',
             'Earth-observation (EO) payloads now produce raw data volumes that far exceed')
replace_text(' Transform-based codecs such as JPEG 2000 achieve high efficiency but their discrete wavelet transform and '
             'tier-2 bitplane coding are costly to implement in real time on the power-constrained hardware of '
             'microsatellites.',
             ' Transform coders such as JPEG 2000 are costly to run in real time on microsatellite hardware.')
replace_text('Given the volume of data that needs to be processed, the satellite\'s onboard system for scientific data '
             'collection and storage (SDCS) must apply preliminary compression and temporary buffer storage before '
             'downlinking. Regardless of the data volume to be transmitted, the satellite channel speed is always lower '
             'and requires compression. ',
             'The onboard data collection and storage system therefore compresses and buffers the data before downlink. ')

# ----------------------------------------------------------------- accuracy fixes found in the prose pass
def replace_between(start, end, new):
    """Replace the text from `start` through `end` (inclusive) inside one paragraph."""
    a, b = find_par(start)
    flat = vis(x[a:b])
    i = flat.index(start)
    j = flat.index(end, i) + len(end)
    replace_text(flat[i:j], new)


replace_text('On our Artix-7 (-2) implementation a single core closes timing at an implementation frequency of about '
             'fmax = 53 MHz, i.e. 53 Mpixel/s ≈ 0.43 Gbit/s at 8-bit;',
             'On our Artix-7 (-2) device each lane closes timing at up to fmax = 53.3 MHz (frequency sweep of the '
             '16-lane build, Section VI-A), i.e. 53 Mpixel/s ≈ 0.43 Gbit/s per lane at 8 bit;')
replace_text('Across the corpus the three directions compress within about 1–4 % of one another',
             'Across the Blue Marble sizes the three directions compress within about 1–4 % of one another')
replace_between('This corrects the earlier prototype figure', 'for mission-scale images. ', '')

open(DOC, 'w', encoding='utf8').write(x)
print('condensed', DOC)
