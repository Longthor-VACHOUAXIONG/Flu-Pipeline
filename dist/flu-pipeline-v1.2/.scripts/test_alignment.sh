#!/bin/bash
# .scripts/test_alignment.sh - Run only Alignment and Trees using existing consensus results

# Get the absolute directory where this script is located
# Resolve the base directory (Master Folder)
if [ ! -z "$FLU_PIPELINE_DIR" ]; then
    WORKFLOW_DIR="$FLU_PIPELINE_DIR"
else
    WORKFLOW_DIR=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]:-$0}")")" && pwd | sed 's/\.scripts//')
fi

# Fallback: if .references is not in WORKFLOW_DIR, check standard install path
if [ ! -d "${WORKFLOW_DIR}/.references" ] && [ -d "/usr/local/lib/flu-pipeline/.references" ]; then
    WORKFLOW_DIR="/usr/local/lib/flu-pipeline"
fi

RESULTS_DIR="results_irma"
REF_FILE="${WORKFLOW_DIR}/.references/combined_flu_reference.fasta"
MAFFT="mafft"
IQTREE="iqtree"

# Robust tool detection (handle alternate names like iqtree2)
if ! command -v $MAFFT &>/dev/null; then
    if command -v mafft.bat &>/dev/null; then MAFFT="mafft.bat"
    elif command -v mafft.exe &>/dev/null; then MAFFT="mafft.exe"
    fi
fi

if ! command -v $IQTREE &>/dev/null; then
    if command -v iqtree2 &>/dev/null; then IQTREE="iqtree2"
    elif command -v iqtree.exe &>/dev/null; then IQTREE="iqtree.exe"
    elif command -v iqtree2.exe &>/dev/null; then IQTREE="iqtree2.exe"
    fi
fi

# Handle recursive globbing
shopt -s globstar

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧪  TESTING ALIGNMENT & PHYLOGENY (Skipping IRMA)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 1. Cleanup
echo "▶ Cleaning old results..."
rm -rf "${RESULTS_DIR}/05_alignment" "${RESULTS_DIR}/06_trees"
mkdir -p "${RESULTS_DIR}/05_alignment" "${RESULTS_DIR}/06_trees"

# 2. Extract sequences from existing consensus files
echo "▶ Step 4: Regrouping consensus sequences..."
for FASTA in "${RESULTS_DIR}/03_consensus"/**/*.fasta; do
    [ ! -f "$FASTA" ] && continue
    
    # Identify segment from filename (e.g. A_HA_H5.fasta)
    SEG_NAME=$(basename "$FASTA" | grep -o 'PB2\|PB1\|PA\|HA\|NP\|NA\|MP\|NS' | head -n 1)
    [ -z "$SEG_NAME" ] && continue
    # Identify subtype from directory name
    SAMPLE_SUBTYPE=$(basename "$(dirname "$FASTA")")
    
    ALIGN_SUBTYPE_DIR="${RESULTS_DIR}/05_alignment/${SAMPLE_SUBTYPE}"; mkdir -p "$ALIGN_SUBTYPE_DIR"
    MERGE_FILE="${ALIGN_SUBTYPE_DIR}/${SEG_NAME}_unaligned.fasta"
    ALIGN_ALL_DIR="${RESULTS_DIR}/05_alignment/all"; mkdir -p "$ALIGN_ALL_DIR"
    MERGE_FILE_ALL="${ALIGN_ALL_DIR}/${SEG_NAME}_unaligned.fasta"
    
    # Add references if this is the first time seeing this segment in this subtype
    if [ ! -f "$MERGE_FILE" ]; then
        echo "   ℹ  Adding references for ${SEG_NAME}..."
        awk -v RS=">" -v name="| $SEG_NAME |" 'index($0, name) {
            n = split($0, lines, "\n");
            if (n < 2) next;
            full_hdr = ""; seq = ""; in_seq = 0;
            for (i=1; i<=n; i++) {
                if (lines[i] == "") continue;
                if (!in_seq && (index(lines[i], "|") > 0 || i == 1)) {
                    full_hdr = full_hdr " " lines[i];
                } else {
                    in_seq = 1;
                    seq = seq lines[i];
                }
            }
            m = split(full_hdr, p, "|");
            if (m < 4) next;
            acc = p[m]; gsub(/^[ \t]+|[ \t]+$/, "", acc);
            strain = p[3]; gsub(/^[ \t]+|[ \t]+$/, "", strain);
            if (m == 6) { subtype = p[5]; } else { subtype = p[4]; }
            gsub(/^[ \t]+|[ \t]+$/, "", subtype);
            
            gsub(/[ \/]/, "_", strain); gsub(/\(/, "_", strain); gsub(/\)/, "", strain);
            gsub(/[ \/]/, "_", subtype);
            gsub(/[^A-Za-z0-9_.-]/, "", acc);
            gsub(/[ \t\r\n]/, "", seq);
            if (seq != "") {
                hdr_name = acc "_" strain "_" subtype;
                if (!seen[hdr_name]) {
                    printf ">%s\n%s\n", hdr_name, seq;
                    seen[hdr_name] = 1;
                }
            }
        }' "$REF_FILE" >> "$MERGE_FILE" 2>/dev/null
    fi
    
    if [ ! -f "$MERGE_FILE_ALL" ]; then
        cat "$MERGE_FILE" > "$MERGE_FILE_ALL" 2>/dev/null
    fi
    
    # Add the sample consensus
    echo "   + Adding $(basename "$FASTA")"
    cat "$FASTA" >> "$MERGE_FILE"
    cat "$FASTA" >> "$MERGE_FILE_ALL"
done

# 4. Run Alignment
echo -e "\n▶ Step 5: Automated Multiple Sequence Alignment (MAFFT)..."
for UNALIGNED in "${RESULTS_DIR}/05_alignment"/*/*_unaligned.fasta; do
    [ ! -f "$UNALIGNED" ] && continue
    awk '
    /^>/ {
        if (hdr && !seen[hdr]) { print hdr; print seq; seen[hdr]=1 }
        name=substr($0,2); gsub(/[^A-Za-z0-9_.-]/, "_", name); gsub(/__+/, "_", name);
        hdr=">" name; seq=""
        next
    }
    {
        gsub(/[ \t\r\n]/, "", $0);
        if ($0 != "") seq = seq $0
    }
    END {
        if (hdr && !seen[hdr]) { print hdr; print seq }
    }' "$UNALIGNED" > "${UNALIGNED}.tmp" && mv "${UNALIGNED}.tmp" "$UNALIGNED"
    BASENAME=$(basename "$UNALIGNED" _unaligned.fasta)
    SUBTYPE_DIR_NAME=$(basename "$(dirname "$UNALIGNED")")
    ALIGNED="${RESULTS_DIR}/05_alignment/${SUBTYPE_DIR_NAME}/${BASENAME}_aligned.fasta"
    echo "   ℹ  Aligning ${BASENAME}..."
    $MAFFT --auto --anysymbol "$UNALIGNED" > "$ALIGNED" 2>/dev/null
done

# 5. Run Tree
echo -e "\n▶ Step 6: Automated Phylogenetic Analysis (IQ-TREE)..."
for ALIGNED in "${RESULTS_DIR}/05_alignment"/*/*_aligned.fasta; do
    [ ! -f "$ALIGNED" ] && continue
    # Count sequences (must be at least 3 for a tree)
    COUNT=$(grep -c "^>" "$ALIGNED")
    if [ "$COUNT" -lt 3 ]; then
        echo "   ⚠  Skipping Tree for ${BASENAME} (found $COUNT sequences)"
        continue
    fi
    
    BASENAME=$(basename "$ALIGNED" _aligned.fasta)
    SUBTYPE_DIR_NAME=$(basename "$(dirname "$ALIGNED")")
    TREE_DIR="${RESULTS_DIR}/06_trees/${SUBTYPE_DIR_NAME}"
    mkdir -p "$TREE_DIR"
    
    echo "   ℹ  Building Tree for ${BASENAME} in ${SUBTYPE_DIR_NAME} ($COUNT sequences)..."
    
    # Use TEST model and thread auto-detection like main pipeline
    pushd "$TREE_DIR" > /dev/null
    if [[ "$IQTREE" == *.exe ]]; then
        W_ALIGNED=$(wslpath -w "../../${ALIGNED#${RESULTS_DIR}/}")
        "$IQTREE" -s "$W_ALIGNED" -m GTR+F+G4 -fast -nt AUTO -pre "$BASENAME" -quiet -keep-ident -redo
    else
        $IQTREE -s "../../${ALIGNED#${RESULTS_DIR}/}" -m GTR+F+G4 -fast -nt AUTO -pre "$BASENAME" -quiet -keep-ident -redo
    fi
    popd > /dev/null
done

echo -e "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅  TEST COMPLETE. Check results in ${RESULTS_DIR}/06_trees"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
