#!/bin/bash
### General options
#BSUB -q hpcspecial
#BSUB -J genomad
#BSUB -n 24
#BSUB -R "span[hosts=1] rusage[mem=8GB]"
#BSUB -M 8500MB
#BSUB -W 12:00
#BSUB -u josne@dtu.dk
#BSUB -B
#BSUB -N
#BSUB -o genomad_%J.out
#BSUB -e genomad_%J.err

#==========================================================================
# EDIT THESE BEFORE SUBMITTING
#==========================================================================
CONTIGS="/work3/josne/Projects/DoraMultiOmics/metaMDBG_rescued.all.fastq/contigs.fasta.gz"        # Filtered contigs from step 02_filter_host.sh
                  # (contigs_no_host.fasta.gz)
OUTDIR="/work3/josne/Projects/DoraMultiOmics/geNomad_out"         # Output directory for geNomad results
GENOMAD_DB="/work3/josne/Databases/genomad_db"     # Path to geNomad database directory
                  # Download with: genomad download-database /path/to/db/
THREADS=24
#==========================================================================

# --- Validate inputs ------------------------------------------------------
if [ -z "${CONTIGS}" ] || [ -z "${OUTDIR}" ] || [ -z "${GENOMAD_DB}" ]; then
    echo "ERROR: CONTIGS, OUTDIR, and GENOMAD_DB must all be set." >&2
    exit 1
fi
if [ ! -f "${CONTIGS}" ]; then
    echo "ERROR: Contigs file not found: ${CONTIGS}" >&2
    exit 1
fi
if [ ! -d "${GENOMAD_DB}" ]; then
    echo "ERROR: geNomad database not found: ${GENOMAD_DB}" >&2
    echo "       Download with: genomad download-database /path/to/db/" >&2
    exit 1
fi

# --- Environment ----------------------------------------------------------
source /work3/josne/miniconda3/etc/profile.d/conda.sh
conda activate /work3/josne/miniconda3/envs/genomad

# Derive output prefix from input filename (geNomad names outputs after input)
BASENAME=$(basename "${CONTIGS}")
PREFIX="${BASENAME%.fasta.gz}"
PREFIX="${PREFIX%.fasta}"
PREFIX="${PREFIX%.fa.gz}"
PREFIX="${PREFIX%.fa}"

# --- Log header -----------------------------------------------------------
echo "=========================================="
echo "geNomad — plasmid/virus detection"
echo "Job started:   $(date)"
echo "Job ID:        ${LSB_JOBID}"
echo "Host:          $(hostname) ($(nproc) CPUs, $(free -h | awk '/^Mem/{print $2}') RAM)"
echo "Contigs:       ${CONTIGS}"
echo "Output dir:    ${OUTDIR}"
echo "Database:      ${GENOMAD_DB}"
echo "Output prefix: ${PREFIX}"
echo "Threads:       ${THREADS}"
echo "=========================================="

mkdir -p "${OUTDIR}"

genomad end-to-end \
    --threads "${THREADS}" \
    --cleanup \
    "${CONTIGS}" \
    "${OUTDIR}" \
    "${GENOMAD_DB}"

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "ERROR: geNomad failed (exit ${EXIT_CODE})" >&2
    exit ${EXIT_CODE}
fi

# --- Generate scaffold-to-bin TSV for DAStool (plasmids only) -------------
# Each plasmid contig is treated as its own bin (plasmids are distinct elements)
PLASMID_SUMMARY="${OUTDIR}/${PREFIX}_summary/${PREFIX}_plasmid_summary.tsv"
SCAFFOLD2BIN="${OUTDIR}/genomad_plasmid_contigs2bins.tsv"

if [ -f "${PLASMID_SUMMARY}" ]; then
    # Column 1 of the summary TSV is the contig name (skip header)
    awk 'NR>1 {print $1"\t"$1}' "${PLASMID_SUMMARY}" > "${SCAFFOLD2BIN}"
    N_PLASMIDS=$(wc -l < "${SCAFFOLD2BIN}")
else
    echo "WARNING: plasmid summary not found at ${PLASMID_SUMMARY}" >&2
    N_PLASMIDS=0
fi

# --- Log footer -----------------------------------------------------------
VIRUS_SUMMARY="${OUTDIR}/${PREFIX}_summary/${PREFIX}_virus_summary.tsv"
N_VIRUSES=0
[ -f "${VIRUS_SUMMARY}" ] && N_VIRUSES=$(( $(wc -l < "${VIRUS_SUMMARY}") - 1 ))

echo "=========================================="
echo "Job finished:    $(date)"
echo "Exit code:       0"
echo "Plasmid contigs: ${N_PLASMIDS}"
echo "Virus contigs:   ${N_VIRUSES}"
echo "Scaffold2bin:    ${SCAFFOLD2BIN}"
echo "  (pass to DAStool alongside SemiBin2 scaffold2bin)"
echo "=========================================="
