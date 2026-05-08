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
00_qc.sh                             Adapter trimming + read QC (→ qc_reads.fastq.gz)
    │
    └── 01_assembly.sh               metaMDBG assembly (filtered reads → contigs)
            │
            ├── 02_gfa.sh            Assembly graph export (visualization)
            │
            └── 02_filter_host.sh    Remove I. galbana host contigs
                    │
                    ├── 04_genomad.sh    Plasmid / virus detection (contig-level)
                    │
                    └── 02_map_reads.sh  Map ONT reads back to clean contigs (BAM)
                            │
                            └── 03_semibin2.sh   SemiBin2 binning
                                    │
                                    └── 05_checkm2.sh   Bin quality assessment
                                            │
                                            └── 06_gtdbtk.sh   Taxonomic classification
```

Steps `02_gfa.sh` and `02_filter_host.sh` can run in parallel immediately after
assembly. `04_genomad.sh` and `02_map_reads.sh` can run in parallel after host
filtering.

---

## Prerequisites

### Conda environments

| Environment | Path | Used by |
|---|---|---|
| `nanoQC` | `/work3/josne/miniconda3/envs/nanoQC` | `00_qc.sh` |
| `metaMDBG` | `/work3/josne/miniconda3/envs/metaMDBG` | `01_assembly.sh`, `02_gfa.sh` |
| `anvio-9` | `/work3/josne/miniconda3/envs/anvio-9` | `02_filter_host.sh`, `02_map_reads.sh` |
| `semibin2` | `/work3/josne/miniconda3/envs/semibin2` | `03_semibin2.sh` |
| `genomad` | `/work3/josne/miniconda3/envs/genomad` | `04_genomad.sh` |
| `checkm2` | `/work3/josne/miniconda3/envs/checkm2` | `05_checkm2.sh` |
| `gtdbtk` | `/work3/josne/miniconda3/envs/gtdbtk` | `06_gtdbtk.sh` |

Note: `minimap2` must be installed in the `anvio-9` environment:
```bash
conda install -n anvio-9 -c bioconda minimap2
```

### Databases

| Database | Path | Used by |
|---|---|---|
| geNomad DB | `/work3/josne/Databases/genomad_db` | `04_genomad.sh` |
| CheckM2 DB | `/work3/josne/Databases/checkm2_db` | `05_checkm2.sh` |
| GTDB-Tk r232 | `/work3/josne/miniconda3/envs/gtdbtk/share/gtdbtk-2.7.1/db/` | `06_gtdbtk.sh` |
| *I. galbana* reference | `I.galbana_GCA_018136815.1_ASM1813681v1_genomic.fna.gz` (in repo) | `02_filter_host.sh` |

Download the CheckM2 database (~3 GB, one-time):
```bash
conda activate /work3/josne/miniconda3/envs/checkm2
checkm2 database --download --path /work3/josne/Databases/checkm2_db
```

Download the geNomad database:
```bash
conda activate /work3/josne/miniconda3/envs/genomad
genomad download-database /work3/josne/Databases/genomad_db
```

---

## Step-by-step

### 00 — Read QC (`00_qc.sh`)

**Tools:** Porechop_ABI + Chopper + NanoStat + NanoPlot
**Resources:** 24 cores, 120 GB RAM, 12 h
**Environment:** `nanoQC`

Performs adapter trimming and quality/length filtering on raw ONT reads before
assembly, and generates QC reports before and after filtering.

Steps:
1. **NanoStat + NanoPlot** on raw reads — baseline QC report and HTML visualisation
2. **Porechop_ABI** — adapter trimming; uses ab initio detection so adapter
   sequences need not be specified. The trimmed intermediate is written to local
   scratch (`/tmp/${LSB_JOBID}`) and deleted after filtering.
3. **Chopper** — streaming quality and length filter (`--quality 8 --minlength 500`)
4. **NanoStat + NanoPlot** on filtered reads — post-QC comparison

Default thresholds (`MIN_QUALITY=8`, `MIN_LENGTH=500`) are intentionally lenient:
metaMDBG applies its own `--min-read-quality 10` filter internally, so the QC
step removes only clearly low-quality reads and very short fragments that carry
no assembly information.

Output `qc_reads.fastq.gz` replaces the raw reads as input to `01_assembly.sh`.
Update the `READS` variable in `01_assembly.sh` accordingly before submitting.

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

### 03b — Contig taxonomy annotation (`03_kaiju_taxonomy.sh`)

**Tool:** Kaiju (protein-level classification, MEM algorithm)  
**Resources:** 24 cores, 72 GB RAM, 6 h  
### 04 — Plasmid/virus detection (`04_genomad.sh`)

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

Plasmid and viral contigs are reported independently — they are not merged into
chromosomal bins. Results can be cross-referenced with SemiBin2 bins to flag
any bin contaminated by plasmid sequence.

---

### 05 — Bin quality assessment (`05_checkm2.sh`)

**Tool:** CheckM2  
**Resources:** 24 cores, 72 GB RAM, 4 h  
**Environment:** `checkm2`

Assesses completeness and contamination of each SemiBin2 bin using DIAMOND
protein search against a reference database followed by a machine learning
model. Replaces CheckM1 (which used hmmer) — CheckM2 is substantially faster
and more accurate, especially for novel lineages.

Bins meeting standard thresholds (MIMAG):
- **High quality (HQ):** completeness ≥ 90%, contamination ≤ 5%
- **Medium quality (MQ):** completeness ≥ 50%, contamination ≤ 10%

The quality report (`quality_report.tsv`) feeds directly into GTDB-Tk — only
HQ and MQ bins warrant taxonomic placement.

Database download (~3 GB, one-time):
```bash
conda activate /work3/josne/miniconda3/envs/checkm2
checkm2 database --download --path /work3/josne/Databases/checkm2_db
```

---

### 06 — GTDB-Tk classification (`06_gtdbtk.sh`)

**Tool:** GTDB-Tk 2.7.1  
**Resources:** 24 cores, 384 GB RAM (milan queue), 12 h  
**Environment:** `gtdbtk`

Taxonomic classification and phylogenetic placement of the refined MAGs against
the GTDB r232 reference tree. Runs `classify_wf`, which:
1. Identifies single-copy marker genes with prodigal + hmmer
2. Aligns markers to the bac120 / ar53 reference MSA
3. Places genomes into the reference tree with pplacer

**Queue:** `milan` is required — pplacer loads the full bacterial reference tree
(~165 GB) into RAM, which leaves insufficient headroom on `hpcspecial` (251 GB).
milan (1 TB RAM) handles this comfortably with the 384 GB request (16 GB × 24 cores).

**pplacer parallelism:** `--pplacer_cpus` spawns independent pplacer processes,
each loading the full tree (~165 GB). For ~8 MAGs, `PPLACER_CPUS=1` is fast and
safe. Increase only if running many MAGs and RAM allows (each additional CPU adds
~165 GB peak usage for bacteria).

**Database:** Set via `GTDBTK_DATA_PATH` environment variable before running.
The tarball must be extracted before use:
```bash
cd /work3/josne/miniconda3/envs/gtdbtk/share/gtdbtk-2.7.1/db
tar -I 'pigz -p 4' -xf gtdbtk_r232_data.tar.gz
```

Outputs: `classify/gtdbtk.bac120.summary.tsv` and
`classify/gtdbtk.ar53.summary.tsv` — full lineage strings, RED values, and
the nearest reference genome for each MAG.

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

- **NanoPack2** (NanoStat, NanoPlot, Chopper): De Coster & Rademakers, *Bioinformatics* (2023)
- **Porechop_ABI**: Bonenfant et al., *Bioinformatics Advances* (2023)
- **metaMDBG:** Benoit et al., *Nat. Biotechnol.* (2023); *Nat. Commun.* (2026)
- **SemiBin2:** Pan et al., *Nat. Methods* (2023)
- **geNomad:** Camargo et al., *Nat. Biotechnol.* (2023)
- **CheckM2:** Chklovski et al., *Nat. Methods* (2023)
- **GTDB-Tk:** Chaumeil et al., *Bioinformatics* (2022)
- **TaxVamb** (evaluated, not used): dependency on large GTDB database (400+ GB) not feasible on this cluster
- **DAStool** (evaluated, not used): geNomad produces contig-level classifications, not chromosomal bins — plasmid contigs carry no bacterial marker genes and are discarded by DAStool's scoring; DAStool only adds value with two independent chromosomal binners; Sieber et al., *Nat. Microbiol.* (2018)
- **BASALT** (evaluated, not used): PacBio HiFi only, no ONT support; Qiu et al., *Nat. Commun.* (2024) — doi:10.1038/s41467-024-46539-7
