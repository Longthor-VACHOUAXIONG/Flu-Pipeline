import os, sys, csv, json, glob, re
from pathlib import Path
from datetime import datetime

ROOT_DIR = Path(os.path.dirname(os.path.abspath(__file__)))
if ROOT_DIR.name == "scripts": ROOT_DIR = ROOT_DIR.parent

OVERRIDE_DIR = os.environ.get("RESULTS_DIR_OVERRIDE")
if OVERRIDE_DIR:
    RESULTS_DIR = Path(OVERRIDE_DIR)
elif (ROOT_DIR / "results_irma").exists():
    RESULTS_DIR = ROOT_DIR / "results_irma"
else:
    RESULTS_DIR = ROOT_DIR / "results_final"

REPORT_FILE = RESULTS_DIR / "04_summary" / "AIV_Diagnostic_Report.html"
CONSENSUS_DIR = RESULTS_DIR / "03_consensus"
ALIGN_DIR = RESULTS_DIR / "05_alignment"
TREE_DIR = RESULTS_DIR / "06_trees"

OVERRIDE_LIB = os.environ.get("LIB_FILE_OVERRIDE")
LIB_FILE = ROOT_DIR / "references" / OVERRIDE_LIB if OVERRIDE_LIB else (ROOT_DIR / "references" / "depletion_library.fasta")

SEG_NAMES = ["PB2","PB1","PA","HA","NP","NA","MP","NS"]

def load_tsv(path):
    if not os.path.exists(path): return []
    with open(path, newline='', encoding='utf-8', errors='ignore') as f:
        # Try tab first, then comma
        content = f.read()
        f.seek(0)
        delim = ',' if ',' in content.split('\n')[0] else '\t'
        reader = csv.DictReader(f, delimiter=delim)
        return list(reader)

def load_library_headers(path):
    headers = {}
    if not os.path.exists(path): return headers
    with open(path) as f:
        for line in f:
            if line.startswith(">"):
                parts = line.strip()[1:].split(" ", 1)
                acc = parts[0].split(".")[0].replace("Influenza_A_", "")
                headers[acc] = parts[1] if len(parts) > 1 else acc
    return headers

def translate(dna):
    table = {
        'ATA':'I','ATC':'I','ATT':'I','ATG':'M','ACA':'T','ACC':'T','ACG':'T','ACT':'T',
        'AAC':'N','AAT':'N','AAA':'K','AAG':'K','AGC':'S','AGT':'S','AGA':'R','AGG':'R',
        'CTA':'L','CTC':'L','CTG':'L','CTT':'L','CCA':'P','CCC':'P','CCG':'P','CCT':'P',
        'CAC':'H','CAT':'H','CAA':'Q','CAG':'Q','CGA':'R','CGC':'R','CGG':'R','CGT':'R',
        'GTA':'V','GTC':'V','GTG':'V','GTT':'V','GCA':'A','GCC':'A','GCG':'A','GCT':'A',
        'GAC':'D','GAT':'D','GAA':'E','GAG':'E','GGA':'G','GGC':'G','GGG':'G','GGT':'G',
        'TCA':'S','TCC':'S','TCG':'S','TCT':'S','TTC':'F','TTT':'F','TTA':'L','TTG':'L',
        'TAC':'Y','TAT':'Y','TAA':'_','TAG':'_','TGC':'C','TGT':'C','TGA':'_','TGG':'W'
    }
    dna = dna.upper().replace('N','')
    return "".join(table.get(dna[i:i+3],'?') for i in range(0, len(dna)-(len(dna)%3), 3))

def get_segment_num(name):
    name = name.upper()
    for i, s in enumerate(SEG_NAMES): 
        if s in name: return i+1
    return 99

def load_reconstructions(lib_headers):
    # Match: RunID_Barcode_SampleName_A_SegName[_Subtype].fasta
    # Search recursively in subfolders (e.g. H5N1, H9N2)
    files = glob.glob(str(CONSENSUS_DIR / "**" / "*.fasta"), recursive=True)
    samples = {}
    for f in files:
        fname = os.path.basename(f)
        if "_aligned" in fname or "_unaligned" in fname or "_ref.fasta" in fname: continue
        
        # Parse: RunID_BC_Sample_A_SEG[_SUB].fasta
        parts = fname.replace(".fasta","").split("_")
        if len(parts) < 5: continue
        
        # BC is index 1, Sample is index 2, Seg is index 4
        bc = parts[1]
        sample_id = f"{bc} → {parts[2]}"
        seg_name = parts[4]
        
        with open(f) as fasta:
            lines = fasta.readlines()
            seq = "".join([l.strip() for l in lines[1:]]) if lines else ""
        
        acc_key = seg_name
        desc = lib_headers.get(acc_key, f"Segment {seg_name}")
        
        if sample_id not in samples: samples[sample_id] = []
        samples[sample_id].append({'name':desc,'id':fname,'len':len(seq),'conf':'HQ','reads':0,'seq':seq,'con_seq':seq,'ref_seq':''})
    return samples

def load_trees():
    trees = {}
    for seg in SEG_NAMES:
        tf = TREE_DIR / f"{seg}.treefile"
        if tf.exists():
            with open(tf) as f: trees[seg] = f.read().strip()
        iq = TREE_DIR / f"{seg}.iqtree"
        model = ""
        if iq.exists():
            with open(iq) as f:
                for line in f:
                    if "Best-fit model" in line:
                        model = line.split(":")[-1].strip()
                        break
            trees[seg+"_model"] = model
    return trees

def load_alignments():
    aligns = {}
    for seg in SEG_NAMES:
        af = ALIGN_DIR / f"{seg}_aligned.fasta"
        if not af.exists(): continue
        seqs = {}
        current = ""
        with open(af) as f:
            for line in f:
                line = line.strip()
                if line.startswith(">"):
                    current = line[1:].split()[0][:30]
                    seqs[current] = ""
                elif current:
                    seqs[current] += line
        aligns[seg] = seqs
    return aligns

def load_qc():
    # Look for any QC_Report file, prioritizing the most recent
    qc_files = sorted(glob.glob(str(RESULTS_DIR / "QC" / "QC_Report_*.csv")), reverse=True)
    if qc_files:
        return load_tsv(qc_files[0])
    return []

def diff_html(ref, con):
    if not ref or not con: return ""
    out = []
    for i in range(min(len(ref), len(con))):
        if ref[i] != con[i] and ref[i] != '-' and con[i] != '-':
            out.append(f'<span class="snp" title="Pos {i+1}: {ref[i]}→{con[i]}">{con[i]}</span>')
        elif con[i] == '-':
            out.append(f'<span class="gap">-</span>')
        else:
            out.append(con[i])
    return "".join(out)

def generate_html(qc_rows, samples, trees, aligns):
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    total_samples = len(qc_rows)
    success = sum(1 for r in qc_rows if r.get('Status','') == 'SUCCESS')
    total_segs = sum(int(r.get('Segments_Detected','0')) for r in qc_rows)
    tree_count = sum(1 for s in SEG_NAMES if s in trees)

    # QC table
    qc_html = ""
    for r in qc_rows:
        bc = r.get('Barcode','?')
        sample_name = r.get('Sample_Name', bc)
        reads = int(r.get('Initial_Reads','0'))
        irma = int(r.get('IRMA_Initiate_Reads','0'))
        st = r.get('Status','FAILED')
        segs = r.get('Segments_Detected','0')
        pct = (irma/reads*100) if reads > 0 else 0
        st_cls = "success" if st=="SUCCESS" else ("warning" if st=="LOW_DATA" else "danger")
        qc_html += f'''<tr>
            <td class="fw700">{bc}</td><td class="sample-name-cell" title="{sample_name}">{sample_name}</td><td>{reads:,}</td><td>{irma:,}</td>
            <td>{pct:.1f}%</td><td><div class="bar-bg"><div class="bar-fill" style="width:{min(100,pct)}%"></div></div></td>
            <td>{segs}/8</td><td><span class="badge badge-{st_cls}">{st}</span></td>
        </tr>'''

    # Tree cards
    tree_html = ""
    for seg in SEG_NAMES:
        if seg not in trees: continue
        nwk = trees[seg].replace("'","").replace('"','')
        nwk_js = nwk.replace('\\','\\\\')
        model = trees.get(seg+"_model","N/A")
        # Parse distances from newick for visual
        pairs = re.findall(r'([^,:()]+):([\d.]+)', nwk)
        dist_rows = ""
        for name, dist in pairs:
            name_clean = name.replace("gi_","").replace("_gb_","_").replace("_"," ")[:40]
            is_sample = not any(ind in name for ind in ['Reference_','gi_','_gb_','A_H','B_Vic','B_Yam','segment'])
            d = float(dist)
            bar_w = min(100, d * 200)
            color = 'var(--pri)' if is_sample else 'var(--muted)'
            dist_rows += f'<div class="dist-row"><span class="dist-name" style="color:{color}">{"🔬 " if is_sample else ""}{name_clean}</span><div class="dist-bar-bg"><div class="dist-bar" style="width:{bar_w}%;{"background:var(--pri)" if is_sample else ""}" ></div></div><span class="dist-val">{d:.4f}</span></div>'
        tree_html += f'''<div class="tree-card">
            <div class="tree-header"><span class="seg-badge">{seg}</span><span class="tree-model">Model: {model}</span></div>
            <div class="tree-body">
                <div class="tree-visual"><svg id="tree-svg-{seg}" width="100%" height="180"></svg></div>
                <script>document.addEventListener("DOMContentLoaded",function(){{drawTree("tree-svg-{seg}","{nwk_js}")}});</script>
                <div class="dist-chart">{dist_rows}</div>
            </div></div>'''

    # Alignment cards
    align_html = ""
    for seg in SEG_NAMES:
        if seg not in aligns: continue
        seqs = aligns[seg]
        names = list(seqs.keys())
        if not names: continue
        aln_len = max(len(s) for s in seqs.values()) if seqs else 0
        ref_name = names[0]
        ref_seq = seqs[ref_name]
        rows_html = ""
        # Detect reference vs sample: references usually have long names with underscores/pipes/accessions
        ref_indicators = ['Reference_', 'gi_', '_gb_', 'A_H', 'B_Vic', 'B_Yam', 'segment']
        for nm in names:
            sq = seqs[nm]
            label = nm[:30]
            is_ref = any(ind in nm for ind in ref_indicators)
            is_sample = not is_ref
            cls = "sample-seq" if is_sample else ""
            if nm == ref_name:
                seq_display = sq
            else:
                seq_display = diff_html(ref_seq, sq)
            rows_html += f'<div class="aln-row {cls}"><span class="aln-label">{label}</span><span class="aln-seq">{seq_display}</span></div>'
        align_html += f'''<div class="align-card">
            <div class="align-header"><span class="seg-badge">{seg}</span><span class="aln-info">{len(names)} sequences · {aln_len:,} bp aligned</span></div>
            <div class="align-body"><div class="aln-viewer">{rows_html}</div>
            <div class="aln-note">Full-length alignment. SNPs highlighted in red. Scroll horizontally to view.</div></div></div>'''

    # Reconstruction cards
    recon_html = ""
    for bc in sorted(samples.keys()):
        segs = samples[bc]
        seg_cards = ""
        for s in sorted(segs, key=lambda x: get_segment_num(x['name'])):
            d = diff_html(s['ref_seq'], s['con_seq'])
            seg_cards += f'''<div class="seg-row">
                <div class="seg-meta"><span class="seg-name">{s['name']}</span><span>{s['len']}bp</span><span>{s['reads']:,} reads</span><span class="badge badge-{s['conf'].lower()}">{s['conf']}</span></div>
                <details><summary>Triple-View</summary><div class="triple-view">
                    <div class="tv-row"><div class="tv-label">REF</div><div class="tv-seq">{s['ref_seq'] if s['ref_seq'] else "N/A"}</div></div>
                    <div class="tv-row"><div class="tv-label">CONSENSUS</div><div class="tv-seq">{d if d else (s['con_seq'] if s['con_seq'] else "N/A")}</div></div>
                    <div class="tv-row"><div class="tv-label">SAMPLE</div><div class="tv-seq">{s['seq'] if s['seq'] else "N/A"}</div></div>
                </div></details></div>'''
        recon_html += f'''<div class="recon-card"><div class="recon-header"><span class="fw700">{bc}</span><span>{len(segs)} segments</span></div>{seg_cards}</div>'''

    html = f'''<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8">
<title>AIV Genomic Intelligence Report</title>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700;800&family=JetBrains+Mono:wght@400;700&display=swap" rel="stylesheet">
<style>
*{{box-sizing:border-box;margin:0;padding:0}}
:root{{--bg:#0a0e1a;--card:#131829;--card2:#1a2035;--border:#1e2a45;--text:#e2e8f0;--muted:#64748b;--pri:#38bdf8;--sec:#818cf8;--acc:#a78bfa;--success:#22c55e;--warn:#f59e0b;--danger:#ef4444;--hq:#10b981;--lq:#f59e0b}}
body{{font-family:'Inter',system-ui,sans-serif;background:var(--bg);color:var(--text);line-height:1.6;padding:0}}
.wrap{{max-width:1400px;margin:0 auto;padding:30px 40px}}

/* Header */
.header{{background:linear-gradient(135deg,#0f172a 0%,#1e1b4b 50%,#172554 100%);padding:40px;border-bottom:1px solid var(--border);margin-bottom:0}}
.header h1{{font-size:2.2rem;font-weight:800;background:linear-gradient(135deg,var(--pri),var(--sec),var(--acc));-webkit-background-clip:text;-webkit-text-fill-color:transparent}}
.header .sub{{color:var(--muted);margin-top:5px}}
.header .meta{{color:var(--muted);font-size:.85rem;margin-top:10px}}

/* Nav */
.nav{{display:flex;gap:0;background:var(--card);border-bottom:1px solid var(--border);position:sticky;top:0;z-index:100}}
.nav-btn{{padding:14px 28px;background:none;border:none;color:var(--muted);font-size:.9rem;font-weight:600;cursor:pointer;border-bottom:3px solid transparent;transition:all .2s}}
.nav-btn:hover,.nav-btn.active{{color:var(--pri);border-bottom-color:var(--pri);background:rgba(56,189,248,.05)}}

/* Tabs */
.tab{{display:none;padding:30px 40px}}.tab.active{{display:block}}

/* Dashboard */
.dash{{display:grid;grid-template-columns:repeat(4,1fr);gap:16px;margin-bottom:30px}}
.stat{{background:var(--card);border:1px solid var(--border);border-radius:12px;padding:20px;position:relative;overflow:hidden}}
.stat::before{{content:'';position:absolute;top:0;left:0;right:0;height:3px}}
.stat:nth-child(1)::before{{background:var(--pri)}}.stat:nth-child(2)::before{{background:var(--success)}}.stat:nth-child(3)::before{{background:var(--acc)}}.stat:nth-child(4)::before{{background:var(--warn)}}
.stat-val{{font-size:2rem;font-weight:800;color:var(--pri)}}.stat-lab{{font-size:.75rem;text-transform:uppercase;letter-spacing:.08em;color:var(--muted);margin-top:4px}}

/* Tables */
table{{width:100%;border-collapse:collapse;background:var(--card);border-radius:12px;overflow:hidden;border:1px solid var(--border)}}
th{{background:var(--bg);padding:14px 16px;text-align:left;font-size:.75rem;text-transform:uppercase;letter-spacing:.05em;color:var(--muted);border-bottom:1px solid var(--border)}}
td{{padding:14px 16px;border-bottom:1px solid var(--border);font-size:.9rem}}
.sample-name-cell{{max-width:220px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:.82rem;color:var(--acc)}}
tr:last-child td{{border-bottom:none}}tr:hover{{background:rgba(56,189,248,.03)}}
.fw700{{font-weight:700}}
.bar-bg{{width:80px;height:6px;background:var(--bg);border-radius:3px;display:inline-block;vertical-align:middle}}.bar-fill{{height:100%;background:linear-gradient(90deg,var(--pri),var(--sec));border-radius:3px}}
.badge{{padding:3px 10px;border-radius:20px;font-size:.7rem;font-weight:700;text-transform:uppercase}}
.badge-success,.badge-hq{{background:rgba(34,197,94,.15);color:var(--success);border:1px solid rgba(34,197,94,.3)}}
.badge-warning,.badge-lq{{background:rgba(245,158,11,.15);color:var(--warn);border:1px solid rgba(245,158,11,.3)}}
.badge-danger{{background:rgba(239,68,68,.15);color:var(--danger);border:1px solid rgba(239,68,68,.3)}}
.badge-tr{{background:rgba(100,116,139,.15);color:var(--muted);border:1px solid rgba(100,116,139,.3)}}

/* Section */
.sec-title{{font-size:1.3rem;font-weight:700;margin:30px 0 16px;padding-left:14px;border-left:4px solid var(--pri)}}

/* Tree Cards */
.tree-card{{background:var(--card);border:1px solid var(--border);border-radius:12px;margin-bottom:16px;overflow:hidden}}
.tree-header{{padding:16px 20px;display:flex;justify-content:space-between;align-items:center;border-bottom:1px solid var(--border);background:var(--card2)}}
.tree-body{{padding:20px}}
.seg-badge{{background:linear-gradient(135deg,var(--pri),var(--sec));color:#fff;padding:4px 14px;border-radius:6px;font-weight:700;font-size:.85rem}}
.tree-model{{color:var(--muted);font-size:.85rem}}
.newick-box{{background:var(--bg);border-radius:8px;padding:12px 16px;margin-bottom:16px;font-family:'JetBrains Mono',monospace;font-size:.8rem;overflow-x:auto;color:var(--acc);word-break:break-all}}
.dist-chart{{display:flex;flex-direction:column;gap:8px}}
.dist-row{{display:flex;align-items:center;gap:12px}}
.dist-name{{width:200px;font-size:.8rem;color:var(--muted);flex-shrink:0;text-overflow:ellipsis;overflow:hidden;white-space:nowrap}}
.dist-bar-bg{{flex:1;height:8px;background:var(--bg);border-radius:4px;overflow:hidden}}.dist-bar{{height:100%;background:linear-gradient(90deg,var(--success),var(--warn));border-radius:4px;transition:width .5s}}
.dist-val{{width:70px;text-align:right;font-family:'JetBrains Mono',monospace;font-size:.8rem;color:var(--pri)}}

/* Align Cards */
.align-card{{background:var(--card);border:1px solid var(--border);border-radius:12px;margin-bottom:16px;overflow:hidden}}
.align-header{{padding:16px 20px;display:flex;justify-content:space-between;align-items:center;border-bottom:1px solid var(--border);background:var(--card2)}}
.aln-info{{color:var(--muted);font-size:.85rem}}
.align-body{{padding:16px 20px}}
.aln-viewer{{background:var(--bg);border-radius:8px;padding:14px;font-family:'JetBrains Mono',monospace;font-size:11px;overflow-x:auto;max-height:300px;overflow-y:auto}}
.aln-row{{display:flex;margin-bottom:3px;white-space:nowrap}}.aln-label{{width:160px;color:var(--muted);flex-shrink:0;overflow:hidden;text-overflow:ellipsis}}.aln-seq{{letter-spacing:.5px}}
.sample-seq .aln-label{{color:var(--pri);font-weight:700}}
.aln-note{{color:var(--muted);font-size:.75rem;margin-top:10px;font-style:italic}}
.snp{{background:rgba(239,68,68,.3);color:#fff;font-weight:700;border-bottom:2px solid var(--danger)}}.gap{{color:#334155}}

/* Recon Cards */
.recon-card{{background:var(--card);border:1px solid var(--border);border-radius:12px;margin-bottom:20px;overflow:hidden}}
.recon-header{{padding:16px 20px;display:flex;justify-content:space-between;align-items:center;background:var(--card2);border-bottom:1px solid var(--border)}}
.seg-row{{padding:16px 20px;border-bottom:1px solid var(--border)}}
.seg-meta{{display:flex;gap:16px;align-items:center;margin-bottom:10px;font-size:.85rem;color:var(--muted)}}.seg-name{{font-weight:700;color:var(--text);min-width:100px}}
.triple-view{{background:var(--bg);border-radius:8px;padding:14px;font-family:'JetBrains Mono',monospace;font-size:11px;overflow-x:auto;margin-top:8px}}
.tv-row{{display:flex;margin-bottom:4px}}.tv-label{{width:90px;color:var(--muted);flex-shrink:0;font-weight:600}}.tv-seq{{word-break:break-all;letter-spacing:.5px}}
details summary{{cursor:pointer;color:var(--pri);font-weight:600;font-size:.85rem}}

footer{{text-align:center;padding:30px;color:var(--muted);font-size:.75rem;border-top:1px solid var(--border);margin-top:40px}}
</style>
<script>
function showTab(id){{document.querySelectorAll('.tab').forEach(t=>t.classList.remove('active'));document.querySelectorAll('.nav-btn').forEach(b=>b.classList.remove('active'));document.getElementById(id).classList.add('active');event.target.classList.add('active')}}

function drawTree(svgId, nwk) {{
  var svg = document.getElementById(svgId);
  if (!svg || !nwk) return;
  // Parse newick: extract taxa and distances
  var pairs = [];
  var re = /([^,:()]+):([\d.]+)/g;
  var m;
  while ((m = re.exec(nwk)) !== null) {{
    pairs.push({{name: m[1].trim(), dist: parseFloat(m[2])}});
  }}
  if (pairs.length === 0) return;
  
  var maxDist = Math.max.apply(null, pairs.map(function(p){{return p.dist}}));
  if (maxDist === 0) maxDist = 1;
  
  var n = pairs.length;
  var h = Math.max(160, n * 50);
  svg.setAttribute('height', h);
  var W = svg.clientWidth || 700;
  var pad = 20, labelW = 250, treeW = W - labelW - pad * 2;
  var rootX = pad, rootY = h / 2;
  var yStep = (h - pad * 2) / Math.max(1, n - 1);
  
  var ns = 'http://www.w3.org/2000/svg';
  svg.innerHTML = '';
  
  // Draw root vertical line
  var topY = pad;
  var botY = pad + (n - 1) * yStep;
  var vline = document.createElementNS(ns, 'line');
  vline.setAttribute('x1', rootX); vline.setAttribute('y1', topY);
  vline.setAttribute('x2', rootX); vline.setAttribute('y2', botY);
  vline.setAttribute('stroke', '#475569'); vline.setAttribute('stroke-width', '2');
  svg.appendChild(vline);
  
  for (var i = 0; i < n; i++) {{
    var p = pairs[i];
    var y = pad + i * yStep;
    var branchLen = (p.dist / maxDist) * treeW;
    var endX = rootX + branchLen;
    var refIndicators = ['Reference_', 'gi_', '_gb_', 'A_H', 'B_Vic', 'B_Yam', 'segment'];
    var isRef = refIndicators.some(function(ind) {{ return p.name.indexOf(ind) >= 0; }});
    var isSample = !isRef;
    var color = isSample ? '#38bdf8' : '#64748b';
    var lw = isSample ? 3 : 2;
    
    // Horizontal branch
    var hline = document.createElementNS(ns, 'line');
    hline.setAttribute('x1', rootX); hline.setAttribute('y1', y);
    hline.setAttribute('x2', endX); hline.setAttribute('y2', y);
    hline.setAttribute('stroke', color); hline.setAttribute('stroke-width', lw);
    svg.appendChild(hline);
    
    // Node circle
    var circ = document.createElementNS(ns, 'circle');
    circ.setAttribute('cx', endX); circ.setAttribute('cy', y); circ.setAttribute('r', isSample ? 5 : 3);
    circ.setAttribute('fill', color);
    svg.appendChild(circ);
    
    // Label
    var label = p.name.replace(/gi_/g,'').replace(/_gb_/g,' ').replace(/_/g,' ');
    if (label.length > 35) label = label.substring(0, 35) + '...';
    var txt = document.createElementNS(ns, 'text');
    txt.setAttribute('x', endX + 10); txt.setAttribute('y', y + 4);
    txt.setAttribute('fill', color); txt.setAttribute('font-size', isSample ? '13' : '11');
    txt.setAttribute('font-family', 'Inter, sans-serif');
    txt.setAttribute('font-weight', isSample ? '700' : '400');
    txt.textContent = (isSample ? '🔬 ' : '') + label + ' (' + p.dist.toFixed(4) + ')';
    svg.appendChild(txt);
  }}
}}
</script></head><body>

<div class="header"><div>
<h1>🧬 AIV Genomic Intelligence Report</h1>
<div class="sub">Automated Influenza Sequencing · Full Pipeline Analysis</div>
<div class="meta">Report ID: {datetime.now().strftime("%Y%m%d")}-FLU · Generated: {now}</div>
</div></div>

<div class="nav">
<button class="nav-btn active" onclick="showTab('tab-qc')">📊 QC Dashboard</button>
<button class="nav-btn" onclick="showTab('tab-recon')">🔬 Reconstructions</button>
<button class="nav-btn" onclick="showTab('tab-align')">🧬 Alignments</button>
<button class="nav-btn" onclick="showTab('tab-tree')">🌳 Phylogenetic Trees</button>
</div>

<div id="tab-qc" class="tab active"><div class="wrap">
<div class="dash">
<div class="stat"><div class="stat-val">{total_samples}</div><div class="stat-lab">Total Samples</div></div>
<div class="stat"><div class="stat-val" style="color:var(--success)">{success}</div><div class="stat-lab">Successful</div></div>
<div class="stat"><div class="stat-val" style="color:var(--acc)">{total_segs}</div><div class="stat-lab">Segments Found</div></div>
<div class="stat"><div class="stat-val" style="color:var(--warn)">{tree_count}</div><div class="stat-lab">Trees Built</div></div>
</div>
<div class="sec-title">Quality Control Summary</div>
<table><thead><tr><th>Barcode</th><th>Sample Name</th><th>Initial Reads</th><th>IRMA Reads</th><th>% Used</th><th>Efficiency</th><th>Segments</th><th>Status</th></tr></thead>
<tbody>{qc_html}</tbody></table>
</div></div>

<div id="tab-recon" class="tab"><div class="wrap">
<div class="sec-title">Genomic Reconstructions (Triple-View)</div>
{recon_html if recon_html else '<div style="color:var(--muted);padding:40px;text-align:center">No reconstructions found.</div>'}
</div></div>

<div id="tab-align" class="tab"><div class="wrap">
<div class="sec-title">Multiple Sequence Alignments (MUSCLE)</div>
<p style="color:var(--muted);margin-bottom:20px;font-size:.9rem">Automated MUSCLE alignments for each segment. SNPs between sample and reference are highlighted in red.</p>
{align_html if align_html else '<div style="color:var(--muted);padding:40px;text-align:center">No alignments found.</div>'}
</div></div>

<div id="tab-tree" class="tab"><div class="wrap">
<div class="sec-title">Maximum-Likelihood Phylogenetic Trees</div>
<p style="color:var(--muted);margin-bottom:20px;font-size:.9rem">IQ-TREE analysis with automatic model selection. Trees show evolutionary distances between your sample and reference sequences.</p>
{tree_html if tree_html else '<div style="color:var(--muted);padding:40px;text-align:center">No trees generated yet. Need ≥3 sequences per segment.</div>'}
</div></div>

<footer>AIV Genomic Intelligence Report · Automated Influenza Pipeline · Confidential Diagnostic Data</footer>
</body></html>'''
    return html

def main():
    print(f"📊 Analyzing data in {RESULTS_DIR}")
    summary_path = RESULTS_DIR / "04_summary" / "discovery_summary.tsv"
    if not summary_path.exists():
        summary_path = RESULTS_DIR / "04_summary" / "irma_qc_report.tsv"
    summary_rows = load_tsv(summary_path)
    lib_headers = load_library_headers(LIB_FILE)
    reconstructions = load_reconstructions(lib_headers)
    trees = load_trees()
    aligns = load_alignments()
    qc_rows = load_qc()
    if not qc_rows: qc_rows = summary_rows
    html = generate_html(qc_rows, reconstructions, trees, aligns)
    os.makedirs(os.path.dirname(REPORT_FILE), exist_ok=True)
    with open(REPORT_FILE, 'w', encoding='utf-8') as f: f.write(html)
    print(f"✅ Premium Report generated: {REPORT_FILE}")

if __name__ == "__main__": main()
