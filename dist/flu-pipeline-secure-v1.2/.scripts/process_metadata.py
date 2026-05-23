#!/usr/bin/env python3
"""
Metadata Processor for AIV Workflow (Header-Mapped Version)
============================================================
Two modes:
  1) map   — Reads metadata.xlsx, prints barcode|Long_name|Subtype|RunNo|ShortBC
  2) fill  — After pipeline, reads QC + IRMA results and fills columns by header name

Usage:
  python process_metadata.py map   <metadata.xlsx>
  python process_metadata.py fill  <metadata.xlsx> <results_dir>
"""
import sys
import os
import glob
import re
from pathlib import Path

try:
    import openpyxl
except ImportError:
    print("ERROR: openpyxl not installed. Run: pip install openpyxl", file=sys.stderr)
    sys.exit(1)

# ---------------------------------------------------------------------------
# Header Names to look for in metadata.xlsx
# ---------------------------------------------------------------------------
HDR_SAMPLE_ID    = "Sample ID"
HDR_RUN_NO       = "Run No"
HDR_SUBTYPE      = "Type from PCR"
HDR_BARCODE      = "Barcode"           # e.g. barcode01
HDR_SHORT_BC     = "Barcode_Display"   # e.g. NB01, RB01
HDR_GISAID       = "GISAID name"
HDR_LONGNAME     = "Long_name"

HDR_NUM_READS    = "Number of reads"
HDR_NUM_IRMA     = "Number of Read starting IRMA"
HDR_PCT_IRMA     = "% Starting IRMA"
HDR_MAPPED_TOT   = "Mapped reads"

# Per-segment headers (Look for "Seg_Reads" and "Seg_Cov")
SEG_NAMES = ["PB2", "PB1", "PA", "HA", "NP", "NA", "MP", "NS"]

SEG_EXPECTED_LEN = {
    "PB2": 2341, "PB1": 2341, "PA": 2233, "HA": 1778,
    "NP": 1565, "NA": 1413, "MP": 1027, "NS": 890
}

def get_header_map(ws):
    """Creates a map of {Header_Name: Column_Index} (0-based)."""
    h_map = {}
    for cell in ws[1]:
        if cell.value:
            h_map[str(cell.value).strip()] = cell.column - 1
    return h_map

def get_depth_range(irma_dir, segment):
    """Parses *-coverage.txt (preferred) or *-allAlleles.txt to find min and max coverage."""
    if not irma_dir or not irma_dir.exists():
        return "0-0"
    
    # Try coverage.txt first
    pattern = str(irma_dir / "tables" / f"*{segment}*-coverage.txt")
    files = glob.glob(pattern)
    depth_col = "Coverage Depth"
    
    if not files:
        # Fallback to allAlleles
        pattern = str(irma_dir / "tables" / f"*{segment}*-allAlleles.txt")
        files = glob.glob(pattern)
        depth_col = "Total"
        
    if not files:
        return "0-0"
    
    min_d = None
    max_d = 0
    try:
        with open(files[0], 'r') as f:
            header = f.readline().strip().split('\t')
            try:
                total_idx = header.index(depth_col)
            except ValueError:
                total_idx = 4 if depth_col == "Total" else 2
                
            for line in f:
                parts = line.split('\t')
                if len(parts) > total_idx:
                    try:
                        d = int(parts[total_idx])
                        if min_d is None or d < min_d: min_d = d
                        if d > max_d: max_d = d
                    except: continue
    except:
        return "0-0"
        
    if min_d is None: return "0-0"
    return f"{min_d}-{max_d}"


def mode_map(xlsx_path):
    """Print barcode|Long_name|Subtype|RunNo|ShortBC mapping to stdout."""
    wb = openpyxl.load_workbook(xlsx_path, read_only=True)
    ws = wb.active
    h = get_header_map(ws)

    # Required columns
    c_bc = h.get(HDR_BARCODE)
    c_name = h.get(HDR_LONGNAME)
    c_sub = h.get(HDR_SUBTYPE)
    c_run = h.get(HDR_RUN_NO)
    c_short = h.get(HDR_SHORT_BC)

    if c_bc is None:
        print(f"ERROR: Could not find '{HDR_BARCODE}' header in {xlsx_path}", file=sys.stderr)
        sys.exit(1)

    for row in ws.iter_rows(min_row=2, values_only=True):
        barcode = row[c_bc]
        if barcode is None: continue

        barcode = str(barcode).strip().replace('\r', '').replace('\n', '')
        name = str(row[c_name]).strip() if c_name is not None and row[c_name] else barcode
        subtype = str(row[c_sub]).strip() if c_sub is not None and row[c_sub] else ""
        run_no = str(row[c_run]).strip() if c_run is not None and row[c_run] else ""
        short_bc = str(row[c_short]).strip() if c_short is not None and row[c_short] else ""

        # Output: barcode|Long_name|Subtype|RunNo|ShortBC
        print(f"{barcode}|{name}|{subtype}|{run_no}|{short_bc}")

    wb.close()


def mode_runid(xlsx_path):
    """Extract the first Run No found in the metadata."""
    wb = openpyxl.load_workbook(xlsx_path, read_only=True)
    ws = wb.active
    h = get_header_map(ws)
    c_run = h.get(HDR_RUN_NO)
    
    if c_run is not None:
        for row in ws.iter_rows(min_row=2, values_only=True):
            run_no = row[c_run]
            if run_no and str(run_no).strip():
                print(str(run_no).strip().replace('\r', '').replace('\n', ''))
                break
    wb.close()


def mode_fill(xlsx_path, results_dir):
    """Fill metadata.xlsx with pipeline results using header mapping."""
    results_dir = Path(results_dir)
    wb = openpyxl.load_workbook(xlsx_path)
    ws = wb.active
    h = get_header_map(ws)

    # Required columns for finding data
    c_bc = h.get(HDR_BARCODE)
    c_name = h.get(HDR_LONGNAME)
    c_run = h.get(HDR_RUN_NO)
    c_short = h.get(HDR_SHORT_BC)

    if c_bc is None:
        print(f"ERROR: Could not find '{HDR_BARCODE}' header in {xlsx_path}", file=sys.stderr)
        sys.exit(1)

    # Parse QC files (Newest first, don't overwrite)
    qc_data = {}
    qc_files = sorted(glob.glob(str(results_dir / "QC" / "*.csv")), reverse=True)
    if qc_files:
        import csv
        for qcf in qc_files:
            try:
                with open(qcf, newline='', encoding='utf-8', errors='ignore') as f:
                    reader = csv.DictReader(f)
                    for r in reader:
                        bc = r.get('Barcode', '').strip()
                        if bc and bc not in qc_data:
                            qc_data[bc] = r
            except: continue

    irma_base = results_dir / "01_irma_outputs"
    consensus_dir = results_dir / "03_consensus"

    for row in ws.iter_rows(min_row=2):
        barcode = row[c_bc].value
        if barcode is None: continue
        barcode = str(barcode).strip()
        
        long_name = row[c_name].value if c_name is not None and row[c_name].value else barcode
        run_no = row[c_run].value if c_run is not None and row[c_run].value else "*"
        short_bc = row[c_short].value if c_short is not None and row[c_short].value else barcode.replace("barcode", "NB")
            
        # --- Find IRMA output directory (Latest with FASTA) ---
        irma_dir = None
        candidates = []
        
        # Primary match: RunID_Barcode_SampleName (most specific)
        if run_no and run_no != "*":
            for bc_id in [short_bc, barcode]:
                pattern = str(irma_base / f"{run_no}_{bc_id}_*")
                primary_matches = glob.glob(pattern)
                if primary_matches:
                    candidates.extend(primary_matches)
                    # If primary match found, don't add secondary matches to avoid confusion
                    break
        
        # Secondary match: by barcode only (fallback) - only if no primary match
        if not candidates:
            for bc_id in [short_bc, barcode]:
                pattern = str(irma_base / f"*_{bc_id}_*")
                candidates.extend(glob.glob(pattern))
                candidates.append(str(irma_base / bc_id))
        
        # Robust candidate matching: also match by unique sample Long_name to survive barcode display name typos (e.g. NB001 vs NB21)
        if long_name and not candidates:
            pattern = str(irma_base / f"*_{long_name}*")
            candidates.extend(glob.glob(pattern))
        
        # Sort candidates by modification time (newest first)
        candidates = sorted(candidates, key=lambda x: os.path.getmtime(x) if os.path.exists(x) else 0, reverse=True)
        
        for cand in candidates:
            cand_path = Path(cand)
            if cand_path.exists() and cand_path.is_dir():
                # Check if it has fasta files
                if list(cand_path.glob("*.fasta")):
                    irma_dir = cand_path
                    break
        
        if irma_dir:
            print(f"  🔍 Processing {barcode}: using results from {irma_dir.name}")

        # --- Extract Read Totals ---
        total_reads = 0
        irma_reads = 0
        if irma_dir and irma_dir.exists():
            count_file = irma_dir / "tables" / "READ_COUNTS.txt"
            if count_file.exists():
                with open(count_file) as cf:
                    for line in cf:
                        line = line.strip()
                        if not line or line.startswith('Record'): continue
                        parts = line.split()
                        if len(parts) < 2: continue
                        if parts[0] == '1-initial' and total_reads == 0:
                            total_reads = int(parts[1])
                        elif parts[0] == '2-passQC' and irma_reads == 0:
                            irma_reads = int(parts[2]) if len(parts) > 2 and parts[2].isdigit() else int(parts[1])
        
        if total_reads == 0 or irma_reads == 0:
            qc = qc_data.get(barcode, {})
            if total_reads == 0: total_reads = int(qc.get('Initial_Reads', 0)) if qc.get('Initial_Reads') else 0
            if irma_reads == 0: irma_reads = int(qc.get('IRMA_Initiate_Reads', 0)) if qc.get('IRMA_Initiate_Reads') else 0

        if h.get(HDR_NUM_READS) is not None: row[h[HDR_NUM_READS]].value = total_reads
        if h.get(HDR_NUM_IRMA) is not None: row[h[HDR_NUM_IRMA]].value = irma_reads
        if h.get(HDR_PCT_IRMA) is not None:
            row[h[HDR_PCT_IRMA]].value = round(irma_reads / total_reads * 100, 2) if total_reads > 0 else 0

        # --- Per-segment counts ---
        seg_reads = {}
        if irma_dir and irma_dir.exists():
            count_file = irma_dir / "tables" / "READ_COUNTS.txt"
            if count_file.exists():
                with open(count_file) as cf:
                    for line in cf:
                        if not line.startswith('4-'): continue
                        parts = line.split()
                        if len(parts) < 2: continue
                        count = int(parts[2]) if len(parts) > 2 and parts[2].isdigit() else int(parts[1])
                        for seg in SEG_NAMES:
                            if f"_{seg}" in parts[0].upper():
                                seg_reads[seg] = seg_reads.get(seg, 0) + count

        total_mapped = 0
        for seg in SEG_NAMES:
            hdr_reads = f"{seg}_Reads"
            hdr_pct = f"{seg}_Pct"
            sr = seg_reads.get(seg, 0)
            total_mapped += sr
            if h.get(hdr_reads) is not None: row[h[hdr_reads]].value = sr
            if h.get(hdr_pct) is not None:
                row[h[hdr_pct]].value = round(sr / irma_reads * 100, 2) if irma_reads > 0 else 0

        if h.get(HDR_MAPPED_TOT) is not None: row[h[HDR_MAPPED_TOT]].value = total_mapped

        # --- Per-segment consensus lengths and coverage ---
        for seg in SEG_NAMES:
            hdr_len = f"{seg}_Len"
            hdr_cov = f"{seg}_Cov"
            
            pattern = str(consensus_dir / "**" / f"*{short_bc}*_{long_name}_A_{seg}*.fasta")
            consensus_files = sorted(glob.glob(pattern, recursive=True), reverse=True)
            if not consensus_files:
                pattern = str(consensus_dir / "**" / f"*{barcode}*_{long_name}_A_{seg}*.fasta")
                consensus_files = sorted(glob.glob(pattern, recursive=True), reverse=True)

            if consensus_files:
                with open(consensus_files[0]) as cf:
                    lines = cf.readlines()
                    seq = "".join(l.strip() for l in lines[1:] if not l.startswith(">"))
                    seq_len = len(seq.replace("N", "").replace("-", ""))
                    full_len = len(seq)
                    if h.get(hdr_len) is not None: row[h[hdr_len]].value = full_len
                    depth_range = get_depth_range(irma_dir, seg)
                    expected = SEG_EXPECTED_LEN.get(seg, full_len)
                    if h.get(hdr_cov) is not None: row[h[hdr_cov]].value = depth_range
            else:
                if h.get(hdr_len) is not None: row[h[hdr_len]].value = 0
                if h.get(hdr_cov) is not None: row[h[hdr_cov]].value = "0-0"

    wb.save(xlsx_path)
    wb.close()
    print(f"✅ Metadata filled and saved to {xlsx_path}")


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)

    mode = sys.argv[1]
    xlsx_path = sys.argv[2]

    if not os.path.exists(xlsx_path):
        print(f"ERROR: File not found: {xlsx_path}", file=sys.stderr)
        sys.exit(1)

    if mode == "map":
        mode_map(xlsx_path)
    elif mode == "runid":
        mode_runid(xlsx_path)
    elif mode == "fill":
        if len(sys.argv) < 4:
            print("ERROR: fill mode requires results_dir", file=sys.stderr)
            sys.exit(1)
        mode_fill(xlsx_path, sys.argv[3])
    else:
        print(f"ERROR: Unknown mode '{mode}'. Use 'map' or 'fill'.", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
