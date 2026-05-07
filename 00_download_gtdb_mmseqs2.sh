#!/bin/bash
### General options
#BSUB -q hpcspecial
#BSUB -J gtdb_mmseqs2_download
#BSUB -n 24
#BSUB -R "span[hosts=1] rusage[mem=4GB]"
#BSUB -M 4500MB
#BSUB -W 12:00
#BSUB -u josne@dtu.dk
#BSUB -B
#BSUB -N
#BSUB -o gtdb_mmseqs2_download_%J.out
#BSUB -e gtdb_mmseqs2_download_%J.err

#==========================================================================
# EDIT THESE BEFORE SUBMITTING
#==========================================================================
OUTDB="/work3/josne/Databases/gtdb_mmseqs2_db"  # Output database path (NFS, persists)
THREADS=24
#==========================================================================

# --- Environment ----------------------------------------------------------
source /work3/josne/miniconda3/etc/profile.d/conda.sh
conda activate /work3/josne/miniconda3/envs/genomad

# --- Log header -----------------------------------------------------------
echo "=========================================="
echo "MMseqs2 GTDB database download"
echo "Job started:  $(date)"
echo "Job ID:       ${LSB_JOBID}"
echo "Host:         $(hostname) ($(nproc) CPUs, $(free -h | awk '/^Mem/{print $2}') RAM)"
echo "Output DB:    ${OUTDB}"
echo "Tmp dir:      ${TMPDIR} (local scratch)"
echo "Threads:      ${THREADS}"
echo "=========================================="

mkdir -p "$(dirname "${OUTDB}")"

# Use LSF-provided local scratch (auto-cleaned after job)
# LSF sets $TMPDIR but does not guarantee the directory exists
mkdir -p "${TMPDIR}"
mmseqs databases GTDB "${OUTDB}" "${TMPDIR}" --threads "${THREADS}"

EXIT_CODE=$?

# --- Log footer -----------------------------------------------------------
echo "=========================================="
echo "Job finished: $(date)"
echo "Exit code:    ${EXIT_CODE}"
if [ ${EXIT_CODE} -eq 0 ]; then
    echo "Database:     ${OUTDB}"
    echo "Version:      $(cat "${OUTDB}.version" 2>/dev/null || echo 'unknown')"
    ls -lh "${OUTDB}"* 2>/dev/null
fi
echo "=========================================="

exit ${EXIT_CODE}
