#!/usr/bin/env python3
"""DESSERT / IEEE-template compliance pass + prose condensation (runs after revise_v5.py).

Template fixes (checked against DESSERT2025_paper_example.docx and the IEEE A4 conference
template):
  3  two-column body sections: column gap 18 pt (360 twips), as in the templates
  6  figure captions: 'figure caption' style, template numbering suppressed so the
     existing SEQ fields and in-text REF fields keep working; "Fig. N." with a period
  7  table cells: 'table col head' (header row) / 'table copy' (body), centred as before
  8  references renumbered in order of first citation (Hinnerson moves from [6] to [13]);
     every visible citation - REF field result or plain text - is remapped at once
  9  second author e-mail: ...@lpnu -> ...@lpnu.ua (text and mailto target)
 11  "Abstract—" / "Keywords—" (IEEE em dash)
Prose condensation (reviewer-neutral): Section II, Section VII (merged into one paragraph
next to Table X), Section VIII.
usage: python eval/paper/format_v5.py <unpacked_dir>
"""
import os, re, sys, csv
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
from make_review_report import power  # noqa: E402

E = os.path.join(ROOT, 'eval')
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
    """Replace text spanning runs of one paragraph; never across a field."""
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


def delete_paragraph(key):
    global x
    a, b = find_par(key)
    assert 'fldChar' not in x[a:b] and 'bookmarkStart' not in x[a:b], 'refuse to delete: ' + key
    x = x[:a] + x[b:]


# ----------------------------------------------------------------- data for Section VII
P = {t: power(os.path.join(E, 'power', t + '_power_saif.rpt')) for t in ['n12_45', 'n16_32']}
mc = open(os.path.join(E, 'baseline', 'charls_multicore.txt')).read()
cpu1 = float(re.search(r'1 process : ([\d.]+)', mc).group(1))
cpuN = float(re.search(r'(\d+) processes: ([\d.]+)', mc).group(2))
ncore = int(re.search(r'(\d+) processes:', mc).group(1))
cpu_full = float(re.search(r'([\d.]+) Mpixel/s', open(os.path.join(E, 'baseline', 'charls_throughput.txt')).read()).group(1))
end = max(int(re.search(r'last_in_to_all_lanes_done=(\d+)', open(os.path.join(E, 'hw', t + '__h12v1.sim.log')).read()).group(1))
          for t in ['lat8_300', 'lat8_1500', 'lat16_300'])
p12 = float(P['n12_45']['total'])

# ----------------------------------------------------------------- option C: Section II
set_paragraph('Recent research in lossless image compression has shifted',
              'Recent lossless-compression work has moved to parallel hardware, combining pipelining and multiple '
              'cores to keep pace with high-speed sensor interfaces.')
replace_text(' It supports both lossless and near-lossless modes and can be targeted at Xilinx, Intel, and Microchip FPGAs.', '')
set_paragraph('These commercial solutions demonstrate the feasibility',
              'These cores are closed-source, which limits customization to mission-specific I/O interfaces or '
              'radiation-hardened configurations.')
replace_text(' The algorithm was compared with H.264 (AVC), HEVC (H.265), and other codecs.', '')
set_paragraph('Existing works focus on general-purpose hardware',
              'These works target general-purpose hardware, camera formats or internal buffering rather than '
              'continuous raw-pixel scanner streams, and few offer a model for scaling throughput with multiple '
              'FPGA cores under resource constraints.')
replace_text('It should be noted that conducting rigorous evaluation of FPGA-implemented designs, particularly those '
             'involving parallelized data processing, is not feasible without the development and use of an IP Core '
             'Generator ', 'Evaluating such parallel FPGA designs systematically relies on an IP-core generator ')

# ----------------------------------------------------------------- option C: Section VII (one paragraph + Table X)
for k in ['While parallel FPGAs offer significant advantages', 'FPGAs process pixels as they arrive from the sensor',
          'GPUs reach high aggregate throughput', 'FPGA: Deterministic Streaming', 'GPU: Massive Throughput',
          'CPU: Programmatic Flexibility']:
    delete_paragraph(k)
set_paragraph('CPUs offer the most flexible toolchain',
    'Table X compares the platforms on throughput, power, energy per pixel and latency. The FPGA processes pixels as '
    'they arrive, without frame buffers: the 12-lane build sustains 540 Mpixel/s at %.2f W on chip (about 1 nJ per '
    'pixel) and delivers the last compressed byte about %.1f µs after the last pixel. On the authors\' host (Intel '
    'Core i5-11400H) CharLS 2.4.3 reaches %.0f Mpixel/s on a whole 4992×4992 frame, %.0f Mpixel/s on the same 12 '
    'strips as the hardware and %.0f Mpixel/s with %d processes (%.0f %% of the FPGA rate); at the processor\'s rated '
    '45 W (not measured) this costs two orders of magnitude more energy per pixel, and each frame must be buffered '
    'first. GPUs reach high throughput (26.3× over sequential software for CUDA JPEG-LS [12]) but draw 200–450 W and '
    'work in batches, which suits ground-segment rather than onboard processing. An embedded ARM SoC was not measured. '
    'On these axes the FPGA is the most appropriate onboard platform.' % (
        p12, end / 45.0, cpu_full, cpu1, cpuN, ncore, 100 * cpuN / 540))

# ----------------------------------------------------------------- option C: Section VIII
set_paragraph('The choice of spatial splitting strategy is governed', 'The results suggest three mission-specific choices:')
set_paragraph('Latency-critical missions',
    'Latency-critical missions (disaster response, surveillance): all directions have the same deterministic latency '
    '(about %d cycles from the last pixel to the last compressed byte), so the choice follows resource fit; vertical '
    'splitting engages every lane from the first scan lines and uses the fewest DSP slices.' % end)
set_paragraph('Bandwidth-constrained missions',
    'Bandwidth-constrained missions (Sich-3O class): the directions compress within about 1–4 % at mission-scale '
    'block sizes, block and vertical marginally ahead of horizontal; on sensor-like imagery lossless ratios stay below '
    '2.5:1 (Tables VIII and IX), so these missions should plan for near-lossless coding.')
set_paragraph('Resource-constrained (CubeSat/NanoSat) missions',
    'Resource-constrained (CubeSat/NanoSat) missions: vertical splitting is the most economical (24 % of LUTs and 8 % '
    'of Block RAM at 12 lanes, under 30 % and 11 % at 16 lanes), leaving most of the device for other subsystems.')
set_paragraph('Dependability in orbit deserves explicit treatment',
    'Dependability in orbit. Because JPEG-LS is context-adaptive, a single-event upset (SEU) in the compressed data or '
    'in the encoder state can corrupt the rest of a slice. Each lane is an independent JPEG-LS stream, so an upset is '
    'confined to one block; restart markers inside each lane stream (not implemented in this work) would bound it '
    'further. Candidate mitigations are ECC or scrubbing of the Block-RAM line buffers and FIFOs, protection of the '
    'LUT-RAM contexts, triple-modular redundancy on the control FSMs and configuration-memory scrubbing; a beam-test '
    'SEU cross-section is future work.')
set_paragraph('Memory protection follows from these results',
    'The line buffer, the most sensitive structure in these injections, and the FIFOs are Block RAM, for which the 7-series '
    'devices provide built-in single-error correction on 64-bit-wide ports; the context memories (366 × 26 + 364 × 8 '
    'bits per lane at 8 bit) are LUT RAM. Because every lane re-initialises its contexts at the start of each block, a '
    'context upset cannot outlive its block.')

replace_text('compare it with the vector-less estimates reported here', 'compare it with the activity-based estimates reported here')

# ----------------------------------------------------------------- fix 11: IEEE em dash
replace_text('Abstract – ', 'Abstract—')
replace_text('Keywords – ', 'Keywords—')

# ----------------------------------------------------------------- fix 9: e-mail
replace_text('valerii.s.hlukhov@lpnu', 'valerii.s.hlukhov@lpnu.ua')
ra = os.path.join(D, 'word', '_rels', 'document.xml.rels')
rels = open(ra, encoding='utf8').read()
rels = re.sub(r'mailto:valerii\.s\.hlukhov@lpnu(?!\.ua)', 'mailto:valerii.s.hlukhov@lpnu.ua', rels)
open(ra, 'w', encoding='utf8').write(rels)

# ----------------------------------------------------------------- fix 3: column gap
x = x.replace('<w:cols w:num="2" w:space="720"/>', '<w:cols w:num="2" w:space="360"/>')

# ----------------------------------------------------------------- fix 6: figure captions
def fix_caption(m):
    p = m.group(0)
    if '<w:pStyle w:val="Caption"/>' not in p or 'SEQ Fig.' not in p:
        return p
    p = p.replace('<w:pStyle w:val="Caption"/>', '<w:pStyle w:val="figurecaption"/><w:numPr><w:ilvl w:val="0"/><w:numId w:val="0"/></w:numPr>', 1)
    # text after the SEQ field: " Caption" -> ". Caption." ; drop the direct bold-off/size (style is 8 pt regular)
    tail = p.rindex('<w:fldChar w:fldCharType="end"/>')
    t = re.search(TRUN, p[tail:])
    cap = t.group(1).lstrip()
    cap = cap if cap.endswith('.') else cap + '.'
    s0 = tail + t.start(1)
    return p[:s0] + '. ' + escape(cap) + p[tail + t.end(1):]
x = re.sub(r'<w:p[ >].*?</w:p>', fix_caption, x, flags=re.S)

# ----------------------------------------------------------------- fix 7: table cell styles
def style_cells(tm):
    t = tm.group(0)
    rows = re.findall(r'<w:tr[ >].*?</w:tr>', t, re.S)
    out = t
    for ri, r in enumerate(rows):
        sty = 'tablecolhead' if ri == 0 else 'tablecopy'
        def fix_p(pm):
            p = pm.group(0)
            if '<w:pStyle ' in p:
                return p
            jc = '' if '<w:jc ' in p else '<w:jc w:val="center"/>'
            if '<w:pPr>' in p:
                p = p.replace('<w:pPr>', '<w:pPr><w:pStyle w:val="%s"/>' % sty, 1)
                if jc:
                    p = re.sub(r'(<w:pPr>.*?)(<w:rPr>|</w:pPr>)', lambda q: q.group(1) + jc + q.group(2), p, count=1, flags=re.S)
            else:
                p = re.sub(r'(<w:p(?: [^>]*)?>)', r'\1<w:pPr><w:pStyle w:val="%s"/>%s</w:pPr>' % (sty, jc), p, count=1)
            return p
        out = out.replace(r, re.sub(r'<w:p[ >].*?</w:p>', fix_p, r, flags=re.S), 1)
    return out
x = re.sub(r'<w:tbl>.*?</w:tbl>', style_cells, x, flags=re.S)

# ----------------------------------------------------------------- fix 8: citation order
ref_hdr = x.index('>References<') if '>References<' in x else None
refs = [m for m in paras() if '<w:pStyle w:val="references"/>' in m.group(0) and vis(m.group(0)).strip()]
assert len(refs) == 17, len(refs)
old6, old13 = refs[5], refs[12]
assert 'Hinnerson' in vis(old6.group(0)) and 'Sullivan' in vis(old13.group(0))
block6 = x[old6.start():old6.end()]
x = x[:old13.end()] + block6 + x[old13.end():]            # insert after [13] first (later offset)
x = x[:old6.start()] + x[old6.end():]                      # then remove the original
new_of = {6: 13}
new_of.update({o: o - 1 for o in range(7, 14)})
body_end = min(m.start() for m in paras() if '<w:pStyle w:val="references"/>' in m.group(0))
body = x[:body_end]
def remap(m):
    s = m.group(0)
    return re.sub(r'\[(\d+)\]', lambda q: '[%d]' % new_of.get(int(q.group(1)), int(q.group(1))), s)
body = re.sub(r'(<w:t(?: [^>]*)?>)([^<]*)(</w:t>)', lambda m: m.group(1) + remap(m) [len(m.group(1)):-len(m.group(3))] + m.group(3) if '[' in m.group(2) else m.group(0), body)
x = body + x[body_end:]

open(DOC, 'w', encoding='utf8').write(x)
print('formatted', DOC)
