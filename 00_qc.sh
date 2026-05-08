#!/bin/bash
### General options
#BSUB -q hpcspecial
#BSUB -J nanoqc
#BSUB -n 24
#BSUB -R "span[hosts=1] rusage[mem=5GB]"
#BSUB -M 5500MB
#BSUB -W 12:00
#BSUB -u josne@dtu.dk
#BSUB -B
#BSUB -N
#BSUB -o nanoqc_%J.out
#BSUB -e nanoqc_%J.err

#==========================================================================
# EDIT THESE BEFORE SUBMITTING
#==========================================================================
READS="/work3/josne/Projects/DoraMultiOmics/rescued.all.fastq.gz"
OUTDIR="/work3/josne/Projects/DoraMultiOmics/qc_out"
MIN_QUALITY=8      # Chopper: minimum mean read quality (Phred)
MIN_LENGTH=500     # Chopper: minimum read length (bp)
THREADS=24
#==========================================================================

# --- Validate inputs -------------------------------------------------------
if [ ! -f "${READS}" ]; then
    echo "ERROR: Reads file not found: ${READS}" >&2
    exit 1
fi

# --- Environment ------------------------------------------------------------
source /work3/josne/miniconda3/etc/profile.d/conda.sh
conda activate /work3/josne/miniconda3/envs/nanoQC

# --- Setup ------------------------------------------------------------------
mkdir -p "${OUTDIR}"
TMPDIR_JOB="/tmp/${LSB_JOBID}"
mkdir -p "${TMPDIR_JOB}"
TRIMMED="${TMPDIR_JOB}/trimmed.fastq.gz"   # adapter-trimmed intermediate (local scratch)
FILTERED="${OUTDIR}/qc_reads.fastq.gz"     # final output → input to 01_assembly.sh

# --- Log header -------------------------------------------------------------
echo "=========================================="
echo "Read QC — Porechop_ABI + Chopper + NanoStat + NanoPlot"
echo "Job started:  $(date)"
echo "Job ID:       ${LSB_JOBID}"
echo "Host:         $(hostname) ($(nproc) CPUs, $(free -h | awk '/^Mem/{print $2}') RAM)"
echo "Reads:        ${READS}"
echo "Output dir:   ${OUTDIR}"
echo "Min quality:  Q${MIN_QUALITY}"
echo "Min length:   ${MIN_LENGTH} bp"
echo "Threads:      ${THREADS}"
echo "=========================================="

# --- Pre-QC stats -----------------------------------------------------------
echo ""
echo "--- Pre-QC: NanoPlot ---"
NanoPlot --fastq "${READS}" \
    --outdir "${OUTDIR}/nanoplot_raw" \
    --threads "${THREADS}" \
    --N50 \
    --title "Raw reads" \
    --loglength \
    --no_static \
    --downsample 100000

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "ERROR: NanoPlot (raw) failed (exit ${EXIT_CODE})" >&2
    exit ${EXIT_CODE}
fi

# --- Adapter trimming (Porechop_ABI) ----------------------------------------
echo ""
echo "--- Adapter trimming: Porechop_ABI ---"
porechop_abi \
    --input "${READS}" \
    --output "${TRIMMED}" \
    --threads "${THREADS}"

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "ERROR: Porechop_ABI failed (exit ${EXIT_CODE})" >&2
    exit ${EXIT_CODE}
fi

# --- Quality + length filtering (Chopper) -----------------------------------
echo ""
echo "--- Quality + length filtering: Chopper (Q>=${MIN_QUALITY}, len>=${MIN_LENGTH} bp) ---"
zcat "${TRIMMED}" \
    | chopper \
        --quality "${MIN_QUALITY}" \
        --minlength "${MIN_LENGTH}" \
        --threads "${THREADS}" \
    | gzip > "${FILTERED}"

PIPE_STATUS=("${PIPESTATUS[@]}")
if [ ${PIPE_STATUS[1]} -ne 0 ]; then
    echo "ERROR: Chopper failed (exit ${PIPE_STATUS[1]})" >&2
    exit ${PIPE_STATUS[1]}
fi

# Trimmed intermediate no longer needed
rm -f "${TRIMMED}"

# --- Post-QC stats ----------------------------------------------------------
echo ""
echo "--- Post-QC: NanoPlot ---"
NanoPlot --fastq "${FILTERED}" \
    --outdir "${OUTDIR}/nanoplot_filtered" \
    --threads "${THREADS}" \
    --N50 \
    --title "Filtered reads (Q>=${MIN_QUALITY}, len>=${MIN_LENGTH} bp)" \
    --loglength \
    --no_static \
    --downsample 100000

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "ERROR: NanoPlot (filtered) failed (exit ${EXIT_CODE})" >&2
    exit ${EXIT_CODE}
fi

# --- Log footer -------------------------------------------------------------
echo ""
echo "=========================================="
echo "Job finished: $(date)"
echo "Exit code:    0"
echo ""
echo "Outputs:"
echo "  Filtered reads:     ${FILTERED}"
echo "  NanoPlot raw:       ${OUTDIR}/nanoplot_raw/NanoPlot-report.html"
echo "  NanoPlot filtered:  ${OUTDIR}/nanoplot_filtered/NanoPlot-report.html"
echo ""
echo "Next step: update READS in 01_assembly.sh to:"
echo "  ${FILTERED}"
echo "=========================================="
