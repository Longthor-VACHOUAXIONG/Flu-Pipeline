#!/bin/bash
# ==============================================================================
# INFLUENZA VIRUS SEQUENCING WORKFLOW
# ------------------------------------------------------------------------------
# Developed by: Longthor VACHOUAXIONG
# Purpose: Nanopore Influenza Subtyping & Metadata Pipeline
# ==============================================================================
# CLI Arguments Parsing
RUN_IRMA=true
RUN_ALIGN=true
RUN_TREE=true
RUN_FILL=true
RUN_MAP=true
SHOW_HELP=false

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --irma)  RUN_IRMA=true;  RUN_ALIGN=false; RUN_TREE=false; RUN_FILL=false; RUN_MAP=true ;;
        --align) RUN_IRMA=false; RUN_ALIGN=true;  RUN_TREE=false; RUN_FILL=false; RUN_MAP=false ;;
        --tree)  RUN_IRMA=false; RUN_ALIGN=false; RUN_TREE=true;  RUN_FILL=false; RUN_MAP=false ;;
        --fill)  RUN_IRMA=false; RUN_ALIGN=false; RUN_TREE=false; RUN_FILL=true;  RUN_MAP=false ;;
        --map)   RUN_IRMA=false; RUN_ALIGN=false; RUN_TREE=false; RUN_FILL=false; RUN_MAP=true ;;
        --all)   RUN_IRMA=true;  RUN_ALIGN=true;  RUN_TREE=true;  RUN_FILL=true;  RUN_MAP=true ;;
        -h|--help) SHOW_HELP=true ;;
        *) echo "Error: Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

if [ "$SHOW_HELP" = true ]; then
    echo "Usage: flu-pipeline [options]"
    echo ""
    echo "Options:"
    echo "  --all        Run full workflow (default)"
    echo "  --irma       Run only Barcode mapping + IRMA assembly"
    echo "  --align      Run only Alignment (based on existing results)"
    echo "  --tree       Run only Phylogeny (based on existing alignments)"
    echo "  --fill       Run only Metadata Excel filling"
    echo "  --map        Run only Barcode-to-Sample mapping check"
    echo "  -h, --help   Show this help message"
    exit 0
fi

# ------------------------------------------------------------------------------
# 1. SETUP & CONFIGURATION
# ------------------------------------------------------------------------------
# Resolve the base directory (Master Folder)
if [ ! -z "$FLU_PIPELINE_DIR" ]; then
    WORKFLOW_DIR="$FLU_PIPELINE_DIR"
else
    WORKFLOW_DIR=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]:-$0}")")" && pwd)
fi

# Fallback: if .references is not in WORKFLOW_DIR, check standard install path
if [ ! -d "${WORKFLOW_DIR}/.references" ] && [ -d "/usr/local/lib/flu-pipeline/.references" ]; then
    WORKFLOW_DIR="/usr/local/lib/flu-pipeline"
fi

FASTQ_DIR="fastq_pass"
CONCAT_DIR="concat"
RESULTS_DIR="results_irma"
METADATA_FILE="metadata.xlsx"

# Auto-generate metadata template if it doesn't exist
if [ ! -f "$METADATA_FILE" ]; then
    if [ -f "${WORKFLOW_DIR}/metadata_template.xlsx" ]; then
        echo "▶ metadata.xlsx not found in the current directory."
        echo "   Generating a blank metadata.xlsx template for you..."
        cp "${WORKFLOW_DIR}/metadata_template.xlsx" "$METADATA_FILE"
        echo "✅ Created metadata.xlsx successfully!"
        echo "   Please open it, fill in your sample information, and re-run the pipeline."
        exit 0
    fi
fi

REF_FILE="${WORKFLOW_DIR}/.references/combined_flu_reference.fasta"
PY_MAP_SCRIPT="${WORKFLOW_DIR}/.scripts/process_metadata.py"
RUN_ID="Run_$(date +%Y%m%d)"
MAFFT="mafft"
IQTREE="iqtree"

# Auto-detect and activate conda environment where IRMA is installed
if ! command -v IRMA &>/dev/null && ! command -v irma &>/dev/null; then
    if command -v conda &>/dev/null; then
        eval "$(conda shell.bash hook)"
        # Search all conda environments for IRMA
        IRMA_ENV=""
        for env_path in $(conda env list | grep -v '^#' | awk '{print $NF}' | grep -v '^$'); do
            if [ -f "${env_path}/bin/IRMA" ] || [ -f "${env_path}/bin/irma" ]; then
                IRMA_ENV=$(basename "$env_path")
                break
            fi
        done
        if [ ! -z "$IRMA_ENV" ]; then
            conda activate "$IRMA_ENV" 2>/dev/null
            echo "✅ Conda environment '${IRMA_ENV}' activated"
        else
            # IRMA not found anywhere — auto-install it
            echo "📦 IRMA not found. Installing automatically..."
            conda create -n irma -c cdcgov -c bioconda -c conda-forge irma mafft iqtree -y -q
            conda activate irma 2>/dev/null
        fi
    fi
fi

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

echo "   ℹ  Using MAFFT: $(command -v $MAFFT || echo 'NOT FOUND')"
echo "   ℹ  Using IQ-TREE: $(command -v $IQTREE || echo 'NOT FOUND')"

# Python detection
PYTHON=$(which python 2>/dev/null)
[ -z "$PYTHON" ] && PYTHON=$(which python3 2>/dev/null)
[ -z "$PYTHON" ] && PYTHON=$(which python.exe 2>/dev/null)
[ -z "$PYTHON" ] && PYTHON="python"

echo "   ℹ  Using Python: $PYTHON ($($PYTHON --version 2>&1 | head -n 1))"

# Auto-install Python dependencies
if ! $PYTHON -c "import openpyxl" &>/dev/null; then
    echo "   ℹ  Installing openpyxl..."
    $PYTHON -m pip install openpyxl -q --break-system-packages 2>/dev/null
fi

# Create folder structure
mkdir -p "$CONCAT_DIR" "${RESULTS_DIR}/01_irma_outputs" "${RESULTS_DIR}/03_consensus" "${RESULTS_DIR}/04_summary" "${RESULTS_DIR}/05_alignment" "${RESULTS_DIR}/06_trees" "${RESULTS_DIR}/QC"

# Build combined reference if missing
if [ ! -f "$REF_FILE" ]; then
    echo "   ℹ  Building combined reference library..."
    for f in "${WORKFLOW_DIR}"/.references/A_*.fasta "${WORKFLOW_DIR}"/.references/B_*.fasta; do
        sed '$a\' "$f"
    done > "$REF_FILE" 2>/dev/null
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "▶  Influenza Virus Sequencing - Fully Automated Workflow"
echo "▶  Developed by: Longthor VACHOUAXIONG"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ------------------------------------------------------------------------------
# 1b. LOAD METADATA MAPPING
# ------------------------------------------------------------------------------
if [ "$RUN_MAP" = true ] || [ "$RUN_IRMA" = true ]; then
declare -A NAME_MAP; declare -A SUBTYPE_MAP; declare -A RUN_NO_MAP; declare -A DISPLAY_BC_MAP; declare -A BC_PATH_MAP
if [ -f "$METADATA_FILE" ]; then
    echo -e "\n▶ Loading metadata from $METADATA_FILE..."
    PY_MAP_SCRIPT="${WORKFLOW_DIR}/.scripts/process_metadata.py"
    M_PATH="$METADATA_FILE"
    if [[ "$PYTHON" == *.exe ]]; then
        PY_MAP_SCRIPT=$(wslpath -w "$PY_MAP_SCRIPT")
        M_PATH=$(wslpath -w "$M_PATH")
    fi

    while IFS='|' read -r bc name subtype run_no short_bc; do
        [ -z "$bc" ] && continue
        bc=$(echo "$bc" | tr -d '\r'); name=$(echo "$name" | tr -d '\r')
        run_no=$(echo "$run_no" | tr -d '\r')
        
        # Check standard flat path, then check inside the nested run folder structure
        BC_PATH="${FASTQ_DIR}/${bc}"
        [ ! -d "$BC_PATH" ] && [ ! -z "$run_no" ] && BC_PATH="${FASTQ_DIR}/${run_no}/${bc}"
        [ ! -d "$BC_PATH" ] && [ ! -z "$run_no" ] && BC_PATH="${FASTQ_DIR}/${run_no}/fastq_pass/${run_no}/${bc}"
        
        if [ -d "$BC_PATH" ]; then
            # Use unique key combining run_no and barcode to handle same barcode in different runs
            unique_key="${run_no}_${bc}"
            NAME_MAP["$unique_key"]="$name"; SUBTYPE_MAP["$unique_key"]="$subtype"; RUN_NO_MAP["$unique_key"]="$run_no"
            DISPLAY_BC_MAP["$unique_key"]="${short_bc:-$(echo "$bc" | sed 's/barcode/NB/')}"
            BC_PATH_MAP["$unique_key"]="$BC_PATH"
            echo "   ✓ ${bc} → ${name} (Path: ${BC_PATH})"
        else
            echo "   ⚠️ ${bc} is in metadata, but folder missing under ${FASTQ_DIR}/ (checked: ${FASTQ_DIR}/${bc}, ${FASTQ_DIR}/${run_no}/${bc}, and ${FASTQ_DIR}/${run_no}/fastq_pass/${run_no}/${bc})"
        fi
    done < <("$PYTHON" "$PY_MAP_SCRIPT" map "$M_PATH" 2>/dev/null)
fi
fi

if [ "$RUN_MAP" = true ] && [ "$RUN_IRMA" = false ] && [ "$RUN_ALIGN" = false ] && [ "$RUN_FILL" = false ]; then
    echo -e "\n✅ Mapping check complete. Use --irma to proceed."
    exit 0
fi

# Initialize QC File and Segment Map
QC_FILE="${RESULTS_DIR}/QC/QC_Report_$(date +%Y%m%d).csv"
[ ! -f "$QC_FILE" ] && echo "Barcode,Sample_Name,Initial_Reads,IRMA_Initiate_Reads,Status,Segments_Detected" > "$QC_FILE"

declare -A SEG_MAP
SEG_MAP[1]="PB2"; SEG_MAP[2]="PB1"; SEG_MAP[3]="PA"; SEG_MAP[4]="HA"
SEG_MAP[5]="NP"; SEG_MAP[6]="NA"; SEG_MAP[7]="MP"; SEG_MAP[8]="NS"

# ------------------------------------------------------------------------------
# 2. DATA PREPARATION & ASSEMBLY
# ------------------------------------------------------------------------------
if [ "$RUN_IRMA" = true ]; then
# Robustly find barcode directories in flat structure and nested structure
BARCODES=()
# 1. First check the active paths mapped from metadata
for unique_key in "${!BC_PATH_MAP[@]}"; do
    [ -d "${BC_PATH_MAP[$unique_key]}" ] && BARCODES+=("${BC_PATH_MAP[$unique_key]}")
done

# 2. Fallback to physical scanning if metadata-based map is empty
if [ ${#BARCODES[@]} -eq 0 ]; then
    for d in "${FASTQ_DIR}"/barcode*; do
        [ -d "$d" ] && BARCODES+=("$d")
    done
    for d in "${FASTQ_DIR}"/*/barcode*; do
        [ -d "$d" ] && BARCODES+=("$d")
    done
    for d in "${FASTQ_DIR}"/*/fastq_pass/*/barcode*; do
        [ -d "$d" ] && BARCODES+=("$d")
    done
fi

if [ ${#BARCODES[@]} -eq 0 ]; then
    echo "❌ Error: No barcodes found in ${FASTQ_DIR} (searched mapped, flat, and nested paths)"
    exit 1
fi
rm -f "${RESULTS_DIR}/05_alignment"/*.fasta "${RESULTS_DIR}/06_trees"/*

for BC_DIR in "${BARCODES[@]}"; do
    BARCODE=$(basename "$BC_DIR")
    
    # Find the unique key for this barcode path
    UNIQUE_KEY=""
    for key in "${!BC_PATH_MAP[@]}"; do
        if [ "${BC_PATH_MAP[$key]}" = "$BC_DIR" ]; then
            UNIQUE_KEY="$key"
            break
        fi
    done
    
    [ -z "$UNIQUE_KEY" ] && continue
    [ -z "${NAME_MAP[$UNIQUE_KEY]}" ] && continue
    
    SAMPLE_NAME="${NAME_MAP[$UNIQUE_KEY]}"
    BC_SHORT="${DISPLAY_BC_MAP[$UNIQUE_KEY]}"
    [ -z "$BC_SHORT" ] && BC_SHORT=$(echo "$BARCODE" | sed 's/barcode/NB/')
    CURRENT_RUN_ID="${RUN_NO_MAP[$UNIQUE_KEY]}"; [ -z "$CURRENT_RUN_ID" ] && CURRENT_RUN_ID="$RUN_ID"
    SAMPLE_LABEL="${CURRENT_RUN_ID}_${BC_SHORT}_${SAMPLE_NAME}"
    echo -e "\nProcessing: ${BARCODE} → ${SAMPLE_NAME}"
    CONCAT_FASTQ="${CONCAT_DIR}/${SAMPLE_LABEL}.fastq"
    zcat -f "${BC_DIR}"/*.fastq* > "$CONCAT_FASTQ" 2>/dev/null
    total_reads=$(cat "$CONCAT_FASTQ" | wc -l | awk '{print int($1/4)}')
    if [ "$total_reads" -lt 10 ]; then
        echo "${BARCODE},${SAMPLE_NAME},${total_reads},0,LOW_DATA,0" >> "$QC_FILE"
        continue
    fi
    IRMA_OUT="${RESULTS_DIR}/01_irma_outputs/${SAMPLE_LABEL}"
    if command -v IRMA >/dev/null 2>&1 || command -v irma >/dev/null 2>&1; then
        IRMA_CMD=$(command -v IRMA || command -v irma)
        rm -rf "$IRMA_OUT"
        $IRMA_CMD FLU-minion "$CONCAT_FASTQ" "$IRMA_OUT"
    fi
    ACTUAL_IRMA_OUT="$IRMA_OUT"
    if [ ! -d "$ACTUAL_IRMA_OUT" ] || [ -z "$(ls -A $ACTUAL_IRMA_OUT/*.fasta 2>/dev/null)" ]; then
        LATEST_SUCCESS=""
        CANDIDATES=$(ls -dt ${RESULTS_DIR}/01_irma_outputs/*${BC_SHORT}* 2>/dev/null)
        for folder in $CANDIDATES; do
            if [ -d "$folder" ] && [ ! -z "$(ls -A $folder/*.fasta 2>/dev/null)" ]; then
                LATEST_SUCCESS="$folder"; break
            fi
        done
        [ ! -z "$LATEST_SUCCESS" ] && ACTUAL_IRMA_OUT="$LATEST_SUCCESS"
    fi
    DETECTED_H=""; DETECTED_N=""
    if [ -d "$ACTUAL_IRMA_OUT" ]; then
        for FASTA in "$ACTUAL_IRMA_OUT"/*.fasta; do
            [ ! -f "$FASTA" ] && continue
            FBASE=$(basename "$FASTA" .fasta)
            [[ "$FBASE" == *"_HA_"* ]] && DETECTED_H=$(echo "$FBASE" | grep -o 'H[0-9]\+' | head -n 1)
            [[ "$FBASE" == *"_NA_"* ]] && DETECTED_N=$(echo "$FBASE" | grep -o 'N[0-9]\+' | head -n 1)
        done
    fi
    SAMPLE_SUBTYPE="${DETECTED_H}${DETECTED_N}"
    [ -z "$SAMPLE_SUBTYPE" ] && SAMPLE_SUBTYPE=$(echo "${SUBTYPE_MAP[$UNIQUE_KEY]}" | tr -d ' \r\n' | sed 's/[ /]/_/g')
    [ -z "$SAMPLE_SUBTYPE" ] && SAMPLE_SUBTYPE="Unknown"
    SUBTYPE_DIR="${RESULTS_DIR}/03_consensus/${SAMPLE_SUBTYPE}"; mkdir -p "$SUBTYPE_DIR"
    initiate_reads=0; seg_count=0; status="FAILED"
    if [ -d "$ACTUAL_IRMA_OUT" ] && [ ! -z "$(ls -A $ACTUAL_IRMA_OUT 2>/dev/null)" ]; then
        COUNT_FILE="${ACTUAL_IRMA_OUT}/tables/READ_COUNTS.txt"
        [ -f "$COUNT_FILE" ] && initiate_reads=$(grep '2-passQC' "$COUNT_FILE" | awk '{print $3}')
        for FASTA in "$ACTUAL_IRMA_OUT"/*.fasta; do
            [ ! -f "$FASTA" ] && continue
            FILE_BASE=$(basename "$FASTA" | sed 's/\.fa.*//')
            SEG_RAW=$(echo "$FILE_BASE" | cut -d'_' -f2)
            SEG_NAME="$SEG_RAW"
            [[ "$SEG_RAW" =~ ^[0-9]+$ ]] && SEG_NAME=${SEG_MAP[$SEG_RAW]}
            IRMA_SUBTYPE=$(echo "$FILE_BASE" | cut -d'_' -f3 | grep -E '^[HN][0-9]+$')
            SEQ=$(awk '!/^>/ { printf "%s", $0 } END { printf "\n" }' "$FASTA")
            SUBTYPE_VAL=$(echo "${SUBTYPE_MAP[$UNIQUE_KEY]}" | sed 's/ /_/g')
            CONS_HEADER="${CURRENT_RUN_ID}_${BC_SHORT}_${SAMPLE_NAME}_A_${SEG_NAME}"
            FINAL_SUF="$IRMA_SUBTYPE"
            [ -z "$FINAL_SUF" ] && [[ "$SEG_NAME" == "HA" ]] && FINAL_SUF=$(echo "$SUBTYPE_VAL" | grep -o 'H[0-9]\+' | head -n 1)
            [ -z "$FINAL_SUF" ] && [[ "$SEG_NAME" == "NA" ]] && FINAL_SUF=$(echo "$SUBTYPE_VAL" | grep -o 'N[0-9]\+' | head -n 1)
            [ ! -z "$FINAL_SUF" ] && CONS_HEADER="${CONS_HEADER}_${FINAL_SUF}"
            CONS_FILE="${SUBTYPE_DIR}/${CONS_HEADER}.fasta"
            echo ">${CONS_HEADER}" > "$CONS_FILE"; echo "$SEQ" >> "$CONS_FILE"
            ALIGN_SUBTYPE_DIR="${RESULTS_DIR}/05_alignment/${SAMPLE_SUBTYPE}"; mkdir -p "$ALIGN_SUBTYPE_DIR"
            MERGE_FILE="${ALIGN_SUBTYPE_DIR}/${SEG_NAME}_unaligned.fasta"
            ALIGN_ALL_DIR="${RESULTS_DIR}/05_alignment/all"; mkdir -p "$ALIGN_ALL_DIR"
            MERGE_FILE_ALL="${ALIGN_ALL_DIR}/${SEG_NAME}_unaligned.fasta"
            
            if [ ! -f "$MERGE_FILE" ]; then
                awk -v RS=">" -v name="| $SEG_NAME |" 'index($0, name) {
                    n = split($0, lines, "\n"); if (n < 2) next;
                    full_hdr = ""; seq = ""; in_seq = 0;
                    for (i=1; i<=n; i++) {
                        if (lines[i] == "") continue;
                        if (!in_seq && (index(lines[i], "|") > 0 || i == 1)) { full_hdr = full_hdr " " lines[i]; }
                        else { in_seq = 1; seq = seq lines[i]; }
                    }
                    m = split(full_hdr, p, "|"); if (m < 4) next;
                    acc = p[m]; gsub(/^[ \t]+|[ \t]+$/, "", acc);
                    strain = p[3]; gsub(/^[ \t]+|[ \t]+$/, "", strain);
                    if (m == 6) { subtype = p[5]; } else { subtype = p[4]; }
                    gsub(/^[ \t]+|[ \t]+$/, "", subtype);
                    
                    gsub(/[ \/]/, "_", strain); gsub(/\(/, "_", strain); gsub(/\)/, "", strain);
                    gsub(/[ \/]/, "_", subtype);
                    gsub(/[^A-Za-z0-9_.-]/, "", acc); gsub(/[ \t\r\n]/, "", seq);
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
            
            echo ">${CONS_HEADER}" >> "$MERGE_FILE"; echo "$SEQ" >> "$MERGE_FILE"
            echo ">${CONS_HEADER}" >> "$MERGE_FILE_ALL"; echo "$SEQ" >> "$MERGE_FILE_ALL"
            seg_count=$((seg_count + 1))
        done
        [ "$seg_count" -gt 0 ] && status="SUCCESS"
    fi
    echo "${BARCODE},${SAMPLE_NAME},${total_reads},${initiate_reads},${status},${seg_count}" >> "$QC_FILE"
done
fi

# ------------------------------------------------------------------------------
# 3. ALIGNMENT
# ------------------------------------------------------------------------------
if [ "$RUN_ALIGN" = true ]; then
echo -e "\n▶ Step 5: Alignment (MAFFT)..."
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
    $MAFFT --auto --anysymbol "$UNALIGNED" > "$ALIGNED" 2>/dev/null
done
fi

# ------------------------------------------------------------------------------
# 4. PHYLOGENY
# ------------------------------------------------------------------------------
if [ "$RUN_TREE" = true ]; then
echo -e "\n▶ Step 6: Phylogeny (IQ-TREE)..."
if ! command -v $IQTREE &>/dev/null; then
    echo "❌ Error: IQ-TREE not found."
else
    for ALIGNED in "${RESULTS_DIR}/05_alignment"/*/*_aligned.fasta; do
        [ ! -f "$ALIGNED" ] && continue
        seq_count=$(grep -c ">" "$ALIGNED")
        [ "$seq_count" -lt 3 ] && continue
        BASENAME=$(basename "$ALIGNED" _aligned.fasta)
        SUBTYPE_DIR_NAME=$(basename "$(dirname "$ALIGNED")")
        TREE_DIR="${RESULTS_DIR}/06_trees/${SUBTYPE_DIR_NAME}"
        mkdir -p "$TREE_DIR"
        pushd "$TREE_DIR" > /dev/null
        if [[ "$IQTREE" == *.exe ]]; then
            W_ALIGNED=$(wslpath -w "../../${ALIGNED#${RESULTS_DIR}/}")
            "$IQTREE" -s "$W_ALIGNED" -m GTR+F+G4 -fast -nt AUTO -pre "$BASENAME" -quiet -keep-ident -redo
        else
            $IQTREE -s "../../${ALIGNED#${RESULTS_DIR}/}" -m GTR+F+G4 -fast -nt AUTO -pre "$BASENAME" -quiet -keep-ident -redo
        fi
        popd > /dev/null
    done
fi
fi

# ------------------------------------------------------------------------------
# 5. METADATA FILLING
# ------------------------------------------------------------------------------
if [ "$RUN_FILL" = true ]; then
if [ -f "$METADATA_FILE" ]; then
    echo -e "\n▶ Step 7: Filling metadata..."
    PY_SCRIPT="${WORKFLOW_DIR}/.scripts/process_metadata.py"
    if [[ "$PYTHON" == *.exe ]]; then
        PY_SCRIPT=$(wslpath -w "$PY_SCRIPT"); W_META=$(wslpath -w "$METADATA_FILE"); W_RESULTS=$(wslpath -w "$RESULTS_DIR")
        "$PYTHON" "$PY_SCRIPT" fill "$W_META" "$W_RESULTS"
    else
        $PYTHON "$PY_SCRIPT" fill "$METADATA_FILE" "$RESULTS_DIR"
    fi
fi
cp "$QC_FILE" "${RESULTS_DIR}/04_summary/discovery_summary.tsv"
echo -e "\n✅ Pipeline Complete."
fi
