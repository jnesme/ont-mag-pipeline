#!/bin/bash
### General options
#BSUB -q hpcspecial
#BSUB -J metamdbg_map
#BSUB -n 24
#BSUB -R "span[hosts=1] rusage[mem=5GB]"
#BSUB -M 5500MB
#BSUB -W 12:00
#BSUB -u josne@dtu.dk
#BSUB -B
#BSUB -N
#BSUB -o metamdbg_map_%J.out
#BSUB -e metamdbg_map_%J.err

#==========================================================================
# EDIT THESE BEFORE SUBMITTING
#==========================================================================
ASSEMBLY_DIR="/work3/josne/Projects/DoraMultiOmics/metaMDBG_rescued.all.fastq"   # metaMDBG output dir from step 1 (contains contigs.fasta.gz)
READS="/work3/josne/Projects/DoraMultiOmics/rescued.all.fastq.gz"          # Original ONT reads (.fastq or .fastq.gz) used in step 1
OUTDIR="/work3/josne/Projects/DoraMultiOmics/minimap_vs_contigs"         # Output directory for BAM and mapping stats
THREADS=24
#==========================================================================

CONTIGS="${ASSEMBLY_DIR}/contigs.fasta.gz"
BAM="${OUTDIR}/reads_vs_contigs.bam"

# --- Validate inputs ------------------------------------------------------
if [ -z "${ASSEMBLY_DIR}" ] || [ -z "${READS}" ] || [ -z "${OUTDIR}" ]; then
    echo "ERROR: ASSEMBLY_DIR, READS, and OUTDIR must all be set." >&2
    exit 1
fi
if [ ! -f "${CONTIGS}" ]; then
    echo "ERROR: Contigs not found: ${CONTIGS}" >&2
    exit 1
fi
if [ ! -f "${READS}" ]; then
    echo "ERROR: Reads file not found: ${READS}" >&2
    exit 1
fi

# --- Environment ----------------------------------------------------------
source /work3/josne/miniconda3/etc/profile.d/conda.sh
conda activate /work3/josne/miniconda3/envs/anvio-9

# --- Log header -----------------------------------------------------------
echo "=========================================="
echo "Read mapping (minimap2 → samtools)"
echo "Job started:  $(date)"
echo "Job ID:       ${LSB_JOBID}"
echo "Host:         $(hostname) ($(nproc) CPUs, $(free -h | awk '/^Mem/{print $2}') RAM)"
echo "Contigs:      ${CONTIGS}"
echo "Reads:        ${READS}"
echo "Output BAM:   ${BAM}"
echo "Threads:      ${THREADS}"
echo "=========================================="

mkdir -p "${OUTDIR}"

# Map ONT reads to contigs, sort on the fly — no intermediate SAM on disk
minimap2 -ax map-ont -t "${THREADS}" "${CONTIGS}" "${READS}" \
    | samtools sort -@ "${THREADS}" -o "${BAM}"

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "ERROR: minimap2/samtools sort failed (exit ${EXIT_CODE})" >&2
    exit ${EXIT_CODE}
fi

# Index and QC
samtools index -@ "${THREADS}" "${BAM}"
samtools flagstat -@ "${THREADS}" "${BAM}" > "${BAM%.bam}.flagstat"

# --- Log footer -----------------------------------------------------------
echo "=========================================="
echo "Job finished: $(date)"
echo "Exit code:    $?"
echo ""
echo "--- Mapping summary ---"
cat "${BAM%.bam}.flagstat"
echo "=========================================="
