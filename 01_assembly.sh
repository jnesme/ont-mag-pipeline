#!/bin/bash
### General options
#BSUB -q hpcspecial
#BSUB -J metamdbg_asm
#BSUB -n 24
#BSUB -R "span[hosts=1] rusage[mem=10GB]"
#BSUB -M 10500MB
#BSUB -W 72:00
#BSUB -u josne@dtu.dk
#BSUB -B
#BSUB -N
#BSUB -o metamdbg_asm_%J.out
#BSUB -e metamdbg_asm_%J.err

#==========================================================================
# EDIT THESE BEFORE SUBMITTING
#==========================================================================
INPUT="/work3/josne/Projects/DoraMultiOmics/rescued.all.fastq.gz"              # Path to ONT reads (.fastq or .fastq.gz)
OUTDIR="/work3/josne/Projects/DoraMultiOmics/metaMDBG_rescued.all.fastq"             # Output directory for assembly results
MIN_READ_QUALITY=10   # Minimum average Phred score (set to 0 to disable)
MIN_CONTIG_LENGTH=1000 # Minimum contig length in bp
MIN_CONTIG_COVERAGE=2 # Minimum contig coverage depth
THREADS=24
#==========================================================================

# --- Validate inputs ------------------------------------------------------
if [ -z "${INPUT}" ]; then
    echo "ERROR: INPUT is not set. Edit the script before submitting." >&2
    exit 1
fi
if [ -z "${OUTDIR}" ]; then
    echo "ERROR: OUTDIR is not set. Edit the script before submitting." >&2
    exit 1
fi
if [ ! -f "${INPUT}" ]; then
    echo "ERROR: Input file not found: ${INPUT}" >&2
    exit 1
fi

# --- Environment ----------------------------------------------------------
source /work3/josne/miniconda3/etc/profile.d/conda.sh
conda activate /work3/josne/miniconda3/envs/metaMDBG

# --- Log header -----------------------------------------------------------
echo "=========================================="
echo "metaMDBG Assembly"
echo "Job started:      $(date)"
echo "Job ID:           ${LSB_JOBID}"
echo "Host:             $(hostname) ($(nproc) CPUs, $(free -h | awk '/^Mem/{print $2}') RAM)"
echo "Input reads:      ${INPUT}"
echo "Output dir:       ${OUTDIR}"
echo "Min read quality: ${MIN_READ_QUALITY}"
echo "Min contig len:   ${MIN_CONTIG_LENGTH}"
echo "Min contig cov:   ${MIN_CONTIG_COVERAGE}"
echo "Threads:          ${THREADS}"
echo "Assembly log:     ${OUTDIR}/metaMDBG.log"
echo "  (tail -f ${OUTDIR}/metaMDBG.log  to follow progress)"
echo "=========================================="

mkdir -p "${OUTDIR}"

# Build optional quality filter flag
QUAL_FLAG=""
if [ "${MIN_READ_QUALITY}" -gt 0 ] 2>/dev/null; then
    QUAL_FLAG="--min-read-quality ${MIN_READ_QUALITY}"
fi

# Run assembly (metaMDBG resumes automatically from checkpoints if resubmitted)
metaMDBG asm \
    --out-dir "${OUTDIR}" \
    --in-ont "${INPUT}" \
    --min-contig-length "${MIN_CONTIG_LENGTH}" \
    --min-contig-coverage "${MIN_CONTIG_COVERAGE}" \
    ${QUAL_FLAG} \
    --threads "${THREADS}"

EXIT_CODE=$?

# --- Log footer -----------------------------------------------------------
echo "=========================================="
echo "Job finished:  $(date)"
echo "Exit code:     ${EXIT_CODE}"
if [ ${EXIT_CODE} -eq 0 ] && [ -f "${OUTDIR}/contigs.fasta.gz" ]; then
    N_CONTIGS=$(zgrep -c "^>" "${OUTDIR}/contigs.fasta.gz")
    echo "Contigs:       ${N_CONTIGS}"
fi
echo ""
echo "--- Last 20 lines of metaMDBG.log ---"
tail -20 "${OUTDIR}/metaMDBG.log"
echo "=========================================="

exit ${EXIT_CODE}
