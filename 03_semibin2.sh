#!/bin/bash
### General options
#BSUB -q hpcspecial
#BSUB -J semibin2
#BSUB -n 24
#BSUB -R "span[hosts=1] rusage[mem=8GB]"
#BSUB -M 8500MB
#BSUB -W 24:00
#BSUB -u josne@dtu.dk
#BSUB -B
#BSUB -N
#BSUB -o semibin2_%J.out
#BSUB -e semibin2_%J.err

#==========================================================================
# EDIT THESE BEFORE SUBMITTING
#==========================================================================
ASSEMBLY_DIR="/work3/josne/Projects/DoraMultiOmics/metaMDBG_rescued.all.fastq"   # metaMDBG output dir from step 1 (contains contigs.fasta.gz)
BAM="/work3/josne/Projects/DoraMultiOmics/minimap_vs_contigs/reads_vs_contigs.bam"            # Sorted BAM from step 2 (reads_vs_contigs.bam)
OUTDIR="/work3/josne/Projects/DoraMultiOmics/semibin2_out"         # Output directory for SemiBin2 bins
THREADS=24
#==========================================================================

CONTIGS="${ASSEMBLY_DIR}/contigs.fasta.gz"

# --- Validate inputs ------------------------------------------------------
if [ -z "${ASSEMBLY_DIR}" ] || [ -z "${BAM}" ] || [ -z "${OUTDIR}" ]; then
    echo "ERROR: ASSEMBLY_DIR, BAM, and OUTDIR must all be set." >&2
    exit 1
fi
if [ ! -f "${CONTIGS}" ]; then
    echo "ERROR: Contigs not found: ${CONTIGS}" >&2
    exit 1
fi
if [ ! -f "${BAM}" ]; then
    echo "ERROR: BAM file not found: ${BAM}" >&2
    exit 1
fi
if [ ! -f "${BAM}.bai" ]; then
    echo "ERROR: BAM index not found: ${BAM}.bai — run step 2 first." >&2
    exit 1
fi

# --- Environment ----------------------------------------------------------
source /work3/josne/miniconda3/etc/profile.d/conda.sh
conda activate /work3/josne/miniconda3/envs/semibin2

# --- Log header -----------------------------------------------------------
echo "=========================================="
echo "SemiBin2 binning"
echo "Job started:  $(date)"
echo "Job ID:       ${LSB_JOBID}"
echo "Host:         $(hostname) ($(nproc) CPUs, $(free -h | awk '/^Mem/{print $2}') RAM)"
echo "Contigs:      ${CONTIGS}"
echo "BAM:          ${BAM}"
echo "Output dir:   ${OUTDIR}"
echo "Training:     self-supervised"
echo "Threads:      ${THREADS}"
echo "=========================================="

mkdir -p "${OUTDIR}"

# Run SemiBin2 — single-sample mode, long-read preset
SemiBin2 single_easy_bin \
    --input-fasta "${CONTIGS}" \
    --input-bam "${BAM}" \
    --output "${OUTDIR}" \
    --self-supervised \
    --sequencing-type long_read \
    --threads "${THREADS}"

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "ERROR: SemiBin2 failed (exit ${EXIT_CODE})" >&2
    exit ${EXIT_CODE}
fi

# --- Generate scaffold-to-bin TSV for DAStool ----------------------------
# Format: contig_name <tab> bin_name (no header)
SCAFFOLD2BIN="${OUTDIR}/semibin2_contigs2bins.tsv"
> "${SCAFFOLD2BIN}"
for bin in "${OUTDIR}/output_bins/"*.fa; do
    [ -f "${bin}" ] || continue
    bin_name=$(basename "${bin}" .fa)
    grep "^>" "${bin}" | sed 's/^>//' | awk -v b="${bin_name}" '{print $1"\t"b}'
done >> "${SCAFFOLD2BIN}"

# --- Log footer -----------------------------------------------------------
N_BINS=$(ls "${OUTDIR}/output_bins/"*.fa 2>/dev/null | wc -l)
N_CONTIGS=$(wc -l < "${SCAFFOLD2BIN}")
echo "=========================================="
echo "Job finished: $(date)"
echo "Exit code:    ${EXIT_CODE}"
echo "Bins:         ${N_BINS}"
echo "Contigs binned: ${N_CONTIGS}"
echo "Scaffold2bin: ${SCAFFOLD2BIN}"
echo "=========================================="
