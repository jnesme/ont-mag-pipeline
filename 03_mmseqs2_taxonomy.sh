#!/bin/bash
### General options
#BSUB -q hpcspecial
#BSUB -J mmseqs2_taxonomy
#BSUB -n 24
#BSUB -R "span[hosts=1] rusage[mem=5GB]"
#BSUB -M 5500MB
#BSUB -W 12:00
#BSUB -u josne@dtu.dk
#BSUB -B
#BSUB -N
#BSUB -o mmseqs2_taxonomy_%J.out
#BSUB -e mmseqs2_taxonomy_%J.err

#==========================================================================
# EDIT THESE BEFORE SUBMITTING
#==========================================================================
CONTIGS=""        # Host-filtered contigs (contigs_no_host.fasta.gz)
GTDB_DB=""        # GTDB MMseqs2 database — download with:
                  # mmseqs databases GTDB /path/to/db tmp --threads 24
                  # NOTE: separate from the GTDB-Tk database
OUTDIR=""         # Output directory
THREADS=24
#==========================================================================

# MMseqs2 uses ~100 GB RAM for GTDB — tell it to stay within node limits
MMSEQS_MEM="110G"

# --- Validate inputs ------------------------------------------------------
if [ -z "${CONTIGS}" ] || [ -z "${GTDB_DB}" ] || [ -z "${OUTDIR}" ]; then
    echo "ERROR: CONTIGS, GTDB_DB, and OUTDIR must all be set." >&2
    exit 1
fi
if [ ! -f "${CONTIGS}" ]; then
    echo "ERROR: Contigs not found: ${CONTIGS}" >&2
    exit 1
fi
if [ ! -f "${GTDB_DB}" ] && [ ! -f "${GTDB_DB}.dbtype" ]; then
    echo "ERROR: GTDB MMseqs2 database not found: ${GTDB_DB}" >&2
    echo "       Download with: mmseqs databases GTDB ${GTDB_DB} tmp --threads ${THREADS}" >&2
    exit 1
fi

# --- Environment ----------------------------------------------------------
source /work3/josne/miniconda3/etc/profile.d/conda.sh
conda activate /work3/josne/miniconda3/envs/genomad

# --- Log header -----------------------------------------------------------
echo "=========================================="
echo "MMseqs2 taxonomy — contig-level GTDB annotation"
echo "Job started:  $(date)"
echo "Job ID:       ${LSB_JOBID}"
echo "Host:         $(hostname) ($(nproc) CPUs, $(free -h | awk '/^Mem/{print $2}') RAM)"
echo "Contigs:      ${CONTIGS}"
echo "GTDB DB:      ${GTDB_DB}"
echo "Output dir:   ${OUTDIR}"
echo "Threads:      ${THREADS}"
echo "MMseqs2 mem:  ${MMSEQS_MEM}"
echo "=========================================="

mkdir -p "${OUTDIR}"
TMPDIR="${OUTDIR}/tmp"
mkdir -p "${TMPDIR}"

QUERY_DB="${OUTDIR}/contigs_db"
TAXA_DB="${OUTDIR}/taxonomy_result"
TAXA_TSV="${OUTDIR}/taxonomy.tsv"

# Step 1: Create MMseqs2 query database from contigs
echo "[1/3] Creating MMseqs2 query database..."
mmseqs createdb "${CONTIGS}" "${QUERY_DB}" --threads "${THREADS}"

EXIT_CODE=$?
[ ${EXIT_CODE} -ne 0 ] && echo "ERROR: mmseqs createdb failed" >&2 && exit ${EXIT_CODE}

# Step 2: Run taxonomy classification
# --search-type 2: translated search (nucleotide contigs vs GTDB amino acid DB)
# --lca-mode 3: approximate 2bLCA (recommended for metagenomics)
# --tax-lineage 1: include full lineage string in output
# -s 4: fast-sensitive preset
echo "[2/3] Running taxonomy classification against GTDB..."
mmseqs taxonomy \
    "${QUERY_DB}" \
    "${GTDB_DB}" \
    "${TAXA_DB}" \
    "${TMPDIR}" \
    --threads "${THREADS}" \
    --search-type 2 \
    --lca-mode 3 \
    --tax-lineage 1 \
    --split-memory-limit "${MMSEQS_MEM}" \
    -s 4 \
    -v 2

EXIT_CODE=$?
[ ${EXIT_CODE} -ne 0 ] && echo "ERROR: mmseqs taxonomy failed" >&2 && exit ${EXIT_CODE}

# Step 3: Export results to TSV
# Output columns: contig_name, taxid, rank, name, lineage
echo "[3/3] Exporting taxonomy TSV..."
mmseqs createtsv \
    "${QUERY_DB}" \
    "${TAXA_DB}" \
    "${TAXA_TSV}" \
    --threads "${THREADS}"

EXIT_CODE=$?
[ ${EXIT_CODE} -ne 0 ] && echo "ERROR: mmseqs createtsv failed" >&2 && exit ${EXIT_CODE}

# Clean up MMseqs2 tmp files (large)
rm -rf "${TMPDIR}"

# --- Log footer -----------------------------------------------------------
N_CLASSIFIED=$(awk '$2 != "0"' "${TAXA_TSV}" | wc -l)
N_TOTAL=$(wc -l < "${TAXA_TSV}")
echo "=========================================="
echo "Job finished:     $(date)"
echo "Exit code:        0"
echo "Total contigs:    ${N_TOTAL}"
echo "Classified:       ${N_CLASSIFIED}"
echo "Unclassified:     $(( N_TOTAL - N_CLASSIFIED ))"
echo "Taxonomy TSV:     ${TAXA_TSV}"
echo "  (pass to TaxVamb as taxonomy input)"
echo "=========================================="
