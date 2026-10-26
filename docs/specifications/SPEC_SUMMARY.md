# scRNA aggregation: spec summary (derived from the prototype)

Source of truth: `scrna-aggregation_prototype.sh` (outputs validated). Behavior below is read from it; nothing is invented. Where the pipeline
differs from the prototype, the difference is noted ("Pipeline:"); the full design is in `../development.md` and `../data_flow.md`.
Companion files: `TODO.md` (what is left), `DONE.md` (what is done), `../development.md` (decisions, gotchas, how to run).

## Purpose
Aggregate several single-library Nextflow scRNA pipeline outputs (selected by a YAML manifest of DGE URLs) into one
analysis: library metrics, combined cell metadata, combined triplet (mtx) DGE, donor/cell-type report, and donor and
donor x cell-type metacells.

## Inputs (prototype flags -> pipeline params)
| Prototype flag | Meaning | Pipeline param |
|---|---|---|
| --manifest | YAML: `dges:` list (dge, optional donor/filters/joins) + `dgeDefaults` | params.manifest |
| --analysis-id | prefix of aggregate output files | params.analysis_id |
| --out-dir | output dir | params.outdir |
| --tmp-dir | scratch | not needed (Nextflow work dir) |
| --image-tag | tag of python/java images | fixed to `current` in each module (override per process in a config) |
| --mmc-model / --mmc-level | optional | params.mmc_model / mmc_level |
| --reference | optional | none: libraries with different references fail in the resolver |
| --java-memory | `-m` for Java tools | none: the JVM heap is 80% of `task.memory` (15 GB, then 30 GB, for the three Java steps in `conf/modules.config`) |
| (none) | GCP credentials mounted into the containers | params.gcp_credentials_file (docker profile only; default: your Application Default Credentials) |

Containers: python tools `quay.io/broadinstitute/drop-seq_python:current`; java tools `quay.io/broadinstitute/drop-seq_java:current` (both public; the
prototype used the private Java image, but the public `current` one has `MakeTripletDge` and `MakeMetacellsFromTripletDge`). The names and tag are hard coded in the
modules. Note `docker.registry = 'quay.io'` in nextflow.config only prefixes images with no host, so it does not rewrite these fully-qualified names.
Credentials: prototype mounts ADC and copies gs:// on the host. Pipeline: Nextflow stages gs:// inputs; the tools that read gs://
themselves (locate_scRNA_artifacts, summarize_scRNA_experiments) get credentials in the container: the mounted credentials file with the
`docker` profile, the VM's service account on Google Batch (see `../credentials.md`).

## Steps (prototype section -> tool -> data)
| # | Step | Tool (container) | Cardinality | In -> Out |
|---|---|---|---|---|
| 1a | locate artifacts | `locate_scRNA_artifacts --manifest M --output-dir D` (py) | 1 run, reads gs:// listing | manifest -> `<uei>.yaml` per library |
| 1b | resolve manifest | `resolve_aggregation_manifest --manifest M --artifacts-dir D --analysis-id ID [--reference R] [--mmc-model X] --output-dir O` (py) | 1 run | -> `libraries.tsv` (cols: library_id, artifact_file, dge, cell_metadata, mmc_model, mmc_annotations, reduced_gtf, args_file) + `<lib>.join_and_filter_args.txt` (one arg per line; may be empty) |
| 2a | library metrics | `summarize_scRNA_experiments --artifacts <lib>.yaml --summary <lib>.library_metrics.txt --tearsheet-dir tearsheets` (py) | per library | -> metrics tsv (1 row) + `tearsheets/<lib>.standard_analysis_tearsheet.txt` |
| 2b | concat metrics | `cat_tsvs --output ID.library_metrics.txt <files...>` (py) | gather | -> `ID.library_metrics.txt` |
| 3a | fetch | cp / gcloud storage cp of cell metadata (cmd.tsv), DGE, mmc csv | per library | Nextflow staging replaces this |
| 3b | convert MMC | `convert_mmc_csv --input mmc.csv --column-prefix <model>_ [--level L] --cell-type-column-output cell_type_column.txt --output mmc.tsv` (py) | per library, only if mmc_annotations != NA | -> mmc.tsv + one-line cell type column name |
| 3c | consistency check | all libraries must give the same cell-type column name, else error | gather | |
| 3d | join/filter | `join_and_filter_tsv --input cmd.tsv --output <lib>.joined_filtered_cell_metadata.txt --set-first --set PREFIX <lib> [--join mmc.tsv cell_barcode cell_id] <args from args_file>` (py) | per library | MMC join comes first so manifest filters can use its columns. A donor in manifest overrides donor col via args_file. |
| 4 | triplet manifest | writes YAML `dges:` list: dge (local path), prefix=library, barcode_list=<lib>.joined_filtered_cell_metadata.txt, barcode_column=cell_barcode | gather | -> `ID.make_triplet_dge.yaml` |
| 5 | combine DGEs | `MakeTripletDge -m MEM TMP_DIR VALIDATION_STRINGENCY=SILENT OUTPUT=matrix.mtx.gz OUTPUT_CELLS=barcodes.tsv.gz OUTPUT_FEATURES=features.tsv.gz MANIFEST=... REDUCED_GTF=...` (java) | gather | -> matrix.mtx.gz, barcodes.tsv.gz, features.tsv.gz (reduced GTF ~340 MB, same for all libraries) |
| 5b | h5ad per library | `build_library_h5ad --dge <lib DGE> --cell-metadata <lib>.joined_filtered_cell_metadata.txt --reduced-gtf GTF --uppercase-column cell_barcode --output h5ad/<lib>.h5ad` (py) | per library, after the reduced GTF is localized | -> `h5ad/<lib>.h5ad`: `X` raw counts, `obs` the cell metadata indexed `<lib>_<barcode>` with `CELL_BARCODE`, `var` gene IDs (`gene_ids`) with `gene_symbol`; plain string arrays |
| 6 | combine metadata | `cat_tsvs --output ID.cell_metadata.txt --index-col PREFIX --index-col cell_barcode <lib metadata files>` (py) | gather | -> `ID.cell_metadata.txt` |
| gate | donor column? | if `donor` not in header of cell_metadata: warn, skip 7-9 | conditional | |
| 7 | donor/cell type report | `donor_cell_type_report --input cell_metadata --output ID.donor_cell_type.txt --cell-type-column COL` (py) | only if cell type column exists | -> tsv (donor, cell_type, num_nuclei, fraction_nuclei, median_umis_per_nucleus) |
| 8 | donor metacells | `MakeMetacellsFromTripletDge -m MEM MATRIX FEATURES BARCODES MAPPING=cell_metadata CELL_BARCODE_COLUMN=cell_barcode TMP_DIR VALIDATION_STRINGENCY=SILENT OUTPUT=ID.donors.metacells.txt.gz GROUP_COLUMNS=donor` (java) | needs donor col | |
| 9 | donor x cell type metacells | same, `OUTPUT=ID.donor_cell_type.metacells.txt.gz GROUP_COLUMNS=donor GROUP_COLUMNS=COL` | needs donor col and cell type col | |

## Outputs (prototype, written to out-dir)
`ID.library_metrics.txt`, `tearsheets/<lib>.standard_analysis_tearsheet.txt`, `<lib>.joined_filtered_cell_metadata.txt`,
`ID.make_triplet_dge.yaml`, `ID.cell_type_column.txt` (only with MapMyCells results; added to the prototype 2026-10-16), `matrix.mtx.gz`, `barcodes.tsv.gz`, `features.tsv.gz`, `ID.cell_metadata.txt`,
`ID.donor_cell_type.txt`, `ID.donors.metacells.txt.gz`, `ID.donor_cell_type.metacells.txt.gz`, `h5ad/<lib>.h5ad`
(+ intermediate `artifacts/`, `resolved_manifest/`).

Pipeline: publishes the merged files flat in `--outdir` (`ID.library_metrics.txt`, `ID.cell_metadata.txt`, `matrix.mtx.gz`, `barcodes.tsv.gz`,
`features.tsv.gz`; with donors also `ID.donors.metacells.txt.gz`, and with donors and a cell type column also `ID.donor_cell_type.txt` and
`ID.donor_cell_type.metacells.txt.gz`), `artifacts/<uei>.yaml`, `tearsheets/`, `h5ad/<uei>.h5ad` and `pipeline_info/` (with `ID.resolved_libraries.txt`). The
per-library joined cell metadata, the triplet manifest and the args files stay in the work directory; there is no `cell_type_column.txt` or
`resolved_manifest/`.

## Reference run (real data, validated)
Reproducible from the repo: `tests/live_data/manifest.yaml` run through `scrna-aggregation_prototype.sh` with
`--analysis-id SMRI_V11.unfiltered --out-dir tests/live_data/baseline --image-tag current` (git-ignored; see `docs/testing.md`, "Live tests"),
made with the public `current` images (session 13).
The original validated run, kept for reference and never modified, is in `/Users/nemesh/nextflow_aggregation_shell_script/out`.
- 1 library `SMRI_V11_rxn1` (donor DGE, village), 238 cells (239 lines w/ header), 12778 genes, ~17 donors, MMC model
  HMBA_Human_WB_v0.5, cell type column `HMBA_Human_WB_v0.5_neighborhood_name`, empty args file.
- Inputs fetched to `<out-dir>/tmp/SMRI_V11_rxn1/`: `cmd.tsv` (238 rows), `mmc.csv` (3752 rows; superset of cells, hence the
  left join), `*.donors.digital_expression.txt.gz` (12787 lines, 255 KB), `../tmp/GRCh38_ensembl_v43.reduced.gtf` (3.9M lines).
- `tests/live_data/manifest_no_donors.yaml` = second scenario (selected-cells DGE, no donor column, probably no MMC) -> would exercise the skip branches live (not run: the synthetic pipeline tests cover the no-donor and no-MapMyCells branches).
- Single library only: multi-library behavior (cat_tsvs union columns, index uniqueness, MakeTripletDge merging, cell
  type column mismatch error) is NOT covered by the reference run; the synthetic pipeline tests (`tests/pipeline.synthetic.nf.test`) cover it.

## Data-flow hazards noted for Nextflow, and how the pipeline handles them
- Prototype uses absolute host paths inside files (triplet manifest, artifacts yaml). Pipeline: MAKE_TRIPLET_DGE writes its manifest in the task
  from the staged file names.
- `libraries.tsv` and the args files are produced at runtime by the prototype. Pipeline: no `libraries.tsv`; `LibraryResolver` (Groovy, head job)
  resolves the libraries, `JoinFilterArguments` builds each library's arguments from the manifest, and BUILD_LIBRARY_CELL_METADATA writes them to
  `<lib>.join_and_filter_args.txt` in its task and reads it with `--args-file` (no `ext.args`).
- Optional MMC (value `NA`) -> per-library conditional; the cell type column is a runtime value (the tool's output) that gates steps 7 and 9.
  Pipeline: the donor gate is known upfront (a manifest donor or a village in the artifacts, for all libraries or none), not read from the header.
- Prototype gather steps need stable ordering (cat_tsvs output order follows input order). Pipeline: libraries are merged in manifest order
  (`position`), and the metrics, the cell metadata and the triplet DGE are made from one sorted list.
- No `zcat` on macOS for .gz: use `gzip -dc` when inspecting fixtures locally.

## Module for each prototype step (status in DONE.md)
| Step | Module |
|---|---|
| 1a | LOCATE_SCRNA_ARTIFACTS |
| 1b | RESOLVE_AGGREGATION_MANIFEST in the prototype; in the workflow `LibraryResolver` (Groovy, head job; the library's DGE is the manifest DGE) |
| 2a | SUMMARIZE_SCRNA_EXPERIMENTS |
| 2b, 6 | MERGE_LIBRARY_METADATA (twice: library metrics, cell metadata) |
| 3b | FORMAT_MAPMYCELLS_ANNOTATIONS (tool `convert_mmc_csv`) |
| 3d | BUILD_LIBRARY_CELL_METADATA (tool `join_and_filter_tsv`) |
| 5b | BUILD_LIBRARY_H5AD (tool `build_library_h5ad`) |
| 4, 5 | MAKE_TRIPLET_DGE |
| 7 | DONOR_CELL_TYPE_REPORT |
| 8, 9 | MAKE_METACELLS_FROM_TRIPLET_DGE (called twice: donor; donor and cell type) |

