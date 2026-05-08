#!/bin/bash
### General options
#BSUB -q milan
#BSUB -J gtdbtk
#BSUB -n 24
#BSUB -R "span[hosts=1] rusage[mem=16GB]"
#BSUB -M 16500MB
#BSUB -W 12:00
#BSUB -u josne@dtu.dk
#BSUB -B
#BSUB -N
#BSUB -o gtdbtk_%J.out
#BSUB -e gtdbtk_%J.err

#==========================================================================
# EDIT THESE BEFORE SUBMITTING
#==========================================================================
BINS_DIR="/work3/josne/Projects/DoraMultiOmics/semibin2_out/output_bins"   # SemiBin2 bins (from 03_semibin2.sh)
OUTDIR="/work3/josne/Projects/DoraMultiOmics/gtdbtk_out"
GTDBTK_DB="/work3/josne/miniconda3/envs/gtdbtk/share/gtdbtk-2.7.1/db"
EXTENSION="fa"      # bin FASTA extension (matches SemiBin2 output_bins/*.fa)
THREADS=24
# pplacer spawns one independent process per CPU; each loads the full reference
# tree (~165 GB bacteria, ~14 GB archaea). With 8 MAGs and 384 GB available,
# PPLACER_CPUS=1 is safe and sufficient.
PPLACER_CPUS=1
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

# Check that the GTDB-Tk database has been extracted
if [ ! -d "${GTDBTK_DB}/taxonomy" ]; then
    TARBALL="${GTDBTK_DB}/gtdbtk_r232_data.tar.gz"
    echo "ERROR: GTDB-Tk database not extracted at ${GTDBTK_DB}" >&2
    if [ -f "${TARBALL}" ]; then
        echo "       Tarball found. Extract with:" >&2
        echo "         cd $(dirname "${TARBALL}")" >&2
        echo "         tar -I 'pigz -p 4' -xf $(basename "${TARBALL}")" >&2
    else
        echo "       Tarball not found at ${TARBALL}" >&2
        echo "       Download: https://data.gtdb.ecogenomic.org/releases/release232/" >&2
    fi
    exit 1
fi

# --- Environment ------------------------------------------------------------
source /work3/josne/miniconda3/etc/profile.d/conda.sh
conda activate /work3/josne/miniconda3/envs/gtdbtk

export GTDBTK_DATA_PATH="${GTDBTK_DB}"

# --- Log header -------------------------------------------------------------
echo "=========================================="
echo "GTDB-Tk — taxonomic classification and phylogenetic placement"
echo "Job started:   $(date)"
echo "Job ID:        ${LSB_JOBID}"
echo "Host:          $(hostname) ($(nproc) CPUs, $(free -h | awk '/^Mem/{print $2}') RAM)"
echo "Bins:          ${BINS_DIR} (${N_BINS} bins, .${EXTENSION})"
echo "Output dir:    ${OUTDIR}"
echo "Database:      ${GTDBTK_DB}"
echo "Threads:       ${THREADS}"
echo "pplacer CPUs:  ${PPLACER_CPUS}"
echo "=========================================="

mkdir -p "${OUTDIR}"

gtdbtk classify_wf \
    --genome_dir "${BINS_DIR}" \
    --out_dir "${OUTDIR}" \
    --cpus "${THREADS}" \
    --pplacer_cpus "${PPLACER_CPUS}" \
    --extension "${EXTENSION}"

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "ERROR: GTDB-Tk failed (exit ${EXIT_CODE})" >&2
    exit ${EXIT_CODE}
fi

# --- Summary ----------------------------------------------------------------
BACT_SUMMARY="${OUTDIR}/classify/gtdbtk.bac120.summary.tsv"
AR_SUMMARY="${OUTDIR}/classify/gtdbtk.ar53.summary.tsv"

N_BACT=0
N_ARCH=0
[ -f "${BACT_SUMMARY}" ] && N_BACT=$(( $(wc -l < "${BACT_SUMMARY}") - 1 ))
[ -f "${AR_SUMMARY}" ]   && N_ARCH=$(( $(wc -l < "${AR_SUMMARY}") - 1 ))

echo "=========================================="
echo "Job finished:      $(date)"
echo "Exit code:         0"
echo "Bacterial MAGs:    ${N_BACT}"
echo "Archaeal MAGs:     ${N_ARCH}"
[ -f "${BACT_SUMMARY}" ] && echo "  ${BACT_SUMMARY}"
[ -f "${AR_SUMMARY}" ]   && echo "  ${AR_SUMMARY}"
echo "=========================================="
