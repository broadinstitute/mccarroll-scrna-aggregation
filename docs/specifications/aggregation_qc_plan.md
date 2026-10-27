# Plan: optional aggregation QC step

Status: **the Python tool and the prototype-script step are done and validated (Part 5, steps 1-7); the Nextflow process (step 8) is not started.** Follow the process in `TODO.md` for the
Nextflow part (clarification questions, data contract, severity-ranked candidate tests, then
stop for the user's selection).

## Status and next step

**Done**
- `aggregation_qc` is in the Drop-seq repo (`transcriptome_java/public/src/python`, package `dropseq.aggregation.plots`, merged in
  PR #593) and in the public image `quay.io/broadinstitute/drop-seq_python:current` (digest
  `sha256:05b95c05121f7f91ea5dd0d5cb570c90af4e240e9d5ffe1f852f67a7b87e973c`). `locate_scRNA_artifacts` in that image records `donor_file`.
- The CLI is as in Part 3, with one change from the first design: the tool takes the donor files themselves (`--donor-file FILE [FILE ...]`, optional, local
  or `gs://`, compared by content) and knows nothing about artifact YAMLs. The caller extracts `donor_file` from each library's artifact YAML and passes the files
  only if every library has one.
- `docs/specifications/scrna-aggregation_prototype.sh` has the optional step 10 (`--run-qc`, `--qc-conditions-file`, `--qc-condition-column`, `--qc-core-cell-types`);
  `SPEC_SUMMARY.md` and `../testing.md` describe it. It extracts `donor_file` with `sed` from `artifacts/<uei>.yaml` and copies the donor, conditions and core
  cell type files into `TMP_DIR/qc` (the container only mounts `OUT_DIR`, `TMP_DIR` and the manifest directory).
- Validated on the live baseline (SMRI_V11, one library, 238 cells): `--image-tag current --run-qc` exits 0 and writes `donor_qc.txt` and the 8 PDFs
  (`library_metrics` 12 pages, `filtered_library_metrics` 2, `donor_summary` 11, `donor_nuclei_counts` 4, `cell_type_counts`, `cell_type_median_UMIs` and
  `cell_type_proportions` 4 each, `donor_cell_type_distributions` 2). The other baseline files are byte-identical to the baseline made without QC, apart from the new
  `donor_file` line in `artifacts/SMRI_V11_rxn1.yaml`. The same run with a locally built `jn_test` image gave identical files. The tool was also compared with the legacy R
  plots on the Zamboni SMRI_V11 aggregation (`donor_qc` identical, pages equivalent apart from the intended changes).
- Unit tests: `cd transcriptome_java/public/src/python; uv run pytest tests/aggregation` (`test_qc_tables.py`, `test_aggregation_qc.py`, and the `donor_file` cases of `test_locate_scRNA_artifacts.py`).

**Behaviour to know about (as implemented)**
- Cells without a cell type are left out of every cell type page, so proportions are fractions of the labelled nuclei of the group; `donor_qc.txt` still uses all cells with a donor.
- A donor x cell type combination with no nuclei has 0 nuclei and 0 fraction but an NA median (not 0). Expected donors with no cells are in `donor_qc.txt` (`num_nuclei` 0, NA values).
- Donor files can have Windows (CRLF) line endings (the SMRI_V11 one does); the reader strips them.
- `--library-metrics` may name a library that has no cells in the cell metadata; with `--conditions-file` such a library needs a condition too, with `--condition-column` it is labelled `unknown`.
- Outputs are flat in `--output-dir` with the legacy names. A skipped output exits 0 and is logged. Value labels follow R's formatting (4 significant digits, no trailing zeros).

**Next: step 8, the Nextflow process** (Part 4), in this order:
1. The `LOCATE_SCRNA_ARTIFACTS` module tests: with the new image `main.nf.test` "Should emit the expected artifact paths ..." fails because the expected
   `fixtures/expected/LIB_A.yaml` and `LIB_B.yaml` lack `donor_file` (the live `gcs.nf.test` passes against the new baseline). Give the fixture village `properties.yaml` a
   `donorFile` and the expected YAMLs the `donor_file` line (see "Dependency on the artifact YAML").
2. Check that `lib/LibraryResolver.groovy` does not assume a fixed field list, then write the Groovy that collects each library's `donor_file` (none if any is NA or missing).
3. The `AGGREGATION_QC` module, params, pre-flight checks, publishing, tests and docs of Part 4, following `TODO.md`.

## Context

A co-worker's `aggregation_qc.sh` (plus 3 R scripts) is run by hand after a Zamboni
`LaunchScRnaAggregation` run. It writes a donor QC table and 7 PDFs of library, donor
and cell type QC into the aggregation directory. The aggregation is being re-implemented
as a Nextflow pipeline (`/Users/nemesh/mccarroll-scrna-aggregation`), whose outputs differ
in column names and data sources: MapMyCells (MMC) instead of scPred, snake_case columns,
and so on. We want to keep the *intent* of this QC and re-design it as a Python module,
`dropseq.aggregation.plots`, that the pipeline runs as an **optional last step**, in one
process.

This document covers the legacy analysis (Part 1), the decisions (Part 2), the design of the
Python tool `aggregation_qc` in the Drop-seq repo (`transcriptome_java/public/src/python`,
Part 3) and the Nextflow process that calls it (Part 4). The order of work is in Part 5.

Legacy code: `/broad/bican_um1_mccarroll/RNAseq/data/analysis/aggregated_data/scripts/`
Legacy examples (under `.../aggregated_data/single_village/`):
- `2025-12-09_v148_10X-GEMX-3P_SN/unfiltered`: no cell types, no conditions.
  Command line: `aggregation_qc.sh --directory <that dir> --donor-file /broad/bican_um1_mccarroll/manifests/Donor_Files_2025/2025-12-09_v148_ArbC_SN.txt`
- `2026-05-26_v138_10X-GEMX-3P_ic_cryo-SOX6/unfiltered`: scPred cell types and 4 conditions
  (conditions file: `.../aggregated_data/conditions/2026-05-26_v138_10X-GEMX-3P_ic_cryo-SOX6.conditions.txt`).
New-pipeline example output: `/Users/nemesh/mccarroll-scrna-aggregation/tests/live_data/baseline`
(SMRI_V11, 1 library, 238 cells, HMBA_Human_WB_v0.5 neighborhood).

## Starting a session

- **Where the Python code is:** `/Users/nemesh/dropseqrna/transcriptome_java/public`, a git
  submodule (repo `broadinstitute/Drop-seq`, branch `master`), directory `src/python`
  (hatchling, `src` layout), package `dropseq.aggregation.plots`. Further Python changes need
  a feature branch and a PR there; a changed image needs a new public build (or a local build
  with the tag `jn_test`, see `../testing.md`). The outer `dropseqrna` repo's submodule pointer
  is not part of this work.
- **Tests:** `cd /Users/nemesh/dropseqrna/transcriptome_java/public/src/python; uv run pytest tests/aggregation`
  (or `uv run python -m unittest discover -s tests/aggregation -t .`).
- **Rules:** Python only (no R), snake_case column names, edit only inside
  `public/src/python`. Commit only when asked.
- **Page-by-page spec:** Part 1 summarises the legacy code, but the R files are the reference
  for page order, subtitles and labels: `plot_library_metrics.R`,
  `generate_donor_qc_table_patched.R` and `plot_donor_celltype_qc_patched.R` in the legacy
  scripts directory above. The legacy PDFs next to the example runs can be rendered with
  `pdftoppm` to see what the pages look like.
- **New pipeline inputs** (checked against the baseline):
  - `cell_metadata.txt` (the pipeline's own files keep the lower-case `cell_barcode`; only the
    h5ad files have `CELL_BARCODE`, and this tool does not use the barcode): `PREFIX`
    (library), `donor`, `num_retained_transcripts`, and the cell type column named by the
    pipeline
    (`<model>_<level>_name`, for example `HMBA_Human_WB_v0.5_neighborhood_name`). Read donor
    and cell type columns as strings; donor IDs can look numeric.
  - `library_metrics.txt`: library column `library`; the metrics of the library pages exist
    under these names: `total_reads_M`, `pct_hq_mapped_reads`, `pct_chimeric_UMIs`,
    `n_STAMPs`, `median_cell_UMIs_cbrb`, `pct_confident_doublets`, `assignable_singlets`,
    `reads_per_umi_donor`, `totalUMIs` (the legacy page plots it in millions, rounded to 2
    decimals), `donor_equitability`, `scDblFinder_pct_doublets`.
  - Donor file: headerless, one donor per line, and the last line may have no trailing
    newline; ignore blank lines.
- **`gs://` access:** unit tests use local files only. `gsutil`/`gcloud` copies are unreliable
  on the Mac; use the Python client (`dropseq.util.storage.default_store`) for the live
  baseline donor file.

---

## Part 1: what the legacy code does

### Driver: `aggregation_qc.sh`
Arguments:
- `--directory`: the aggregation directory.
- `--donor-file`: required; a headerless list of expected donors, one per line.
- `--conditions-file`: optional; a TSV with `PREFIX<TAB>CONDITION` columns, mapping each library to its own condition.
- `--cell-type-label`: defaults to `predClass`.

The script finds exactly one `*.donor_cell_type.txt` and one `*.library_metrics.txt` in the
directory, takes the aggregation name from the first, and runs three R steps. Outputs go
into the aggregation directory. `aggregation_qc_old.sh` and `aggregation_qc_olivia.sh` differ
only trivially: the old one finds the cell metadata by glob.

### Step 1: `plot_library_metrics.R` -> `<agg>.library_metrics.pdf`
The input is the per-library metrics table (one row per library), with the conditions joined on
library. Each page shows one metric in two panels:
- Left: a bar per library with value labels and a dashed median line.
- Right: a box plot with points, by CONDITION. With no conditions there is a single box
  labelled "same conditions".

Metrics:
- Always: total reads (M), % HQ uniquely mapped (y axis 0-100), % chimeric UMIs, % polyA
  trimmed, % TSO trimmed, # selected nuclei (`n_STAMPs`), median UMIs/nucleus post-CBRB.
- If dropulation ran: % confident donor doublets, # assignable singlets, reads/UMI in
  singlets, total UMIs (M) in singlets. The check is `>1` non-NA library, which looks like it
  was meant to be `>0`.
- If scPred ran: # post-QC nuclei, median UMIs per post-QC nucleus.

**Intent:** check library-level sequencing, cell selection and demultiplexing health, and
whether any library or condition is an outlier.

### Step 2: `generate_donor_qc_table*.R` -> `<agg>.donor_qc.txt`
Built from the aggregated cell metadata, one row per donor: numNuclei, fractionNuclei,
totalUMIsM, medianUMIsPerNucleus (all from NUM_TRANSCRIPTS).

If the cell type column exists and has no NA values, it adds medianUMIsPerPrimaryNeuron.
"Primary neuron" means any cell type in a hard-coded list: `glutamatergic, SPN,
Upper.rhombic.lip`. These are the dominant neuron classes of cortex, striatum and cerebellum
in the scPred taxonomy.

Problems:
- Bug: the driver never passes `--cell-type-label` to this step, so it always uses `predClass`.
- The original breaks when more than one primary type is present (it compares with `==`
  against a vector). The `_patched` versions were made with Claude Code on Oct 14 (see the
  `.claude/` folder next to them). They use `%in%` for the pooled column and add one
  `medianUMIsPerPrimaryNeuron_<type>` column per type. The patch is a bug fix, not a design
  change.

**Intent:** a per-donor table of yield and RNA quality. The median UMIs of a region's main
neuron is a sensitive per-donor RNA-quality signal, because a donor's overall median also
depends on its cell-type mix.

### Step 3: `plot_donor_celltype_qc*.R` -> up to 6 PDFs
Preprocessing:
- Joins the conditions to the cell metadata by PREFIX.
- Full-joins donor_qc with the expected donor list. Donors in the data but not on the list are
  `UNEXPECTED` (red labels); expected donors with no cells get 0 nuclei.
- Donor colours come from a fixed 28-colour palette assigned to the sorted donors.
- Cell type pages are drawn only if donor_cell_type has more than 1 row and the label column
  exists. Every donor x cell type pair is filled in, with 0 where absent.

PDFs. Each page is one figure; pages marked [cond] are drawn only when conditions are given.
1. `filtered_library_metrics.pdf`: # nuclei and median UMIs/nucleus per library **after
   aggregation filtering**, from the cell metadata. Each page is a bar per library plus a box
   by condition, or one "All libraries" box.
2. `donor_summary.pdf`: sorted bars per donor (dashed median, red = unexpected) for the
   number of nuclei, % nuclei, total UMIs (M), median UMIs/nucleus, and median UMIs per
   primary neuron (one page per type). Then the cell type pages: stacked % per donor (labels for
   values >3%, faceted EXPECTED/UNEXPECTED), and for each of counts, % and median UMIs a box
   page (x = cell type, points = donors) and a faceted-bar page (one panel per cell type,
   donors sorted within each panel, median line per panel).
3. `donor_nuclei_counts.pdf`: # nuclei per donor; [cond] stacked by condition; per-donor box
   over libraries; [cond] per-donor box dodged by condition; per-library box over donors
   (faceted by condition); donor composition per library (100% stacked).
4. `cell_type_counts.pdf`: total per cell type; [cond] per condition (dodged); box per
   library; [cond] dodged box by condition; [cond] free-y facets (x = condition); per-donor
   box and faceted bars.
5. `cell_type_median_UMIs.pdf`: the same set of views for median UMIs/nucleus.
6. `cell_type_proportions.pdf`: the same set of views for % of nuclei.
7. `donor_cell_type_distributions.pdf`: stacked cell type % per donor; [cond] faceted by
   donor, cell type fraction dodged by condition; faceted by donor, box of library fractions
   per cell type.

There is a lot of duplication: the per-donor cell type pages appear in both
`donor_summary.pdf` and the cell type PDFs.

Bugs seen in the rendered v138 PDFs:
- The condition-filled pages have a legend titled "Library".
- Per-library pages drop zero-count cell types (no point at 0).
- A spurious "a EXPECTED" legend appears.

**Intent, summarised.** After aggregation, answer:
- (a) Did every library sequence and demultiplex well, and do conditions differ?
- (b) Did we recover every expected donor, with how many nuclei and what RNA quality? Did
  unexpected donors appear?
- (c) What is the cell type composition and per-type quality, overall and per condition,
  library and donor? Conditions are mostly FACS sorts (NeuN+/-, SOX6 low/high), so "did
  the sort enrich the intended types" is a main question.

---

## Part 2: decisions (agreed with the user)

1. **Condition.** One optional variable that is a property of the library. It comes from
   EITHER an external TSV (library -> condition, the same format as the legacy files) OR a
   named cell-metadata column (for example one added by a manifest `joins`). Both are reduced
   to one library -> condition table.
   - It is an error if a cell-metadata column has more than one value within a library, or if
     a library is missing from the TSV.
   - With no condition, all libraries form one group and the condition-only pages are skipped.
2. **Expected donors.** These come from the village `donorFile` recorded in each library's
   village `properties.yaml`, and from nowhere else. Never use the VCF, which holds more
   donors than the experiment, and there is no override param.
   - All libraries must share one donor set, compared by file **contents**, not location.
   - The tool knows nothing about artifact YAMLs: it takes the donor files themselves
     (`--donor-file`). The caller (the shell script or the Nextflow process) extracts `donor_file`
     from each library's artifact YAML, and passes none at all if any library has none.
   - If no donor file is given, or the sets differ, log it and skip **all
     donor-level outputs**. Library-level and overall cell-type outputs are still produced.
   - An aggregation that mixes villages is legitimate; it just doesn't get donor QC.
3. **Core cell types** (replaces the hard-coded "primary neuron" list).
   - **What they are:** a few cell types that are consistently present in the tissue
     measured, whatever the dissection, and so give a stable per-donor median. Other cell types
     vary more between donors because dissections differ (which sub-regions were included), so
     their per-donor values vary for that reason too, not only through RNA quality. The user
     chooses the core cell types for the tissue; an example is the striatal projection neurons.
   - **What is computed:** for each donor, the median UMIs per nucleus (`--umi-column`) over
     the nuclei of each core cell type, and over all of them pooled. Nothing is normalised or
     divided by them: they are not a calibration and not a denominator. They answer "is this
     donor's RNA quality low in the same cell type as the other donors?", which the overall
     median can't, because it also depends on the donor's cell-type mix.
   - **Input:** an optional, reusable file, headerless, one cell type per line. Each listed
     type that is present gets a `donor_qc` column and a per-donor page.
   - **Legacy:** the hard-coded list was `glutamatergic, SPN, Upper.rhombic.lip` (scPred
     labels). A core cell types file replaces it; for the legacy v138 data it would contain
     `SPN`.
   - Keep the legacy **pooled** column too: the median over all core-type cells combined.
     Its intent is unknown, and the user will ask users whether they need it.
   - Listed types that are absent from the data are logged.
   - The labels must match the cell type column (MMC model + level), so each list belongs to
     one taxonomy level.
   - A median from only a few nuclei is noisy, and the legacy code did not guard against
     it. This is an open question (a minimum number of nuclei per donor) and is not part of
     this plan yet.
4. **Output layout.** Keep the legacy **file names and page sets**, because users know them.
   Consolidating them is a later refactor.
5. **UMI column.** A `--umi-column` param with default `num_retained_transcripts`
   (post-CBRB), the same default as `donor_cell_type_report`. It is used for every median and
   total UMI value.
6. **Column names.** snake_case throughout, `donor_qc.txt` included.
7. **Fix the legacy bugs; don't reproduce them:**
   - The 28-colour donor palette is kept exactly as the legacy code defines it (see Plot
     style in Part 3); it is not replaced. Donor pools are not larger than 28.
   - Correct the legend titles.
   - Include zero-count points.
   - Use the same cell type column in every step.
   - Drop the stray legend.
8. **Library metrics pages.**
   - Driven by a declarative metric list. A missing or all-NA column is skipped with a log line.
   - Drop the %polyA and %TSO trimming pages (those metrics are not coming back).
   - Add a page for % scDblFinder doublets.
   - Replace the scPred pages with MMC equivalents computed from the cell metadata using the
     pipeline's model + level (the cell type column): per library, # nuclei with a cell type
     label, and the median UMIs of those nuclei. These two pages are drawn only under the cell
     type gate (MMC may not have been run on every library; see Gating).
   - `donor_equitability` is not its own page. It is printed per library on the donor
     composition page.
9. **Scope.** One Python CLI, called by one optional Nextflow process. No per-library
   manifest key for the condition: that would extend `DGE_KEYS`, which deliberately matches
   Zamboni's schema.

---

## Part 3: design

### Code location
New subpackage `transcriptome_java/public/src/python/src/dropseq/aggregation/plots/`:

| File | Contents |
|---|---|
| `__init__.py` | empty (it uses the `logger` and `add_log_argument` from `dropseq.aggregation`) |
| `aggregation_qc.py` | CLI `main()`. Reads and validates the inputs, resolves the condition / expected donors / core cell types, decides which outputs are enabled (gating), and calls the reports. |
| `qc_tables.py` | Pure pandas, no plotting: `donor_qc_table`, `library_cell_summary`, `complete_donor_cell_type` (donor x cell type grid filled with zeros, plus an expected flag), `resolve_conditions`, `expected_donors_from_files`, `read_core_cell_types`. |
| `plot_primitives.py` | Reusable matplotlib/seaborn page builders: `sorted_bar_with_median`, `bar_and_condition_box` (the two-panel library page), `box_with_points`, `dodged_bars`, `stacked_fraction_bars`, `faceted_sorted_bars` (independent y axis and median per panel, donors sorted within each panel), `faceted_box_by_condition`; `donor_palette(donors)`; `page_title(fig, analysis_id, subtitle)`. |
| `library_reports.py` | `library_metrics_report` (with `LIBRARY_METRICS`, the declarative list) and `filtered_library_metrics_report` |
| `donor_reports.py` | `donor_summary_report`, `donor_nuclei_counts_report` |
| `cell_type_reports.py` | `cell_type_counts_report`, `cell_type_median_umis_report`, `cell_type_proportions_report`, `donor_cell_type_distributions_report` |

Reuse:
- `donor_cell_type_report()` from `dropseq/aggregation/donor_cell_type_report.py:43`.
  Recompute the donor x cell type table in memory with the same `--umi-column`, so it can't
  drift from `donor_qc`. There is no need to pass `donor_cell_type.txt` in.
- `default_store()` from `dropseq/util/storage.py:128`, to read donor files and artifact
  YAMLs from local paths or `gs://`.
- `logger` and `add_log_argument` from `dropseq/aggregation/__init__.py`.

Each report function takes the prepared DataFrames plus `analysis_id` and `out_dir`, and
writes one PDF with `matplotlib.backends.backend_pdf.PdfPages`. Pages are 14 x 7 in, like
the legacy PDFs. Each page has the analysis id as its title and an explanatory subtitle
(port the legacy subtitles).

Plot style:
- Light grid.
- Bars have black edges.
- Value labels on the bars; rotated 90° in the faceted pages.
- Unexpected donors' labels in red, with "red label = unexpected donor" in the subtitle.
  This replaces ggplot's colour legend.
- Donor colours: the legacy 28-colour palette (the `colors` vector of
  `plot_donor_celltype_qc.R`), in this order, assigned to the sorted donor IDs, so a donor
  has the same colour on every page and in every PDF. Put it in `plot_primitives.py` as one
  constant. With more than 28 donors, log a warning and cycle the palette.
  ```
  "#3478b5", "#aec8e8", "#f37f11", "#f6bc78", "#30a12b", "#99df8a", "#d72729",
  "#f59897", "#9567bd", "#c5b0d5", "#8c564c", "#c49d94", "#e477c2", "#f7b7d3",
  "#7f7f7f", "#c7c7c7", "#d1d11b", "#f0f08d", "#159696", "#8fdbdb", "#d93d6c",
  "#d6819a", "#76ad17", "#7c8f5a", "#1bafe0", "#8ed6ed", "#6729cc", "#9f91eb"
  ```
- Legends go outside the axes on the right.
- Use seaborn for the dodged boxes with overlaid points (`boxplot` + `stripplot`, `dodge=True`).

### CLI: `aggregation_qc`
```
aggregation_qc
  --cell-metadata  <analysis>.cell_metadata.txt          (required)
  --library-metrics <analysis>.library_metrics.txt       (required)
  --analysis-id    <id>     (titles and output file prefix; required)
  --output-dir     <dir>    (default .)
  --cell-type-column <col>  (optional; e.g. HMBA_Human_WB_v0.5_neighborhood_name)
  --donor-file     <file> [...]   (optional; donor file of each library, local or gs://; without it no donor outputs)
  --conditions-file <tsv> | --condition-column <col>     (optional, mutually exclusive)
  --core-cell-types <file>  (optional; headerless list of core cell types, one per line)
  --umi-column     num_retained_transcripts
  --donor-column   donor
  --library-column PREFIX            (cell metadata)
  --library-metrics-library-column library
  --log-level
```

Rules:
- The donor files are compared by content. The caller passes the donor file of every library
  or none, so a library without one (for example one that is not a village) is the caller's
  decision to skip donor QC.
- The conditions TSV has a header and exactly 2 columns, (library, condition). The column
  names are not checked, so legacy files work unchanged.
- Exit status is non-zero for invalid input (a missing required column, a bad condition,
  conflicting options). A skipped section is not an error: it is logged and the run exits 0.

### Gating

| Output | Needs |
|---|---|
| `<id>.library_metrics.pdf` | always; its two cell type pages (# labelled nuclei, their median UMIs per library) only under the cell type gate |
| `<id>.filtered_library_metrics.pdf` | always |
| `<id>.donor_qc.txt`, `<id>.donor_summary.pdf`, `<id>.donor_nuclei_counts.pdf` | donor gate |
| `<id>.cell_type_counts.pdf`, `<id>.cell_type_median_UMIs.pdf`, `<id>.cell_type_proportions.pdf` | cell type gate; the per-donor pages also need the donor gate |
| `<id>.donor_cell_type_distributions.pdf` | donor gate and cell type gate |

- **Donor gate:** the donor column exists in the cell metadata; at least one cell has a
  donor; at least one `--donor-file` was given; and every donor file has the same set of
  donors.
- **Cell type gate:** `--cell-type-column` was given, the column exists, and at least one
  cell has a label. MMC may not have been run on every library: cells without a label are left
  out of the cell type pages, and their number is logged. On the two cell type pages of
  `<id>.library_metrics.pdf`, a library with no labelled cells has 0 nuclei and no median UMI
  value. Unlike the legacy code, a few NA values don't disable the cell type outputs.
- Core cell type outputs need both gates and a core cell types file.
- Condition pages need a condition.

### `donor_qc.txt` columns
`donor num_nuclei fraction_nuclei total_umis_m median_umis_per_nucleus`, then, if there are
core cell types, `median_umis_per_core_cell_type` (pooled) and one
`median_umis_per_nucleus_<type>` per core cell type present.
- Expected donors with no cells are included, with num_nuclei 0 and the other values NA.
- Add an `expected` column (true/false), since the plots compute it anyway.
- Rounding matches the legacy code: fraction to 3 decimal places, total_umis_m to 3.

### `locate_scRNA_artifacts` change
In `dropseq/aggregation/locate_scRNA_artifacts.py`:
- Add `donor_file` to `CANONICAL_FIELDS`, after `village_properties` (around line 121).
- When `village_properties` is not NA, read it with `store.read_text` and `yaml.safe_load`
  (the same pattern as root properties at line 279) and set `donor_file` to its `donorFile`
  value, or NA. Never read `vcf`.
- Update the module docstring and `tests/aggregation/test_locate_scRNA_artifacts.py`, including
  the fixtures: add a village properties file with `donorFile`.
- Check for any consumer that assumes a fixed field list: `resolve_aggregation_manifest`,
  and this repo's `LIB_A.yaml` expected fixture (see Part 4).

### Packaging
- `pyproject.toml` `[project.scripts]`: add
  `aggregation_qc = "dropseq.aggregation.plots.aggregation_qc:main"`. Add `matplotlib` and
  `seaborn` to `dependencies` explicitly; today they only arrive through scanpy.
- `command_line_programs.tsv` (transcriptome repo) is not touched: the tool is run from the
  Python image or with `uv`, not from a deployment wrapper.

---

## Part 4: the Nextflow process

One process, `AGGREGATION_QC`, in `modules/local/aggregation_qc/main.nf`, with
`container 'quay.io/broadinstitute/drop-seq_python:current'` like the other Python modules.
It is gated by a new boolean `params.run_qc`, default `false`; when false nothing changes.
It never alters the other outputs. The published files are the ones in the Gating table of
Part 3, flat in `--outdir` with the legacy names. `<id>` is `params.analysis_id`.

- **Inputs** (typed records, like the other modules):
  - `<analysis>.cell_metadata.txt` (the `MERGE_CELL_METADATA` output)
  - `<analysis>.library_metrics.txt` (the `MERGE_LIBRARY_METRICS` output)
  - the donor files: the `donor_file` of each `artifacts/<uei>.yaml` from
    `LOCATE_SCRNA_ARTIFACTS`, extracted in the workflow (Groovy, as the resolver reads the YAMLs),
    as a list that is empty if any library has none; the files are staged by base name, so
    two with one name need renaming, as for the joins
  - `params.analysis_id`
  - the cell type column name, as the channel value `DONOR_CELL_TYPE_REPORT` already gets;
    absent if the run has no MMC results
  - the optional files and values from the params below
- **Script block**, in outline:
  ```
  aggregation_qc \
      --cell-metadata ${cell_metadata} --library-metrics ${library_metrics} \
      --donor-file ${donor_files} --analysis-id ${id} \    # only if there are donor files
      --cell-type-column '${cell_type_column}' \   # only if there is one
      --conditions-file ${conditions} \            # or --condition-column, never both
      --core-cell-types ${core_cell_types} \       # only if given
      ${args}
  ```
- **Outputs:** `*.pdf`, and `*.donor_qc.txt`, which only exists under the donor gate, so it is
  an optional output. Publishing needs the same four edits as any new result: an `emit:` in
  `workflows/scrna-aggregation.nf` (next to the others, around lines 280-293), an emit in
  `MCCARROLL_SCRNA_AGGREGATION` in `main.nf`, a `publish:` line and an `output {}` entry.
  Add a `stub:` block.
- **GCS credentials:** the Python tool reads the donor files from `gs://` itself, through
  `dropseq.util.storage.default_store`. The pipeline does not parse them (see
  `credentials.md`).
- **A skipped output is not an error.** Gates are decided in the Python tool and logged; the
  tool exits 0. Only invalid input exits non-zero.

### New parameters
Add them to `nextflow_schema.json` and `conf/params.config`.

| Param | Meaning |
|---|---|
| `run_qc` | boolean, default false. Run the QC step. |
| `qc_conditions_file` | optional TSV, a header and two columns (library, condition). The column names are not checked, so the legacy conditions files work unchanged. Every library must be in it. |
| `qc_condition_column` | optional name of a cell-metadata column (for example one added by a manifest `joins`). It must have one value per library; the tool fails if not. Mutually exclusive with `qc_conditions_file`. |
| `qc_core_cell_types` | optional file, headerless, one cell type per line: the core cell types of the tissue (a few types that are consistently present whatever the dissection, so their per-donor median UMI is comparable between donors; nothing is normalised by them). Each listed type present in the data gets a per-donor median UMI column and page, plus a pooled column. The labels must belong to the chosen MMC model and level, so a file is tied to one taxonomy level. |

The UMI column is the tool's `--umi-column` (default `num_retained_transcripts`); it needs
no param (use `ext.args` to change it).

### Pre-flight checks
- `qc_conditions_file` and `qc_condition_column` given together: fail.
- `qc_conditions_file`, `qc_condition_column` or `qc_core_cell_types` given without
  `run_qc`: warn (they are ignored).
- `qc_core_cell_types` given when there are no MMC results: warn.

### Dependency on the artifact YAML
The expected donors come from `donor_file`, the new field of `locate_scRNA_artifacts`
(Part 3). In this repo:
- The `locate_scrna_artifacts` expected fixtures
  (`modules/local/locate_scrna_artifacts/tests/fixtures/expected/LIB_A.yaml`) gain the
  `donor_file` line, and the fixture village `properties.yaml` (currently empty) needs a
  `donorFile`.
- `tests/live_data/baseline/artifacts/*.yaml` are regenerated (done; the baseline now has `donor_file`). The SMRI_V11 donor file is
  `gs://mccarroll_scrnaseq_central_temp/alecw/nextflow_inputs/2024-03-27_SMRI_V11.donors.txt`.
- Check that `lib/LibraryResolver.groovy` does not assume a fixed field list.
- `aggregation_qc` and `donor_file` are in the public `current` image (digest in "Status and next step"). The
  Nextflow modules use `current`, so `LOCATE_SCRNA_ARTIFACTS` already writes `donor_file`. Move the
  `prod` tag of this repo before turning `run_qc` on in a real run.

### Docs to update when implemented
`docs/output.md` (the new files), `docs/usage.md` (the params, an example, and a definition of core cell types with an example
file),
`docs/data_flow.md` and the README figure if the figure lists processes
(`docs/figures/render.sh`), `SPEC_SUMMARY.md`, `CHANGELOG.md`; then move this plan's
completed items to `DONE.md`.

### Open items
- Run QC by default in production runs, or only on request? This plan assumes only on
  request.
- Publish the PDFs into a subdirectory (for example `qc/`) rather than flat? The legacy
  names are kept for now, so flat is assumed; decide before the first release.

---

## Part 5: implementation steps
Steps 1-7 are done (see "Status and next step").
1. Keep this document in step with the code as decisions change.
2. `locate_scRNA_artifacts`: add `donor_file`, with tests. (done)
3. `qc_tables.py`, with unit tests (hand-computed values on a small synthetic metadata table). (done)
4. `plot_primitives.py`, then the report modules; then `aggregation_qc.py` (CLI and gating). (done)
5. `pyproject.toml` entry point and dependencies. (done)
6. Visual review against the legacy PDFs (see Verification), then iterate on the styling. (done for the pages without cell types; the legacy cell type pages could not be compared, because the Zamboni data has no cell type labels)
7. **Prototype script, before the Nextflow process.** (done) Add an optional QC step to
   `docs/specifications/scrna-aggregation_prototype.sh` (after the cell metadata and library
   metrics are written; it runs the `aggregation_qc` command in the Python container like the
   other Python tools), with the flags `--run-qc`, `--qc-conditions-file`,
   `--qc-condition-column` and `--qc-core-cell-types`. Then update `SPEC_SUMMARY.md`, which is
   derived from the script. This lets us run the code and the container image on the live test
   data (the SMRI_V11 baseline) before the Nextflow process exists, so problems in the tool or
   the image show up first.
8. The Nextflow process, params, pre-flight checks, fixtures and docs of Part 4.

## Verification
- Unit tests in `tests/aggregation/test_aggregation_qc.py` (and `test_qc_tables.py`):
  - donor_qc values, the pooled and per-type core columns, and zero rows for missing
    expected donors
  - condition resolution: TSV, column, varies-within-library error, missing-library error
  - donor list consistency: same contents at different paths passes; a different set, or a
    library with NA, skips the donor outputs
  - gating: which files are produced for no cell type, no donors, and no conditions
  - smoke tests that each PDF exists and has the expected page count
    (`PdfPages.get_pagecount()`)

  Run them with `cd public/src/python; uv run python -m unittest discover -s tests/aggregation -t .`
- End-to-end on the new baseline (done): run the tool from the Docker image, through the prototype script, not with `uv run`:
  `docs/specifications/scrna-aggregation_prototype.sh --manifest tests/live_data/manifest.yaml --analysis-id SMRI_V11.unfiltered --out-dir tests/live_data/baseline --image-tag current --run-qc`
  (see `../testing.md`). The donor file, recorded as `donor_file` in the artifact YAML, is
  `gs://mccarroll_scrnaseq_central_temp/alecw/nextflow_inputs/2024-03-27_SMRI_V11.donors.txt`.
- Parity against the legacy run: run on the legacy v138 data, which has conditions and cell
  types, using the column-name options
  (`--donor-column DONOR --umi-column NUM_TRANSCRIPTS --cell-type-column predClass`) and the
  v138 conditions file. Use a donor file that lists the v138 donors. Render both sets of PDFs with `pdftoppm` and compare them page by page. The
  numbers should match the legacy PDFs except where a bug was deliberately fixed.
- Nextflow candidate tests (to rank in the session):
  - module test of `AGGREGATION_QC` with a small fixture (a cell metadata table, a library
    metrics table, two local donor files): the expected
    files exist and the PDFs are non-empty
  - donor gate: different donor sets, or no donor file, give no donor
    files and a zero exit status
  - cell type gate: no cell type column gives no cell type PDFs
  - conditions from a file and from a column; both given fails in pre-flight
  - `run_qc = false` (default): no QC process runs and the outputs are unchanged versus the
    baseline
  - live test: add the QC outputs to the baseline comparison. PDFs cannot be diffed, so
    compare their existence, and `donor_qc.txt` by value
