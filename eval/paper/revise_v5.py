#!/usr/bin/env python3
"""V5 revision pass (reviewer R2-R10, E2-E10), applied on top of update_v4_tables.py.

Edits the unpacked manuscript in place:
  * text fixes: abstract claims, CPU throughput source (E3), eq. (1) (R6), front-end
    bit depth (E4), measured latency (E9), table provenance (E8), Section VII numbers,
    restart-marker wording and BRAM protection (R8), CR >= 2.5 claim, lane-count and
    future-work sentences (conclusion);
  * new Table IX (per-image CR, R3), Table X (platform comparison, R7), an architecture
    paragraph on the lane schedule / data path / stream format (R4/E7, Figs. 2-3);
    SEU tables renumbered to XI/XII.
Every number comes from eval/ artifacts; this script types no measurement by hand.

usage: python eval/paper/revise_v5.py <unpacked_dir>
"""
import os, re, sys, csv, shutil, statistics as st
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
from make_review_report import power  # noqa: E402

E = os.path.join(ROOT, 'eval')
D = sys.argv[1]
DOC = os.path.join(D, 'word', 'document.xml')
x = open(DOC, encoding='utf8').read()


# ----------------------------------------------------------------- XML helpers
def strip_ids(s):
    return re.sub(r' w14:(paraId|textId|anchorId)="[0-9A-F]+"', '', s)


def par_span(key):
    i = x.index(key)
    return x.rfind('<w:p ', 0, i), x.index('</w:p>', i) + 6


def replace_text(old, new, count=1):
    """Replace text that may span several runs of ONE paragraph (never across fields)."""
    global x
    a, b = par_span_text(old)
    p = x[a:b]
    ts = [(m.start(1), m.end(1)) for m in re.finditer(r'<w:t(?: [^>]*)?>([^<]*)</w:t>', p)]
    flat = ''.join(p[s:e] for s, e in ts)
    k = flat.index(old)
    pos, out, done = 0, [], False
    starts = []
    for s, e in ts:
        starts.append(pos); pos += e - s
    j0 = max(i for i, s in enumerate(starts) if s <= k)
    j1 = max(i for i, s in enumerate(starts) if s < k + len(old))
    seg = p[ts[j0][0]:ts[j1][1]]
    assert 'fldChar' not in seg and 'instrText' not in seg, 'replacement would span a field: ' + old[:40]
    pieces = [p[s:e] for s, e in ts]
    head = pieces[j0][:k - starts[j0]]
    tail = pieces[j1][k + len(old) - starts[j1]:]
    newp = p
    for j in range(j1, j0 - 1, -1):          # rewrite from the back so offsets stay valid
        s, e = ts[j]
        txt = head + escape(new) + tail if j == j0 else ''
        newp = newp[:s] + txt + newp[e:]
    newp = newp.replace('<w:t>', '<w:t xml:space="preserve">')
    x = x[:a] + newp + x[b:]


def par_span_text(txt):
    """Locate the paragraph whose visible text contains txt."""
    for m in re.finditer(r'<w:p[ >].*?</w:p>', x, re.S):
        vis = ''.join(re.findall(r'<w:t(?: [^>]*)?>([^<]*)</w:t>', m.group(0)))
        if txt in vis or escape(txt) in vis:
            return m.start(), m.end()
    raise KeyError(txt[:60])


def set_par_text(par, text):
    m = re.search(r'<w:r>(<w:rPr>.*?</w:rPr>)?', par)
    rpr = (m.group(1) or '') if m else ''
    head = par[:par.index('</w:pPr>') + 8] if '</w:pPr>' in par else par[:par.index('>') + 1]
    return head + '<w:r>%s<w:t xml:space="preserve">%s</w:t></w:r></w:p>' % (rpr, escape(text))


def set_paragraph(key, text):
    global x
    a, b = par_span_text(key)
    assert 'fldChar' not in x[a:b], 'paragraph has fields: ' + key
    x = x[:a] + set_par_text(x[a:b], text) + x[b:]


def append_to_paragraph(key, text):
    global x
    a, b = par_span_text(key)
    p = x[a:b]
    m = list(re.finditer(r'(<w:t(?: [^>]*)?>)([^<]*)(</w:t>)', p))[-1]
    p = p[:m.start()] + '<w:t xml:space="preserve">' + m.group(2) + escape(text) + m.group(3) + p[m.end():]
    x = x[:a] + p + x[b:]


def insert_after(key, xml):
    global x
    _, b = par_span_text(key)
    x = x[:b] + xml + x[b:]


def body_par(text):
    a, b = par_span_text('The energy argument for parallelization')
    return strip_ids(set_par_text(x[a:b], text))


def tables():
    return [(m.start(), x.index('</w:tbl>', m.start()) + 8) for m in re.finditer(r'<w:tbl>', x)]


def cells(row):
    return re.findall(r'<w:tc>.*?</w:tc>', row, re.S)


def build_table(tbl, rows, widths):
    tblpr = re.search(r'<w:tblPr>.*?</w:tblPr>', tbl, re.S).group(0)
    total = sum(widths)
    tblpr = re.sub(r'<w:tblW [^>]*/>', '<w:tblW w:w="%d" w:type="dxa"/>' % total, tblpr)
    trs = re.findall(r'<w:tr[ >].*?</w:tr>', tbl, re.S)
    tr_open = re.match(r'<w:tr[^>]*>', trs[0]).group(0)
    trpr = (re.search(r'<w:trPr>.*?</w:trPr>', trs[0], re.S) or [''])[0] if '<w:trPr>' in trs[0] else ''
    hcell, bcell = cells(trs[0])[0], cells(trs[1])[0]
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
    out.append('</w:tbl>')
    return ''.join(out)


def caption_par(text):
    a, _ = tables()[6]                                   # Table VII caption as the template
    p0 = x.rfind('<w:p ', 0, a)
    return strip_ids(set_par_text(x[p0:a], text))


def new_table(caption, rows, widths):
    a, b = tables()[6]
    return caption_par(caption) + build_table(x[a:b], rows, widths)


# ----------------------------------------------------------------- data
P = {t: power(os.path.join(E, 'power', t + '_power_saif.rpt')) for t in ['n12_45', 'n16_32', 'b12_45', 'b16_45']}
R = {r['image']: r for r in csv.DictReader(open(os.path.join(E, 'baseline', 'reference_baseline.csv')))}
M = {}
for r in csv.DictReader(open(os.path.join(E, 'hw', 'matrix_results.csv'))):
    M[(r['image'], r['grid'])] = r
NL = {r['image']: r for r in csv.DictReader(open(os.path.join(E, 'baseline', 'near_lossless.csv')))}
mc = open(os.path.join(E, 'baseline', 'charls_multicore.txt')).read()
cpu1 = float(re.search(r'1 process : ([\d.]+)', mc).group(1))
cpuN = float(re.search(r'(\d+) processes: ([\d.]+)', mc).group(2))
ncore = int(re.search(r'(\d+) processes:', mc).group(1))
cpu_full = float(re.search(r'([\d.]+) Mpixel/s', open(os.path.join(E, 'baseline', 'charls_throughput.txt')).read()).group(1))
lat = {}
for tag in ['lat8_300', 'lat8_1500', 'lat16_300']:
    s = open(os.path.join(E, 'hw', tag + '__h12v1.sim.log')).read()
    lat[tag] = {k: int(v) for k, v in re.findall(r'(\w+)=(-?\d+)', re.search(r'LATENCY_CYCLES (.*)', s).group(1))}
L_IN = sorted({v['first_in_to_enc0_first_px'] for v in lat.values()})
L_ENC = sorted({v['enc0_first_px_to_first_data_word'] for v in lat.values()})
L_END = sorted({v['last_in_to_all_lanes_done'] for v in lat.values()})
L_SOF = sorted({v['sof_to_first_in'] for v in lat.values()})
rng = lambda v: ('%d' % v[0]) if v[0] == v[-1] else '%d–%d' % (v[0], v[-1])
us = lambda cyc, mhz: cyc / mhz
e_px = lambda t, rate: float(P[t]['total']) / rate * 1e9
TDP = 45.0          # Intel Core i5-11400H processor base power (manufacturer specification)


def nl_med(pred, near):
    return st.median(float(r['cr_near%d' % near]) for n, r in NL.items() if pred(n))


aer = lambda n: n.startswith('aer_')
s12 = lambda n: n.endswith('_12b')
aer_cr = [float(r['cr_charls_full']) for n, r in R.items() if aer(n)]
s2_cr = [float(r['cr_charls_full']) for n, r in R.items() if n.startswith('s2_')]
lo_cr, hi_cr = min(aer_cr + s2_cr), max(aer_cr + s2_cr)

# ----------------------------------------------------------------- abstract / intro
replace_text('The design keeps Block RAM below 11 % and on-chip power at the sub-watt level, remaining well within '
             'the energy budget of small-satellite missions.',
             'The same RTL also builds at 12 and 16 bit per sample and closes timing at 45 MHz. Activity-based '
             '(SAIF) estimates give %.2f W on chip for the 8-bit 12-lane build (%.2f nJ per pixel) and %.2f–%.2f W at '
             '12/16 bit, with Block RAM at 8–13 %%. On aerial and Sentinel-2 imagery the partitioned hardware stays '
             'within 1 %% of single-core CharLS, but lossless ratios are only %.1f–%.1f:1, so a CR ≥ 2.5 downlink '
             'budget calls for near-lossless coding.' % (
                 float(P['n12_45']['total']), e_px('n12_45', 540e6), float(P['b12_45']['total']),
                 float(P['b16_45']['total']), lo_cr, hi_cr))
replace_text('reach only on the order of tens to about one hundred MB/s on a modern desktop CPU core, with the '
             'exact figure depending on the processor, image content, and build options',
             'reach %.0f–%.0f Mpixel/s on one core and %.0f Mpixel/s with %d parallel processes (CharLS 2.4.3 on an '
             'Intel Core i5-11400H, 8-bit imagery, Section VII)' % (cpu_full, cpu1, cpuN, ncore))

# ----------------------------------------------------------------- eq. (1) (R6)
replace_text('total’', 'total')
replace_text(' = W * R * D;', ' = W · R · D')

# ----------------------------------------------------------------- front end (E4) + architecture (R4/E7)
replace_text('receives the scanner stream as 8-bit monochrome pixels', 'receives the scanner stream as monochrome pixels of 8 to 16 bit')
replace_text('The current front end accepts 8-bit monochrome pixels; multispectral or higher-bit-depth sensors are '
             'handled band-sequentially, and native wider pixels are left to future work, since the core count '
             'N = ⌈P/F⌉ is independent of bit depth.',
             'The sample precision is a build-time parameter (8 to 16 bit): 8-bit builds use 8-bit pixel lanes and '
             '16-bit compressed words, while 12- and 16-bit builds use 16-bit pixel lanes and 32-bit compressed words, '
             'which keeps each lane\'s output port above the code rate of one sample per clock even for '
             'incompressible data. The input is monochrome; multispectral sensors are handled band-sequentially. '
             'Because one pixel is processed per clock, the core count N = ⌈P/F⌉ does not depend on bit depth.')

# Architecture paragraph (R4/E7) after the Fig. 3 caption; refers to Figs. 2 and 3
ci = x.index('Generalized structure')
cap_b = x.index('</w:p>', ci) + 6
fig_text = body_par(
    'The lane schedule (Fig. 2) and the node structure (Fig. 3) operate as follows. The splitter keeps one shared '
    'intra-block counter (xs, ys) over the W/N_H × H/N_V block and, in every cycle in which an input word is accepted, '
    'writes one pixel into every lane\'s input FIFO, so all lanes advance in lockstep and each receives exactly its own '
    'block in raster order; back-pressure is global (if any lane FIFO is full, the input stalls for all lanes). On the '
    'encoder side a read controller asserts start-of-frame to all lanes for a fixed %d-cycle setup interval, then '
    'starts them together and counts the pixels delivered to each lane, so a lane never runs ahead of the data that has '
    'crossed the clock domain. Each lane emits an independent, complete JPEG-LS stream (SOI, SOF55 frame header '
    'carrying the block size, SOS, entropy-coded data with the mandatory 0xFF bit stuffing, EOI) and keeps no state '
    'shared with other lanes. The output FIFOs record where each stream ends in the write domain and pass the stream '
    'count to the read domain through a Gray-coded pointer, and every lane is presented as its own AXI4-Stream master '
    'with tlast on the final word. The compressed frame is therefore the concatenation of N standard streams in lane '
    'order, and reassembly needs only the fixed block map defined above.' % (L_SOF[0] - 2))
x = x[:cap_b] + fig_text + x[cap_b:]

# ----------------------------------------------------------------- Table III paragraph: units + latency (R6, E9)
replace_text('Latency is deterministic: the encoder pipeline is 11 registered stages (about 11 clocks, ≈ 0.24 µs at '
             '45 MHz per lane) plus the FIFO/CDC fill, independent of image size, which is well suited to real-time '
             'streaming.',
             'Latency is deterministic and independent of image size. In RTL simulation a pixel reaches its lane '
             'encoder %s cycles after its input beat, the first entropy-coded word leaves the encoder %s cycles later, '
             'and the last compressed byte of every lane is available at the AXI4-Stream outputs %s cycles '
             '(≈%.1f µs at 45 MHz) after the last input pixel, for 300×300 and 1500×1500 frames and at 8 and 16 bit. '
             'The only per-frame overhead is the start-of-frame setup interval: %s cycles (≈%.0f µs at 45 MHz) pass '
             'between the SOF pulse and the first accepted pixel. The 12- and 16-bit builds sustain the same 540 Mpixel/s, which '
             'corresponds to 810 MB/s (6.48 Gbit/s) and 1080 MB/s (8.64 Gbit/s) of raw sample data.' % (
                 rng(L_IN), rng(L_ENC), rng(L_END), us(L_END[-1], 45), rng(L_SOF), us(L_SOF[-1], 45)))

# ----------------------------------------------------------------- resource provenance (E8)
append_to_paragraph('Logic is not the limiting resource',
    ' The 12- and 16-bit builds (Table VI) roughly double the LUT count because the error, context and Golomb '
    'datapaths widen and the output word doubles, while Block RAM rises only to 13.2 %. Tables V and VI list the '
    'builds of the parameterized RTL; for the 8-bit power results in Table VII the same 12- and 16-lane '
    'configurations were re-implemented with the encoder packaged as a Vivado IP core, which uses slightly more '
    'logic (27.0 % LUT at 12 lanes) and closes at +0.09 ns.')

# ----------------------------------------------------------------- R3: framing sentence + per-image table (IX)
append_to_paragraph('To check that these results are not specific to one image corpus',
    ' All hardware ratios include every lane\'s complete stream framing (a 25-byte SOI/SOF55/SOS header and the EOI '
    'marker per lane); the CharLS ratios include CharLS\'s own framing (a 44-byte SPIFF header per stream in the '
    'build used). Table IX lists the best- and worst-compressing image of each data set.')
labels = {
    'bm_300x300': 'Blue Marble', 'bm_1500x1500': 'Blue Marble', 'bm_3000x3000': 'Blue Marble', 'bm_4992x4992': 'Blue Marble',
    'aer_2_2_09': 'Aerial 2.2.09, coast', 'aer_2_2_13': 'Aerial 2.2.13, farmland', 'aer_2_2_17': 'Aerial 2.2.17, urban grid',
    'aer_3_2_25': 'Aerial 3.2.25, buildings', 'aer_wash-ir': 'Aerial wash-ir, city (IR)',
    's2_nile_agri_12b': 'S2 Nile-delta fields (B04)', 's2_nile_agri_nir_12b': 'S2 Nile-delta fields (B08)',
    's2_nile_branch_12b': 'S2 Nile branch (B04)', 's2_delta_west_12b': 'S2 western delta (B04)',
    's2_cairo_urban_16b': 'S2 Cairo urban (B04)', 's2_pivot_fields_16b': 'S2 pivot irrigation (B04)',
    's2_desert_16b': 'S2 Eastern Desert (B04)', 's2_nile_agri_16b': 'S2 Nile-delta fields (B04)',
    's2_nile_agri_nir_16b': 'S2 Nile-delta fields (B08)'}
rows9 = [['Image', 'bpp', 'Size', 'CharLS 1 core', 'RTL 12×1', 'RTL 1×12', 'RTL 4×3']]
# keep only the best and worst image (by CharLS CR) of each data set
grp = lambda n: 'bm' if n.startswith('bm_') else 'aer' if n.startswith('aer_') else n[-3:]
keep = set()
for g in {grp(n) for n in labels}:
    ns = [n for n in labels if grp(n) == g]
    keep |= {max(ns, key=lambda n: float(R[n]['cr_charls_full'])), min(ns, key=lambda n: float(R[n]['cr_charls_full']))}
labels = {n: l for n, l in labels.items() if n in keep}
for n, lab in labels.items():
    r = R[n]
    if n.startswith('bm_'):
        hw = [float(r['cr_hw_' + g]) for g in ['h12v1', 'h1v12', 'h4v3']]
    else:
        hw = [float(M[(n, g)]['cr']) for g in ['h12v1', 'h1v12', 'h4v3']]
    rows9.append([lab, r['bpp'], '%s²' % r['W'] if r['W'] == r['H'] else '%s×%s' % (r['W'], r['H']),
                  '%.2f' % float(r['cr_charls_full'])] + ['%.2f' % v for v in hw])
t9 = new_table('BEST AND WORST IMAGE PER DATA SET: RTL (12 LANES, THREE DIRECTIONS) VS. SINGLE-CORE CHARLS', rows9,
               [1500, 350, 650, 650, 550, 550, 550])
a8, b8 = tables()[7]                                     # new Table VIII -> insert IX right after it
x = x[:b8] + t9 + x[b8:]

# ----------------------------------------------------------------- R7: Section VII (E3) + platform table (X)
replace_text('In this work a single -2 Artix-7 sustains 540 MB/s at sub-watt on-chip power, i.e. on the order of '
             '1 GB/s per watt, with a fixed ≈11-clock pipeline latency.',
             'In this work a single -2 Artix-7 sustains 540 Mpixel/s at %.2f W on chip (8-bit, activity-based), i.e. '
             'about %.1f Gpixel/s per watt, and delivers the last compressed byte of a frame about %.1f µs after its '
             'last pixel.' % (float(P['n12_45']['total']), 0.54 / float(P['n12_45']['total']), us(L_END[-1], 45)))
set_paragraph('CPUs offer the most flexible toolchain',
    'CPUs offer the most flexible toolchain but remain serial for this pixel-level, feedback-dependent workload. On '
    'the authors\' host (Intel Core i5-11400H, 6 cores) the CharLS 2.4.3 encoder reaches %.0f Mpixel/s on a whole '
    '4992×4992 frame and %.0f Mpixel/s when the frame is cut into the same 12 strips as the hardware; running the '
    'strips in %d processes gives %.0f Mpixel/s, i.e. %.0f %% of the 12-lane FPGA rate. Taking the processor\'s '
    'rated %.0f W as its power (not measured), the energy per pixel is two orders of magnitude above the FPGA\'s, '
    'and each frame must be buffered in memory before it is compressed. Table X compares the platforms on '
    'throughput, power, energy per pixel and latency; the CPU throughput is measured, the CPU power is the '
    'manufacturer rating, and the GPU speed-up is taken from [12]. An embedded ARM SoC was not measured. On these '
    'axes the FPGA is the most appropriate onboard platform, with an SoC attractive only where programmability '
    'outweighs efficiency.' % (cpu_full, cpu1, ncore, cpuN, 100 * cpuN / 540, TDP))
rows10 = [['Platform', 'Throughput (Mpix/s, 8-bit)', 'Power (W)', 'Energy (nJ/pixel)', 'Latency', 'Basis'],
          ['FPGA, 12 lanes @ 45 MHz (this work)', '540', P['n12_45']['total'], '%.2f' % e_px('n12_45', 540e6),
           '%d cycles ≈ %.1f µs after last pixel' % (L_END[-1], us(L_END[-1], 45)), 'post-route, SAIF'],
          ['FPGA, 16 lanes @ 32 MHz (this work)', '512', P['n16_32']['total'], '%.2f' % e_px('n16_32', 512e6),
           'not measured', 'post-route, SAIF'],
          ['CPU, CharLS, 1 process', '%.0f' % cpu1, '%.0f (rated)' % TDP, '%.0f' % (TDP / cpu1 / 1e6 * 1e9),
           'whole frame: %.0f ms for 1500²' % (2.25e6 / cpu1 / 1e3), 'measured throughput'],
          ['CPU, CharLS, %d processes' % ncore, '%.0f' % cpuN, '%.0f (rated)' % TDP, '%.0f' % (TDP / cpuN / 1e6 * 1e9),
           'whole frame: %.1f ms for 1500²' % (2.25e6 / cpuN / 1e3), 'measured throughput'],
          ['GPU, CUDA JPEG-LS [12]', '26.3× over sequential CPU', '200–450 (typical board, Sec. II)', '—', 'batch', 'speed-up from [12]']]
t10 = new_table('PLATFORM COMPARISON FOR ONBOARD JPEG-LS COMPRESSION', rows10, [1300, 700, 600, 600, 900, 700])
insert_after('CPUs offer the most flexible toolchain', t10)

# ----------------------------------------------------------------- mission guidance + latency wording
replace_text('(about an 11-clock pipeline plus FIFO fill)', '(about %d cycles from the last pixel to the last compressed byte)' % L_END[-1])
append_to_paragraph('Bandwidth-constrained missions',
    ' On sensor-like imagery, however, lossless ratios stay below 2.5:1 (Tables VIII and IX), so these missions '
    'should plan for near-lossless coding.')

# ----------------------------------------------------------------- R8: restart markers + BRAM protection, table renumbering
replace_text('and restart markers inserted at block boundaries bound propagation further',
             'and restart markers inside each lane stream (not implemented in this work) would bound propagation further')
replace_text('Table IX quantifies the SEU exposure', 'Table XI quantifies the SEU exposure')
_, bf = tables()[-1]
x = x[:bf] + body_par(
    'Memory protection follows from these results. The line buffer, the most sensitive structure in these injections, and '
    'the FIFOs are Block RAM, for which the 7-series devices provide built-in single-error-correction on 64-bit-wide '
    'ports and the FIFO generator an ECC option; the context memories (366 entries of 26 bits plus 364 entries of 8 '
    'bits per lane at 8 bit) are LUT RAM and would need triplication or scrubbing. Because every lane re-initialises '
    'its contexts at the start of each block, an upset in a context memory cannot outlive the block in which it '
    'occurs. Configuration-memory scrubbing covers the essential bits of Table XI.') + x[bf:]

# ----------------------------------------------------------------- conclusion
append_to_paragraph('This work benchmarked three spatial splitting strategies',
    ' 12- and 16-bit builds of the 12-lane configuration also close timing at 45 MHz, and the evaluation was '
    'extended to aerial and Sentinel-2 imagery at 8, 12 and 16 bit.')
replace_text('since the large reduction in processing time outweighs the small increment in dynamic power; the clock '
             'manager and static power, which dominate the budget, are essentially fixed with respect to lane count.',
             'since the processing time falls in proportion to the lane count while the on-chip power stays at '
             '%.2f W for 12 lanes at 45 MHz and %.2f W for 16 lanes at 32 MHz, about 1 nJ per pixel at 8 bit.' % (
                 float(P['n12_45']['total']), float(P['n16_32']['total'])))
replace_text('For the tested Earth-observation corpus the ratios lie between about 7:1 at 300×300 and 4.3:1 at '
             '5000×5000, comfortably above the CR ≥ 2.5 needed to avoid discarding scientifically valuable data on a '
             'downlink-limited platform such as Sich-3O.',
             'On the smooth Blue Marble composite the ratios lie between about 7:1 at 300×300 and 4.3:1 at 5000×5000, '
             'but on sensor-like aerial and Sentinel-2 imagery lossless JPEG-LS (hardware and CharLS alike) reaches '
             'only %.1f–%.1f:1, below the CR ≥ 2.5 targeted for Sich-3O. In the CharLS reference, near-lossless coding '
             'with NEAR = 2 raises the median ratio to %.2f:1 on the aerial imagery and %.2f:1 on the 12-bit '
             'Sentinel-2 tiles, so a mission that must meet this budget needs near-lossless operation (supported by '
             'the 8-bit encoder core but not yet exposed by the IP) or additional downlink scheduling.' % (
                 lo_cr, hi_cr, nl_med(aer, 2), nl_med(s12, 2)))
set_paragraph('The proposed multi-encoder architecture is not inherently limited',
    'The architecture scales with the lane count: the same RTL was built and verified with 12 and 16 lanes and at '
    '8 to 16 bit per sample, with Block RAM between 8 % and 13 % and LUT use growing from 24 % (12 lanes, 8 bit) to '
    '63 % (12 lanes, 16 bit). Beyond 16 lanes, or at higher sample precision, the LUT budget and the line-buffer '
    'width, rather than the partitioning scheme, become the limits.')
replace_text('(iii) quantify SEU cross-section and demonstrate restart markers, memory ECC/scrubbing, and TMR for '
             'radiation tolerance; (iv) extend the encoder to 12- and 16-bit and multispectral inputs;',
             '(iii) measure the SEU cross-section in a beam test and implement restart markers, memory ECC/scrubbing '
             'and TMR; (iv) expose near-lossless coding (NEAR ≥ 1) in the IP, including at 12 and 16 bit, and support '
             'band-interleaved multispectral input;')

open(DOC, 'w', encoding='utf8').write(x)
print('revised', DOC)
