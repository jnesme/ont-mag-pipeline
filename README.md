# metaMDBG-lsf10 — ONT Metagenome-Assembled Genome Pipeline

LSF submission scripts for producing metagenome-assembled genomes (MAGs) from
Oxford Nanopore Technology (ONT) metagenomic reads on the DTU HPC `hpcspecial`
cluster.

---

## Context

**Sample:** Filtered planktonic microbiome of an *Isochrysis galbana* (haptophyte
microalga) culture. Algal cells were removed by filtration, so the community is
small and well-defined (~8 MAGs expected).

**Reads:** ONT R10.4+ simplex reads, ~30.6 Gbp, N50 ~10.4 kbp, avg quality Q18.5.

**Cluster:** `hpcspecial` queue — single dedicated node (`n-62-21-19`),
24 cores, ~251 GB RAM, 72 h max walltime.

---

## Pipeline Overview

```
[one-time setup]
00_download_gtdb_mmseqs2.sh          Download GTDB r232 as MMseqs2 database

[per-sample]
01_assembly.sh                       metaMDBG assembly (ONT reads → contigs)
    │
    ├── 02_gfa.sh                    Assembly graph export (visualization)
    │
    └── 02_filter_host.sh            Remove I. galbana host contigs
            │
            ├── 02_map_reads.sh      Map ONT reads back to clean contigs (BAM)
            │       │
            │       ├── 03_semibin2.sh          SemiBin2 binning
            │       │
            │       └── 03_mmseqs2_taxonomy.sh  Contig-level GTDB taxonomy
            │               │
            │               └── 04_taxvamb.sh   TaxVamb binning  [not yet written]
            │
            └── 04_genomad.sh        Plasmid / virus detection
            
[downstream — not yet written]
05_dastool.sh      Bin refinement (SemiBin2 + TaxVamb → non-redundant MAGs)
06_gtdbtk.sh       Taxonomic classification + phylogenetic placement
```

Steps `02_gfa.sh` and `02_filter_host.sh` can run in parallel immediately after
assembly. Steps `03_semibin2.sh` and `03_mmseqs2_taxonomy.sh` can run in parallel
after mapping and host filtering respectively.

---

## Prerequisites

### Conda environments

| Environment | Path | Used by |
|---|---|---|
| `metaMDBG` | `/work3/josne/miniconda3/envs/metaMDBG` | `01_assembly.sh`, `02_gfa.sh` |
| `anvio-9` | `/work3/josne/miniconda3/envs/anvio-9` | `02_filter_host.sh`, `02_map_reads.sh` |
| `semibin2` | `/work3/josne/miniconda3/envs/semibin2` | `03_semibin2.sh` |
| `genomad` | `/work3/josne/miniconda3/envs/genomad` | `03_mmseqs2_taxonomy.sh`, `04_genomad.sh` |
| `gtdbtk` | `/work3/josne/miniconda3/envs/gtdbtk` | `06_gtdbtk.sh` |

Note: `minimap2` must be installed in the `anvio-9` environment:
```bash
conda install -n anvio-9 -c bioconda minimap2
```

### Databases

| Database | Path | Used by |
|---|---|---|
| GTDB r232 (MMseqs2 format) | `/work3/josne/Databases/gtdb_mmseqs2_db` | `03_mmseqs2_taxonomy.sh` |
| geNomad DB | `/work3/josne/Databases/genomad_db` | `04_genomad.sh` |
| GTDB-Tk r232 | `/work3/josne/miniconda3/envs/gtdbtk/share/gtdbtk-2.7.1/db/` | `06_gtdbtk.sh` |
| *I. galbana* reference | `I.galbana_GCA_018136815.1_ASM1813681v1_genomic.fna.gz` (in repo) | `02_filter_host.sh` |

Download the GTDB MMseqs2 database (one-time, run on cluster):
```bash
bsub < 00_download_gtdb_mmseqs2.sh
```

Download the geNomad database:
```bash
conda activate /work3/josne/miniconda3/envs/genomad
genomad download-database /work3/josne/Databases/genomad_db
```

---

## Step-by-step

### 00 — Download GTDB MMseqs2 database (one-time)

Downloads and indexes GTDB r232 in MMseqs2 format to
`/work3/josne/Databases/gtdb_mmseqs2_db`. This database is reusable across all
future projects. Uses local `/tmp` scratch (752 GB) for intermediate files to
avoid NFS I/O during indexing.

---

### 01 — Assembly (`01_assembly.sh`)

**Tool:** metaMDBG 1.4  
**Resources:** 24 cores, 240 GB RAM, 72 h

Assembles ONT reads using a multi-k de Bruijn graph approach. metaMDBG was
chosen over other long-read assemblers (Flye, HiFiAsm) because it is
specifically designed and benchmarked for metagenome assembly from ONT R10
simplex reads.

Key parameters:
- `--min-read-quality 10` — filters reads below Q10; well above the dataset's
  avg Q18.5 so the threshold is conservative
- `--min-contig-length 1000` — standard minimum for downstream binning tools
- `--min-contig-coverage 2` — removes singleton assemblies likely to be errors

The job implements automatic checkpoint/resume: resubmitting the identical
command after a timeout resumes from the last completed step. Progress can be
followed live:
```bash
tail -f /path/to/outdir/metaMDBG.log
```

Output: `contigs.fasta.gz` with headers encoding length, coverage, and
circularity (e.g. `>ctg1 length=45231 coverage=12 circular=yes`).

---

### 02a — GFA export (`02_gfa.sh`)

**Tool:** metaMDBG gfa  
**Resources:** 24 cores, 96 GB RAM, 4 h  
**Runs in parallel with:** `02_filter_host.sh`

Exports the assembly graph in GFA format for visualisation in Bandage. Run
twice: first with `K=""` to discover available k values, then with a chosen K.

**Why not a minimap2 overlap graph?**  
metaMDBG is a de Bruijn graph assembler. The `metaMDBG gfa` export is the
correct graph representation — circular contigs appear as loops. A post-hoc
minimap2 all-vs-all overlap graph would break circular contigs because their
overlapping ends are trimmed during assembly.

`--coverage` is enabled by default: it recomputes per-unitig coverage from
internal assembly data and encodes it in the GFA. In Bandage, this allows
nodes to be coloured by depth, making it straightforward to visually identify
plasmids (elevated coverage from multi-copy elements) and chromosomal
sequences.

Higher k → simpler graph closer to final contigs. Use the highest available k
for visualisation.

---

### 02b — Host filtering (`02_filter_host.sh`)

**Tool:** minimap2 (asm10 preset) + Python  
**Resources:** 24 cores, 48 GB RAM, 4 h  
**Reference:** `I.galbana_GCA_018136815.1_ASM1813681v1_genomic.fna.gz`

*I. galbana* is a eukaryote with a ~60 Mb genome. metaMDBG assembles reads
regardless of origin, so the assembly contains both microbial contigs and
*I. galbana* genomic fragments. These must be removed before binning, which
assumes prokaryotic genomes.

Contigs are mapped to the *I. galbana* reference genome in PAF format (no BAM
needed — this is a classification step, not alignment storage). Contigs where
≥50% of the length maps at MAPQ ≥30 are classified as host-derived.

Outputs two files:
- `contigs_no_host.fasta.gz` — input for all downstream steps
- `host_contigs.fasta.gz` — retained for potential algal genome analysis

The 50% coverage threshold avoids false-positives from microbial contigs that
share short conserved regions with the algal genome.

---

### 02c — Read mapping (`02_map_reads.sh`)

**Tools:** minimap2 (`map-ont` preset) + samtools  
**Resources:** 24 cores, 120 GB RAM, 12 h  
**Environment:** `anvio-9`

Maps the original ONT reads back to the host-filtered contigs to generate
coverage depth profiles. Both SemiBin2 and TaxVamb require sorted, indexed BAM
files as input. Reads are piped directly from minimap2 into `samtools sort`
without writing an intermediate SAM file (~100 GB saved).

Outputs: `reads_vs_contigs.bam`, `reads_vs_contigs.bam.bai`,
`reads_vs_contigs.flagstat`.

**Why keep data on NFS rather than local scratch?**  
metaMDBG implements checkpoint/resume that requires its output directory to
persist between jobs. This reasoning extends to BAM files used by multiple
downstream steps. Local scratch is used only for transient I/O (MMseqs2 tmp).

---

### 03a — SemiBin2 binning (`03_semibin2.sh`)

**Tool:** SemiBin2  
**Resources:** 24 cores, 192 GB RAM, 24 h  
**Runs in parallel with:** `03_mmseqs2_taxonomy.sh`

SemiBin2 uses a variational autoencoder trained on k-mer composition and
coverage depth to cluster contigs into bins.

Key choices:
- `--self-supervised` — trains the model directly on the input data rather
  than using a pre-trained environment model. Pre-trained models exist for
  human gut, ocean, soil, etc., but none exist for microalgal culture
  microbiomes. Self-supervised training adapts to the actual data composition.
- `--sequencing-type long_read` — applies long-read specific scoring;
  essential for ONT data.

Generates `semibin2_contigs2bins.tsv` (scaffold-to-bin format) for DAStool.

---

### 03b — Contig taxonomy annotation (`03_mmseqs2_taxonomy.sh`)

**Tool:** MMseqs2 taxonomy  
**Resources:** 24 cores, 120 GB RAM, 12 h  
**Runs in parallel with:** `03_semibin2.sh`  
**Prerequisite:** `00_download_gtdb_mmseqs2.sh`

Assigns GTDB r232 taxonomy to each contig using translated search
(`--search-type 2`, nucleotide contigs vs GTDB protein database) and
approximate 2bLCA (`--lca-mode 3`). Required by TaxVamb.

MMseqs2 intermediate files are written to `/tmp/${LSB_JOBID}` (local disk,
752 GB) to avoid NFS I/O load. The final taxonomy TSV is written to NFS.

Note: `$TMPDIR` is not set by LSF on this cluster — scratch paths are
constructed from `$LSB_JOBID` explicitly.

---

### 04a — TaxVamb binning (`04_taxvamb.sh`) — *not yet written*

TaxVamb extends VAMB with contig-level taxonomic signals to improve binning.
Takes the BAM file from `02_map_reads.sh` and the taxonomy TSV from
`03_mmseqs2_taxonomy.sh`.

Together with SemiBin2, TaxVamb provides two independent bin sets for DAStool
to reconcile.

---

### 04b — Plasmid/virus detection (`04_genomad.sh`)

**Tool:** geNomad  
**Resources:** 24 cores, 192 GB RAM, 12 h

Classifies contigs as chromosomal, plasmid, or viral using a combination of
marker gene annotation and neural network classification. Runs on host-filtered
contigs.

**Why geNomad instead of PlasMAAG?**  
PlasMAAG was the original choice but is incompatible with this pipeline:
1. Requires paired-end short reads — this pipeline uses ONT long reads only
2. Requires SPAdes assembly graphs (GFA + `.paths`) — metaMDBG produces a
   different graph format and the parser is hard-coded for SPAdes

geNomad operates directly on assembled contigs with no read input, making it
fully compatible with any assembler.

**Why not bin plasmids with their host chromosome?**  
Standard binners (including SemiBin2 and TaxVamb) use coverage depth and
tetranucleotide frequency (TNF) for clustering. Both signals fail for plasmids:
- Multi-copy plasmids have coverage 5–50× higher than the chromosome
- Plasmids acquired by HGT often retain different TNF from the host

Plasmids are therefore treated as individual contigs throughout. Host-plasmid
association is a separate analysis problem outside the scope of this pipeline.

Generates `genomad_plasmid_contigs2bins.tsv` for DAStool, where each plasmid
contig is its own bin.

---

### 05 — Bin refinement (`05_dastool.sh`) — *not yet written*

DAStool scores bins from SemiBin2 and TaxVamb using single-copy marker genes
and produces a non-redundant, quality-filtered set of MAGs. geNomad plasmid
bins are passed as an additional bin set.

**Why DAStool instead of BASALT?**  
BASALT (Binning Across a Series of Assemblies Toolkit, Qiu et al. *Nat.
Commun.* 2024) was evaluated. It outperforms DAStool on CAMI benchmarks but
currently supports only PacBio HiFi long reads — ONT is not yet supported
(as of May 2026).

---

### 06 — GTDB-Tk classification (`06_gtdbtk.sh`) — *not yet written*

Taxonomic classification and phylogenetic placement of final MAGs against the
GTDB r232 reference tree.

---

## Cluster conventions

- All jobs target the `hpcspecial` queue (24 cores, ~251 GB RAM, 72 h max)
- Memory is requested per-core via `rusage[mem=XGB]`; total = X × 24
- Email notifications on start and end: `josne@dtu.dk`
- Logs: `<jobname>_<jobid>.out` / `.err` in the submission directory
- Local scratch: `/tmp/${LSB_JOBID}` (752 GB local disk); `$TMPDIR` is not set
  by LSF on this cluster
- Conda: activated via full path to avoid `PATH` dependency at job start
  ```bash
  source /work3/josne/miniconda3/etc/profile.d/conda.sh
  conda activate /work3/josne/miniconda3/envs/<name>
  ```

---

## References

- **metaMDBG:** Benoit et al., *Nat. Biotechnol.* (2023); *Nat. Commun.* (2026)
- **SemiBin2:** Pan et al., *Nat. Methods* (2023)
- **TaxVamb:** Nissen et al., *Nat. Biotechnol.* (2021) + TaxVamb extension
- **geNomad:** Camargo et al., *Nat. Biotechnol.* (2023)
- **DAStool:** Sieber et al., *Nat. Microbiol.* (2018)
- **GTDB-Tk:** Chaumeil et al., *Bioinformatics* (2022)
- **BASALT** (evaluated, not used): Qiu et al., *Nat. Commun.* (2024) — doi:10.1038/s41467-024-46539-7
