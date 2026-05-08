#!/bin/bash
### General options
#BSUB -q hpcspecial
#BSUB -J filter_host
#BSUB -n 24
#BSUB -R "span[hosts=1] rusage[mem=2GB]"
#BSUB -M 2500MB
#BSUB -W 4:00
#BSUB -u josne@dtu.dk
#BSUB -B
#BSUB -N
#BSUB -o filter_host_%J.out
#BSUB -e filter_host_%J.err

#==========================================================================
# EDIT THESE BEFORE SUBMITTING
#==========================================================================
ASSEMBLY_DIR="/work3/josne/Projects/DoraMultiOmics/metaMDBG_rescued.all.fastq"    # metaMDBG output dir from step 1 (contains contigs.fasta.gz)
HOST_REF="/work3/josne/github/metaMDBG-lsf10/I.galbana_GCA_018136815.1_ASM1813681v1_genomic.fna.gz"
OUTDIR="/work3/josne/Projects/DoraMultiOmics/host_filtering"          # Output directory for filtered contig files
MIN_COV_FRAC=0.50  # Min fraction of contig length mapping to host (0.0-1.0)
MIN_MAPQ=30        # Min mapping quality to call a contig host-derived
THREADS=24
#==========================================================================

CONTIGS="${ASSEMBLY_DIR}/contigs.fasta.gz"

# --- Validate inputs ------------------------------------------------------
if [ -z "${ASSEMBLY_DIR}" ] || [ -z "${HOST_REF}" ] || [ -z "${OUTDIR}" ]; then
    echo "ERROR: ASSEMBLY_DIR, HOST_REF, and OUTDIR must all be set." >&2
    exit 1
fi
if [ ! -f "${CONTIGS}" ]; then
    echo "ERROR: Contigs not found: ${CONTIGS}" >&2
    exit 1
fi
if [ ! -f "${HOST_REF}" ]; then
    echo "ERROR: Host reference not found: ${HOST_REF}" >&2
    exit 1
fi

# --- Environment ----------------------------------------------------------
source /work3/josne/miniconda3/etc/profile.d/conda.sh
conda activate /work3/josne/miniconda3/envs/anvio-9

# --- Log header -----------------------------------------------------------
echo "=========================================="
echo "Host contig filtering (I. galbana)"
echo "Job started:    $(date)"
echo "Job ID:         ${LSB_JOBID}"
echo "Host:           $(hostname) ($(nproc) CPUs, $(free -h | awk '/^Mem/{print $2}') RAM)"
echo "Contigs:        ${CONTIGS}"
echo "Host reference: ${HOST_REF}"
echo "Output dir:     ${OUTDIR}"
echo "Min cov frac:   ${MIN_COV_FRAC}"
echo "Min MAPQ:       ${MIN_MAPQ}"
echo "Threads:        ${THREADS}"
echo "=========================================="

mkdir -p "${OUTDIR}"

PAF="${OUTDIR}/contigs_vs_host.paf"
HOST_LIST="${OUTDIR}/host_contig_names.txt"
HOST_CONTIGS="${OUTDIR}/host_contigs.fasta.gz"
CLEAN_CONTIGS="${OUTDIR}/contigs_no_host.fasta.gz"

# Step 1: Map contigs against host reference (PAF output — no BAM needed)
echo "Mapping contigs to host reference..."
minimap2 -cx asm10 -t "${THREADS}" "${HOST_REF}" "${CONTIGS}" > "${PAF}"

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "ERROR: minimap2 failed (exit ${EXIT_CODE})" >&2
    exit ${EXIT_CODE}
fi

# Step 2: Filter PAF — keep contigs where >= MIN_COV_FRAC of length maps
# PAF columns: 1=qname, 2=qlen, 3=qstart, 4=qend, 12=mapq
echo "Identifying host-derived contigs..."
awk -v cov="${MIN_COV_FRAC}" -v mapq="${MIN_MAPQ}" \
    '$12 >= mapq && ($4-$3)/$2 >= cov {print $1}' "${PAF}" \
    | sort -u > "${HOST_LIST}"

N_HOST=$(wc -l < "${HOST_LIST}")
echo "Host-derived contigs identified: ${N_HOST}"

# Step 3: Split contigs.fasta.gz into host and non-host
echo "Splitting contig FASTA..."
python3 - "${CONTIGS}" "${HOST_LIST}" "${HOST_CONTIGS}" "${CLEAN_CONTIGS}" << 'EOF'
import gzip, sys

contigs_file, host_list_file, host_out, clean_out = sys.argv[1:]

with open(host_list_file) as f:
    host_set = set(line.strip() for line in f)

write_to = None
with gzip.open(contigs_file, 'rt') as fin, \
     gzip.open(host_out, 'wt') as fhost, \
     gzip.open(clean_out, 'wt') as fclean:
    for line in fin:
        if line.startswith('>'):
            name = line[1:].split()[0]
            write_to = fhost if name in host_set else fclean
        write_to.write(line)
EOF

EXIT_CODE=$?
if [ ${EXIT_CODE} -ne 0 ]; then
    echo "ERROR: FASTA splitting failed (exit ${EXIT_CODE})" >&2
    exit ${EXIT_CODE}
fi

# --- Log footer -----------------------------------------------------------
N_TOTAL=$(zgrep -c "^>" "${CONTIGS}")
N_CLEAN=$(zgrep -c "^>" "${CLEAN_CONTIGS}")
echo "=========================================="
echo "Job finished:       $(date)"
echo "Exit code:          0"
echo "Total contigs:      ${N_TOTAL}"
echo "Host contigs:       ${N_HOST}"
echo "Non-host contigs:   ${N_CLEAN}"
echo ""
echo "Pass to downstream steps:"
echo "  contigs_no_host:  ${CLEAN_CONTIGS}"
echo "  host contigs:     ${HOST_CONTIGS}"
echo "  (update ASSEMBLY_DIR or CONTIGS in 02_map_reads.sh and 03_semibin2.sh)"
echo "=========================================="
