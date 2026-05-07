#!/bin/bash
### General options
#BSUB -q hpcspecial
#BSUB -J metamdbg_gfa
#BSUB -n 24
#BSUB -R "span[hosts=1] rusage[mem=4GB]"
#BSUB -M 4500MB
#BSUB -W 4:00
#BSUB -u josne@dtu.dk
#BSUB -B
#BSUB -N
#BSUB -o metamdbg_gfa_%J.out
#BSUB -e metamdbg_gfa_%J.err

#==========================================================================
# EDIT THESE BEFORE SUBMITTING
#==========================================================================
ASSEMBLY_DIR="/work3/josne/Projects/DoraMultiOmics/metaMDBG_rescued.all.fastq"   # metaMDBG output dir from step 1
K="101"              # k value for GFA export — leave blank to list available
                  # values and exit, then re-submit with a chosen K.
                  # Higher K = simpler graph, closer to final contigs.
                  # Lower K = denser graph, more connectivity shown.
COVERAGE=true     # Recompute unitig coverage (recommended: colors nodes by
                  # depth in Bandage, essential for spotting plasmids/repeats)
THREADS=24
#==========================================================================

# --- Validate inputs ------------------------------------------------------
if [ -z "${ASSEMBLY_DIR}" ]; then
    echo "ERROR: ASSEMBLY_DIR is not set." >&2
    exit 1
fi
if [ ! -d "${ASSEMBLY_DIR}" ]; then
    echo "ERROR: Assembly directory not found: ${ASSEMBLY_DIR}" >&2
    exit 1
fi

# --- Environment ----------------------------------------------------------
source /work3/josne/miniconda3/etc/profile.d/conda.sh
conda activate /work3/josne/miniconda3/envs/metaMDBG

# --- Discover available k values if K not set ----------------------------
if [ -z "${K}" ]; then
    echo "K not set — listing available k values in ${ASSEMBLY_DIR}:"
    echo ""
    metaMDBG gfa --assembly-dir "${ASSEMBLY_DIR}" --k 0 --threads "${THREADS}"
    echo ""
    echo "Re-submit with K set to your chosen value."
    echo "Recommendation: use the highest available k for the cleanest graph."
    exit 0
fi

# --- Log header -----------------------------------------------------------
echo "=========================================="
echo "metaMDBG GFA export"
echo "Job started:    $(date)"
echo "Job ID:         ${LSB_JOBID}"
echo "Host:           $(hostname) ($(nproc) CPUs, $(free -h | awk '/^Mem/{print $2}') RAM)"
echo "Assembly dir:   ${ASSEMBLY_DIR}"
echo "k:              ${K}"
echo "Coverage:       ${COVERAGE}"
echo "Threads:        ${THREADS}"
echo "=========================================="

COVERAGE_FLAG=""
[ "${COVERAGE}" = "true" ] && COVERAGE_FLAG="--coverage"

metaMDBG gfa \
    --assembly-dir "${ASSEMBLY_DIR}" \
    --k "${K}" \
    ${COVERAGE_FLAG} \
    --threads "${THREADS}"

EXIT_CODE=$?

# --- Log footer -----------------------------------------------------------
GFA_FILE=$(ls "${ASSEMBLY_DIR}/"*"_k${K}.gfa" 2>/dev/null | head -1)
echo "=========================================="
echo "Job finished: $(date)"
echo "Exit code:    ${EXIT_CODE}"
if [ -n "${GFA_FILE}" ] && [ -f "${GFA_FILE}" ]; then
    GFA_SIZE=$(du -sh "${GFA_FILE}" | cut -f1)
    echo "GFA file:     ${GFA_FILE} (${GFA_SIZE})"
fi
echo "=========================================="

exit ${EXIT_CODE}
