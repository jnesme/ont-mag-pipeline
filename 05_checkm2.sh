#!/bin/bash
### General options
#BSUB -q hpcspecial
#BSUB -J checkm2
#BSUB -n 24
#BSUB -R "span[hosts=1] rusage[mem=3GB]"
#BSUB -M 3500MB
#BSUB -W 04:00
#BSUB -u josne@dtu.dk
#BSUB -B
#BSUB -N
#BSUB -o checkm2_%J.out
#BSUB -e checkm2_%J.err

#==========================================================================
# EDIT THESE BEFORE SUBMITTING
#==========================================================================
BINS_DIR="/work3/josne/Projects/DoraMultiOmics/semibin2_out/output_bins"   # SemiBin2 bin FASTA files
OUTDIR="/work3/josne/Projects/DoraMultiOmics/checkm2_out"
CHECKM2_DB="/work3/josne/Databases/CheckM2_database/uniref100.KO.1.dmnd"   # path to .dmnd file
EXTENSION="fa.gz"
THREADS=24
#==========================================================================

# --- Validate inputs -------------------------------------------------------
if [ ! -d "${BINS_DIR}" ]; then
    echo "ERROR: Bins directory not found: ${BINS_DIR}" >&2
    exit 1
fi

N_BINS=$(find "${BINS_DIR}" -maxdepth 1 -name "*.${EXTENSION}" | wc -l)
if [ "${N_BINS}" -eq 0 ]; then
    echo "ERROR: No .${EXTENSION} files found in ${BINS_DIR}" >&2
    exit 1
fi

if [ ! -f "${CHECKM2_DB}" ]; then
    echo "ERROR: CheckM2 database not found: ${CHECKM2_DB}" >&2
    echo "       Download with:" >&2
    echo "         conda activate /work3/josne/miniconda3/envs/checkm2" >&2
    echo "         checkm2 database --download --path \$(dirname ${CHECKM2_DB})" >&2
    exit 1
fi

# --- Environment ------------------------------------------------------------
source /work3/josne/miniconda3/etc/profile.d/conda.sh
conda activate /work3/josne/miniconda3/envs/checkm2

# --- Log header -------------------------------------------------------------
echo "=========================================="
echo "CheckM2 — bin quality assessment"
echo "Job started:  $(date)"
echo "Job ID:       ${LSB_JOBID}"
echo "Host:         $(hostname) ($(nproc) CPUs, $(free -h | awk '/^Mem/{print $2}') RAM)"
echo "Bins:         ${BINS_DIR} (${N_BINS} bins, .${EXTENSION})"
echo "Output dir:   ${OUTDIR}"
echo "Database:     ${CHECKM2_DB}"
echo "Threads:      ${THREADS}"
echo "=========================================="

mkdir -p "${OUTDIR}"

checkm2 predict \
    --input "${BINS_DIR}" \
    --output-directory "${OUTDIR}" \
    --database_path "${CHECKM2_DB}" \
    --extension "${EXTENSION}" \
    --threads "${THREADS}"

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "ERROR: CheckM2 failed (exit ${EXIT_CODE})" >&2
    exit ${EXIT_CODE}
fi

# --- Summary ----------------------------------------------------------------
REPORT="${OUTDIR}/quality_report.tsv"

echo "=========================================="
echo "Job finished: $(date)"
echo "Exit code:    0"
echo "Report:       ${REPORT}"
echo ""
# Print bins meeting HQ threshold (completeness >= 90, contamination <= 5)
echo "--- High-quality bins (completeness >= 90%, contamination <= 5%) ---"
awk -F'\t' 'NR==1 || ($2 >= 90 && $3 <= 5) {print $1"\t"$2"\t"$3}' "${REPORT}"
echo ""
echo "--- Medium-quality bins (completeness >= 50%, contamination <= 10%) ---"
awk -F'\t' 'NR>1 && ($2 >= 50 && $3 <= 10) && !($2 >= 90 && $3 <= 5) {print $1"\t"$2"\t"$3}' "${REPORT}"
echo "=========================================="
