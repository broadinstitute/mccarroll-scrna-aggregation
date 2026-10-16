# mccarroll/scrna-aggregation: Testing

Tests use [nf-test](https://www.nf-test.com) (0.9.5). Run everything from the repository root. For the coding
conventions and known pitfalls, see [development.md](development.md).

## Test conventions

- Unit tests sit next to the unit, as in nf-core: `modules/local/<tool>/tests/main.nf.test`, with a `nextflow.config`
  and `fixtures/` beside it. Pipeline-level tests go in the top-level `tests/`.
- Test names start with `Should ...`.
- One test file per unit for the unit's tests (`main.nf.test`). Split into a second file only when the tests serve very
  different purposes, such as synthetic fixtures (`main.nf.test`) versus real data (`gcs.nf.test`).
  Tests of one unit that need a different config (for example another `ext.args`) stay in the same file: nf-test accepts
  `config "./x.config"` inside a single `test` block, which overrides the file-level config for that test. nf-test has
  no way for one file to include another; it discovers every `*.nf.test` under the path you give it.

## How to run the tests

To run everything, first make the baseline once (step 1 under [Live tests](#live-tests-real-data-compared-with-the-baseline)),
then run `tests/run_all_tests.sh` (step 2). The fixture tests alone need no baseline: see the table.

| What | Needs | Command |
|---|---|---|
| Pre-flight credentials check (12 tests, `preflight.function.nf.test`) | nothing | `nf-test test subworkflows/local/utils_nfcore_scrna-aggregation_pipeline/` (all tests in the directory) |
| `LOCATE_SCRNA_ARTIFACTS`, fixture tests (6) | Docker and the `jn_test` image | `nf-test test modules/local/locate_scrna_artifacts/tests/main.nf.test` |
| `RESOLVE_AGGREGATION_MANIFEST`, fixture tests (7) | Docker and the `jn_test` image | `nf-test test modules/local/resolve_aggregation_manifest/tests/main.nf.test` |
| `SUMMARIZE_SCRNA_EXPERIMENTS`, fixture tests (2) | Docker and the `jn_test` image | `nf-test test modules/local/summarize_scrna_experiments/tests/main.nf.test` |
| `MERGE_LIBRARY_METADATA`, fixture tests (4, `main.nf.test`) | Docker and the `jn_test` image | `nf-test test modules/local/merge_library_metadata/tests/main.nf.test` |
| `FORMAT_MAPMYCELLS_ANNOTATIONS`, fixture tests (4, `main.nf.test`) | Docker and the `jn_test` image | `nf-test test modules/local/format_mapmycells_annotations/tests/main.nf.test` |
| `BUILD_LIBRARY_CELL_METADATA`, fixture tests (6, `main.nf.test`) | Docker and the `jn_test` image | `nf-test test modules/local/build_library_cell_metadata/tests/main.nf.test` |
| `MAKE_TRIPLET_DGE`, fixture tests (4, `main.nf.test`) | Docker and the local `us.gcr.io/mccarroll-scrna-seq/drop-seq_private_java:jn_test` image | `nf-test test modules/local/make_triplet_dge/tests/main.nf.test` |
| Pipeline input validation (4, `tests/pipeline.validation.nf.test`) | `GOOGLE_PROJECT_ID` (the pre-flight check); no containers start | `nf-test test tests/pipeline.validation.nf.test` |
| Whole pipeline against the baseline (1 live test, `tests/pipeline.live.nf.test`; grows with each wired edge) | Docker, network, ADC, `GOOGLE_PROJECT_ID`, the baseline | `GOOGLE_PROJECT_ID=bican-um1-mccarroll nf-test test tests/pipeline.live.nf.test` |
| `MAKE_METACELLS_FROM_TRIPLET_DGE`, fixture tests (5, `main.nf.test`) | Docker and the `jn_test` private Java image | `nf-test test modules/local/make_metacells_from_triplet_dge/tests/main.nf.test` |
| Manifest parsing (12 tests, `manifest.function.nf.test`) | Nothing (no Docker, no network) | `nf-test test subworkflows/local/utils_nfcore_scrna-aggregation_pipeline/tests/manifest.function.nf.test` |
| `join_and_filter_tsv` arguments (7 tests, `arguments.function.nf.test`) | Nothing (no Docker, no network) | `nf-test test subworkflows/local/utils_nfcore_scrna-aggregation_pipeline/tests/arguments.function.nf.test` |
| `RESOLVE_LIBRARIES`, fixture tests (3) | Docker and the `jn_test` image | `nf-test test modules/local/resolve_libraries/tests/main.nf.test` |
| Library resolver (9 tests, `resolver.function.nf.test`) | Nothing (no Docker, no network) | `nf-test test subworkflows/local/utils_nfcore_scrna-aggregation_pipeline/tests/resolver.function.nf.test` |
| Library resolver against the baseline (1 live test, `resolver.live.nf.test`) | The baseline only | `nf-test test subworkflows/local/utils_nfcore_scrna-aggregation_pipeline/tests/resolver.live.nf.test` |
| `DONOR_CELL_TYPE_REPORT`, fixture tests (3, `main.nf.test`) | Docker and the `jn_test` image | `nf-test test modules/local/donor_cell_type_report/tests/main.nf.test` |
| Everything: 98 tests today (12 pre-flight, 12 manifest, 7 arguments, 9 resolver, 44 module fixture, 4 pipeline validation, 9 module/resolver live, 1 pipeline live) | Docker, network, ADC, `GOOGLE_PROJECT_ID`, and a baseline made first (Live tests, step 1) | `tests/run_all_tests.sh` (stops at once with "no baseline" if step 1 was not done) |

The table lists the tests that need no baseline. The live tests are in the next section.

## Live tests (real data compared with the baseline)

Live tests run a module on real data and compare the result with the baseline: the output of the validated prototype shell script
(`docs/specifications/scrna-aggregation_prototype.sh`) on the same manifest. They are tagged `live`. They exist for the modules that read
`gs://` (also tagged `gcs`) and for the modules that produce the merged files we publish. Per-library intermediate modules
(`FORMAT_MAPMYCELLS_ANNOTATIONS`, `BUILD_LIBRARY_CELL_METADATA`) have fixture tests only: their outputs are covered through the merged
files they feed. The workflow's outputs are checked against the baseline again by the final integration test.

Every live comparison hashes first: the md5 of the generated file's content (decompressed for `.gz`, streamed so large files such as the DGEs are
cheap) is compared with the baseline file's. Equal md5s pass and print `matches baseline (md5 ...)`; only on a mismatch are the fields or lines
compared, to print what differs (at most 10 lines). The helper is `tests/lib/LiveFiles.groovy`, loaded by `libDir` in `nf-test.config`.

The live tests read fixed paths in the repo: the manifest `tests/live_data/manifest.yaml` and the baseline `tests/live_data/baseline/`
(git-ignored, made by step 1 below).

Prerequisites: Docker, network access, the `jn_test` images (see `TODO_STATUS.md`), and your Google Cloud Application
Default Credentials: run `gcloud auth application-default login`, which writes
`$HOME/.config/gcloud/application_default_credentials.json`. These are your own local Google Cloud credentials, and
the same file is used by both steps: step 1 (the shell script) mounts it into its containers, and the tests mount it
into theirs (`gcp_credentials_file` parameter). The shell script additionally copies `gs://` inputs on the host with
`gcloud storage cp`, which uses the gcloud CLI's own login (`gcloud auth login`), a separate credential that the
tests do not need.
### **Step 1: make the baseline**
With the prototype shell script, using the manifest in the repo
(`tests/live_data/manifest.yaml`, see `tests/live_data/README.md`). The baseline is the output of the prototype's
validated serial run of the same steps; the live tests compare the Nextflow modules with it. It goes into
`tests/live_data/baseline/`, which is git-ignored (nothing generated is committed). Run from the repo root, using the same
image tag as the modules (`jn_test` for local images):

```bash
docs/specifications/scrna-aggregation_prototype.sh --manifest tests/live_data/manifest.yaml \
    --analysis-id SMRI_V11.unfiltered --out-dir tests/live_data/baseline --image-tag jn_test
```

It needs the same prerequisites as above plus `gcloud` on the host (it copies `gs://` inputs with
`gcloud storage cp`) and about 340 MB of scratch space for the reduced GTF (in `tests/live_data/baseline/tmp`). This command was run into `tests/live_data/baseline` and the full
suite (including the live tests) passes against that baseline.

### **Step 2: run all the tests** 
With no options (needs the baseline from step 1, the credentials above and the project ID):

```bash
export GOOGLE_PROJECT_ID=bican-um1-mccarroll
tests/run_all_tests.sh
```

The script stops with a clear message, before starting Docker, if the project ID, credentials file, `nf-test` or baseline is
missing. The live tests print the generated and baseline file paths and `matches baseline (...)`, or every differing field.

**What the live tests cover.** One file per module, each with its own tests (`<module>/tests/`); each runs every library in the baseline:

| Test file | Needs | Runs | Compares with the baseline |
|---|---|---|---|
| `locate_scrna_artifacts/tests/gcs.nf.test` | network, ADC | `LOCATE_SCRNA_ARTIFACTS` on the manifest's real `gs://` DGEs | each library's `artifacts/<library>.yaml` (md5, else field by field) |
| `summarize_scrna_experiments/tests/gcs.nf.test` | network, ADC | `SUMMARIZE_SCRNA_EXPERIMENTS` on every `artifacts/<library>.yaml` | `artifacts/<library>.library_metrics.txt` (md5, else column by column) and `tearsheets/<library>.standard_analysis_tearsheet.txt` (md5, else line by line) |
| `merge_library_metadata/tests/live.nf.test` (2 tests) | the baseline only | `MERGE_LIBRARY_METADATA` on the per-library metrics, and on the per-library cell metadata with `--index-col PREFIX --index-col cell_barcode` | `<analysis>.library_metrics.txt` and `<analysis>.cell_metadata.txt` (md5, else line by line) |
| `make_triplet_dge/tests/live.nf.test` | the baseline only | `MAKE_TRIPLET_DGE` on the baseline's local DGE copies (`tmp/<library>/`) and `<library>.joined_filtered_cell_metadata.txt` barcode lists | `matrix.mtx.gz`, `barcodes.tsv.gz`, `features.tsv.gz`: decompressed content identical (md5; 104,322 matrix lines for the current baseline) |
| `make_metacells_from_triplet_dge/tests/live.nf.test` | the baseline only | `MAKE_METACELLS_FROM_TRIPLET_DGE` on the baseline's `matrix.mtx.gz`, `features.tsv.gz`, `barcodes.tsv.gz` and `<analysis>.cell_metadata.txt`, grouped by `donor` and by `donor` + the column in `<analysis>.cell_type_column.txt` | `<analysis>.donors.metacells.txt.gz` and `<analysis>.donor_cell_type.metacells.txt.gz`, without the `#MakeMetacellsFromTripletDge` header line (it holds absolute paths); lines compared only to report a mismatch |
| `donor_cell_type_report/tests/live.nf.test` | the baseline only | `DONOR_CELL_TYPE_REPORT` on `<analysis>.cell_metadata.txt` with the column named in `<analysis>.cell_type_column.txt` (written by the prototype since 2026-10-16; remake an older baseline) | `<analysis>.donor_cell_type.txt` (md5, else line by line) |

The last three need no network or credentials, but they read files that only the baseline has (inputs in `tmp/` and per-library files), so they also need step 1.

**Not covered by live data yet:** the donor cell type report and the metacells (modules not written yet), and the per-library intermediates above.

**Run one live test by hand** (needs the baseline from step 1): pass one of the files above to `nf-test test`, for example

```bash
GOOGLE_PROJECT_ID=bican-um1-mccarroll nf-test test modules/local/summarize_scrna_experiments/tests/gcs.nf.test
```

(or any other file in the table). `nf-test test --tag live` runs all of them, `--tag gcs` only the two that read `gs://`. To select one of the two
MERGE_LIBRARY_METADATA tests, see below. See "Running one file or one test" for selecting tests inside a file.

`run_date` and `run_status` come from the newest Nextflow trace in the bucket, so a newer run of the library makes those two
columns differ from an older baseline.

Notes:

- A plain `nf-test test` also runs the live tests, which fail without the baseline and `GOOGLE_PROJECT_ID`. Use `tests/run_all_tests.sh`, or select by path
  (see "Running one file or one test").
- `nf-test.config` sets the default profile to `docker,test`: tools run in Docker with no extra flag. Fixture tests need no credentials.
- Test output goes to `.nf-test/`, which is git-ignored.

## Running one file or one test

`tests/run_all_tests.sh` always runs everything. To run less while developing, use nf-test directly:

| Goal | Command |
|---|---|
| one file | `nf-test test modules/local/resolve_aggregation_manifest/tests/main.nf.test` |
| one test | add the ID nf-test prints in brackets: `nf-test test modules/local/resolve_aggregation_manifest/tests/main.nf.test@14bbfafa` (the ID comes from the test name, so it changes if the test is renamed) |
| see what would run | add `--dry-run` to any command: it lists the tests without running them |

The live test files (`gcs.nf.test`, `live.nf.test`) need the baseline described under "Live tests".

## Test fixtures

Fixtures are tiny and synthetic. The `LOCATE_SCRNA_ARTIFACTS` tests use a fake library tree in
`modules/local/locate_scrna_artifacts/tests/fixtures/`, mounted at `/fixtures` in the container, so no credentials or
network are needed. Function tests (pre-flight) generate their files at test time under `outputDir`.

## Test catalog

Pre-flight credentials check, `subworkflows/local/utils_nfcore_scrna-aggregation_pipeline/tests/preflight.function.nf.test`
(tag `preflight`; function tests, fixtures written at test time). The docker profile must be in the profile string
for any check to run.

| Severity | Test |
|---|---|
| Critical | credentials file missing: fails, naming the path and the `gcloud auth application-default login` remedy |
| Critical | valid `authorized_user` JSON with a project ID passes |
| High | credentials path is a directory (what Docker creates for a missing mount source): fails |
| High | not valid JSON (empty file): fails |
| High | unsupported or missing `type`: fails, naming the type and the accepted ones |
| High | `authorized_user` missing a required field (`refresh_token`): fails |
| High | `authorized_user` with no project ID: fails, mentioning `GOOGLE_PROJECT_ID` |
| Medium | valid `service_account` JSON passes |
| Medium | `service_account` without a project ID passes (the key carries `project_id`) |
| Medium | check skipped without the `docker` profile |
| Medium | `docker` detected among several comma-separated profiles |
| Medium | `authorized_user` with a project ID passes |

`LOCATE_SCRNA_ARTIFACTS`, `modules/local/locate_scrna_artifacts/tests/` (fixtures described in `tests/fixtures/README.md`):

| File | Severity | Test |
|---|---|---|
| `main.nf.test` | Critical | one YAML per library in the manifest, named by uei, none lost or duplicated |
| `main.nf.test` | Critical | two DGEs of one experiment fail with `duplicate uei values` |
| `main.nf.test` | High | missing optional artifacts (mmc, village, trace, reduced GTF) are `NA`, not dropped; latest trace chosen; mmc keyed by model |
| `main.nf.test` | High | manifest donor carried into the YAML, `NA` when unset |
| `main.nf.test` | High | output equals the reviewed expected YAMLs, and every non-`NA` path exists in the fixture tree |
| `main.nf.test` | Medium | `meta.id` propagates; output is a directory named `artifacts` |
| `gcs.nf.test` | Critical | live: real `gs://` manifest with the mounted credentials gives correctly named YAMLs with `gs://` paths; prints the YAML paths; must equal the baseline field by field |

### RESOLVE_LIBRARIES (`modules/local/resolve_libraries/tests/main.nf.test`, 3 tests)
Input `tuple val(meta), val(artifact_texts)`, `val entries`, `val reference`, `val mmc_model`. Fixtures (`tests/fixtures/README.md`): `artifacts_one/` (LIB_A, village + MODEL1), `artifacts_two/` (LIB_A + LIB_B without village or MapMyCells), `artifacts_conflict/` (LIB_B with another reference). Tests: (1) header and one row with the village DGE, MapMyCells model and `NA` files; (2) two rows in manifest order (reverse of the file names), `NA` MapMyCells for the library without results, 8 columns each; (3) a reference mismatch fails the task and the reason is in the error output. Not selected: overrides (`--mmc_model`, `--reference`) and entry args/files in the row.

### RESOLVE_AGGREGATION_MANIFEST (`modules/local/resolve_aggregation_manifest/tests/main.nf.test`, 7 tests)
Fixtures are self-contained copies (not shared with LOCATE's tests): `artifacts/` (LIB_A village donor DGE + MODEL1,
LIB_B selected-cells DGE, no MMC), `artifacts_ref_mismatch/`, `artifacts_gtf_mismatch/`, `artifacts_two_models/`,
`manifest_two_libraries.yaml`, `manifest_with_filters.yaml`. `--reference` / `--mmc-model` are passed through
`task.ext.args`; tests set them with `reference_override.config` / `mmc_model.config` (per-test `config`).
1. libraries.tsv: one row per library, DGE choice (donor DGE over selected-cells), cell metadata, MMC columns, shared GTF, meta.
2. args files: one per library; donor, join and filter arguments, one per line; dgeDefaults filter used where a DGE has none.
3. empty args file for a library with nothing to apply.
4. references differ -> fails; 5. `--reference REF` overrides the check.
6. reduced GTFs differ -> fails.
7. `--mmc-model MODEL2`: echoed as `mmc_model` for every library; `mmc_annotations` is `NA` where the library lacks it.
Tool behavior learned: a DGE's own `filters` replace (do not merge with) `dgeDefaults` filters; the tool does not need the
fixture files to exist, only the artifact YAMLs; `artifact_file`/`args_file` columns are task-local paths.

### SUMMARIZE_SCRNA_EXPERIMENTS (`modules/local/summarize_scrna_experiments/tests/`)
`main.nf.test` (2 tests, fixtures in `tests/fixtures/`, self-contained: `LIB_FULL.yaml`, `LIB_NA.yaml` and small real files in
`data/LIB_FULL/`, mounted at `/fixtures`; the tool reads the files the YAML points at, it does not accept missing files):
1. one metrics row and one tearsheet named for the library, meta (id, analysis_id) propagated, fixed 48-column header,
   exact values from the fixture files (reads, % mapped, run status/date, chimeric %, doublet %, CBRB median UMIs, tearsheet rows).
2. every artifact NA: succeeds, every metric NA except library/reference/standard_analysis_dir, tearsheet has only the NA chimeric row.
`gcs.nf.test` (live; every `artifacts/<library>.yaml` of the baseline is run): each gives metrics identical to `artifacts/<library>.library_metrics.txt`
(all columns) and a tearsheet identical to `tearsheets/<library>.standard_analysis_tearsheet.txt`.

### MERGE_LIBRARY_METADATA (`modules/local/merge_library_metadata/tests/`)
Contract: `tuple val(meta), path(tsvs)` -> `combined` = `tuple val(meta), path('<ext.prefix ?: meta.id>.txt')`; `ext.args` carries
`--index-col PREFIX --index-col cell_barcode` for the cell metadata call. Fixtures (self-contained, `tests/fixtures/README.md`):
`lib_a.tsv`, `lib_b.tsv` (same barcode AAAA as lib_a, other PREFIX), `lib_c_extra_column.tsv`, `lib_a_duplicate_cell.tsv`.
`main.nf.test` (4 tests; the file-level config sets no `ext.args`, `index.config` sets the index columns for test 4):
1. two libraries: every row kept, input order, header unchanged, file named `<meta.id>.txt`, meta propagated.
2. column union: a file lacking a column gets empty values, other values not shifted.
3. one input passes through with identical content.
4. with `--index-col`, a duplicate (PREFIX, cell_barcode) fails with the tool's `Duplicate keys found`.
`live.nf.test` (2 tests, see Live tests): the merged `<analysis>.library_metrics.txt` (`live_library_metrics.config` sets `ext.prefix`) and
`<analysis>.cell_metadata.txt` (`live_cell_metadata.config` sets `ext.args` and `ext.prefix`, the planned workflow config) equal the baseline files.
Not implemented (candidates 5-7): `ext.prefix` override, same barcode with different PREFIX accepted under `--index-col`, stub.

### FORMAT_MAPMYCELLS_ANNOTATIONS (`modules/local/format_mapmycells_annotations/tests/`)
Contract: `tuple val(meta), path(csv)` (meta.id = library id) -> `converted` = `tuple val(meta), path('<ext.prefix ?: meta.id>.mmc.tsv')` and
`cell_type_column` = `tuple val(meta), val('<prefix><level>_name')` (the module reads the tool's one-line file itself; only the string leaves the task). The cell type column is the `_name` column of the chosen taxonomy level (default: the top level); all levels stay in the TSV.
`ext.args` carries `--column-prefix <model>_` and optionally `--level`. Fixture (`tests/fixtures/README.md`): `mmc_two_level.csv`
(3 `#` lines, hierarchy class > subclass, 3 cells). `main.nf.test` (4 tests; `prefix.config`, `subclass.config`, `bad_level.config` set `ext.args` per test):
1. `#` lines dropped, every column but `cell_id` prefixed, rows in order (the tool rewrites `0.9000` as `0.9`).
2. default level is the top of the hierarchy: `cell_type_column` is `M_class_name`, present in the header.
3. `--level subclass` gives `M_subclass_name`.
4. `--level nope` fails with the tool's `No M_nope_name column`.
No live test (a per-library intermediate; covered through the merged outputs that the live tests compare). Not implemented (candidates 5-8): meta/name check, no-prefix, `ext.prefix` override, stub.

### BUILD_LIBRARY_CELL_METADATA (`modules/local/build_library_cell_metadata/tests/`)
Wraps `join_and_filter_tsv`. Contract: `tuple val(meta), path(cell_metadata), path(mmc_tsv), path(args_file), path(extra_files)` (meta.id = library id;
`mmc_tsv` and `extra_files` are `[]` when absent; `args_file` is always a file) -> `cell_metadata` = `tuple val(meta), path('<ext.prefix ?: meta.id>.joined_filtered_cell_metadata.txt')`.
`PREFIX` (= meta.id) is the first column; the MapMyCells TSV is left-joined on `cell_barcode` = `cell_id` before the arguments file (the manifest's donor, joins and
filters, one argument per line, read with `--args-file`; an empty file for none), so filters can use its columns. Files named in the arguments file go in `extra_files` and are
named by their basename. There is no `ext.args`: the arguments file is the only source, and as a staged input it stays in the task directory (not published). Fixtures
(`tests/fixtures/README.md`): `cmd.tsv`, `mmc.tsv`, `extra.tsv`, `args_*.txt`. `main.nf.test` (6 tests):
1. `PREFIX` first, rows and columns otherwise unchanged, empty arguments file (the tool rewrites numbers: `0.20` -> `0.2`, so fixtures avoid trailing zeros).
2. MapMyCells left join: a cell without an annotation keeps its row with an empty value.
3. `--set donor N1`, `--max pct_mt 0.1` and `--exclude M_class_name GABA` (a joined column) from the arguments file applied.
4. a staged `extra.tsv` named in the arguments file is joined (an absent cell is kept, empty).
5. an argument with spaces, a dollar sign and a quote is applied exactly as written (one argument, not expanded or split).
6. no MapMyCells TSV: no MapMyCells columns.
No live test (a per-library intermediate; covered through the merged outputs that the live tests compare). Not implemented: duplicate join key fails (the tool tests it), meta/name check, `ext.prefix`, stub.

### MAKE_TRIPLET_DGE (`modules/local/make_triplet_dge/tests/`)
Wraps the Java `MakeTripletDge` (private image `${params.java_image}:${params.image_tag}`; the heap is 80% of `task.memory`). Contract:
`tuple val(meta), val(prefixes), path(dges), path(barcode_lists)` plus `path(reduced_gtf)` (the three lists have one element per library, in merge order;
the task writes the manifest as `manifest.yaml` in its work directory, for debugging, and passes it with `--MANIFEST`; it is not an output) -> `matrix`, `barcodes`, `features` = `tuple val(meta), path('matrix.mtx.gz' | 'barcodes.tsv.gz' | 'features.tsv.gz')`.
Barcodes are `<prefix>_<barcode>`. The tests use the local image `us.gcr.io/mccarroll-scrna-seq/drop-seq_private_java:jn_test`
(set in the test `nextflow.config` with a 2 GB `resourceLimits`; the production defaults are changed at the end of development).
Fixtures (`tests/fixtures/README.md`): `lib_a.dge.txt`, `lib_b.dge.txt`, `lib_a.cells.tsv`, `lib_b.cells.tsv`, `reduced.gtf`. `main.nf.test` (4 tests):
1. two libraries: prefixed barcodes in library order, the expected 7 matrix entries, fixed output names, meta propagated.
2. the barcode list filters cells (a cell in the DGE but not in the list is absent, its counts are not in the matrix).
3. features are `gene_id`, `gene_name`, `Gene Expression` in matrix row order, and the matrix header agrees with the features and barcodes.
4. the same prefix and barcode twice fails with the tool's `Output CBCs are not unique`.
`live.nf.test` (see Live tests): the sparse DGE equals the baseline's. Not implemented: a single library, `meta`/names alone, stub.

### DONOR_CELL_TYPE_REPORT (`modules/local/donor_cell_type_report/tests/`)
Wraps `donor_cell_type_report` (python image). Contract: `tuple val(meta), path(cell_metadata), val(cell_type_column)` (`meta.id` = analysis id; the
column name is FORMAT_MAPMYCELLS_ANNOTATIONS's `cell_type_column` value) -> `report` = `tuple val(meta), path('<ext.prefix ?: meta.id>.donor_cell_type.txt')`.
`ext.args` may set `--donor-column` / `--umi-column` (defaults `donor`, `num_retained_transcripts`). The workflow decides whether to call it (donor column and
cell type column present). Fixtures (`tests/fixtures/README.md`, expected values worked out there): `cell_metadata.tsv`,
`cell_metadata_missing_donor_or_cell_type.tsv`. `main.nf.test` (3 tests):
1. exact rows (counts, fractions rounded to 3 places, medians including an even-count median) in first-appearance order; meta and name.
2. cells with no donor are ignored; cells with no cell type count toward the donor's total only; a donor with only untyped cells has no row.
3. a cell type column not in the cell metadata fails with the tool's `No [...] column(s)`.
`live.nf.test` (see Live tests): the report on the baseline's `<analysis>.cell_metadata.txt` equals `<analysis>.donor_cell_type.txt`.
Not implemented: numeric-looking donor ids kept as text, `ext.args --umi-column`, stub.

### MAKE_METACELLS_FROM_TRIPLET_DGE (`modules/local/make_metacells_from_triplet_dge/tests/`)
Wraps `MakeMetacellsFromTripletDge` (private java image). Contract: `tuple val(meta), path(matrix), path(features), path(barcodes), path(cell_metadata),
val(group_columns)` (`meta.id` = analysis id; `group_columns` a list of column names of the merged cell metadata) -> `metacells` = `tuple val(meta),
path('<ext.prefix ?: meta.id>.metacells.txt.gz')`. The workflow includes it twice (donor; donor + cell type column) with `ext.prefix` `<analysis>.donors` /
`<analysis>.donor_cell_type`. The tool joins the cells as `<PREFIX>_<cell_barcode>` itself (defaults), and needs absolute paths (the module uses `$PWD`).
`ext.args` is free for extra tool arguments. Fixtures (`tests/fixtures/README.md`, expected sums worked out there): `matrix.mtx.gz`, `features.tsv.gz`,
`barcodes.tsv.gz`, `cell_metadata.tsv`. `main.nf.test` (5 tests):
1. donor sums, with the join by PREFIX and cell_barcode; meta and name.
2. donor and cell type sums, metacells named `donor:cell_type`.
3. cells with no metadata row or an empty donor are in no metacell.
4. the same barcode in two libraries stays separate, each with its own donor.
5. an unknown group column fails, with the column named in the tool's message.
`live.nf.test` (see Live tests): both outputs equal the baseline's, ignoring the header line.
Not implemented: `ext.prefix`, stub, row order of the output.

### Manifest parsing (`subworkflows/local/utils_nfcore_scrna-aggregation_pipeline/tests/manifest.function.nf.test`)
`lib/AggregationManifest.groovy` (pure Groovy; Nextflow loads `lib/` when the pipeline runs, and `nf-test.config` has `libDir = "tests/lib:lib"` so the tests call
the class directly) parses and validates the manifest YAML. `loadAggregationManifest(String path)` in the utils `main.nf` is the thin wrapper that reads the
file and turns errors into `error(...)`; it hosts the tests (each runs it once on `tests/live_data/manifest.yaml`). Contract: `parse(String yamlText)` returns one
map per DGE in manifest order, `[dge, donor, filters, joins]`, with `dgeDefaults` projected onto each entry; invalid manifests throw
`IllegalArgumentException` naming the DGE entry. Rules follow the original Zamboni workflow (`ScRnaAggregationManifestKey`, `YamlManifestUtil.projectDefaults`):
- Projection is deep (recursive): missing keys are copied, dictionaries merge key by key with the entry winning, default lists (joins) are used only
  when the entry has none. (The Python `resolve_aggregation_manifest` projects shallowly and also allows `donor` in `dgeDefaults` and the list form of
  `filters`; it goes away with the wiring.)
- Strict keys at every level (top level: `dges`, `dgeDefaults`; `dgeDefaults`: `filters`, `joins`; entry: `dge`, `donor`, `filters`, `joins`; no `libraryId`).
- `filters` is a dictionary keyed by column only; `min`/`max` numbers; `include`/`exclude` a value or a list (kept as parsed YAML scalars); `joins` a list or one
  dictionary with all of `joinFile`, `leftColumn`, `joinColumn`; duplicate YAML keys and duplicate DGEs are errors; no value may contain a line break (each
  argument is one line of the arguments file of `join_and_filter_tsv --args-file`).
Fixtures: `tests/fixtures/README.md` (a copy of the original workflow's own example manifest; the rest is inline YAML or the live manifests). 12 tests:
default projection (3: copy, merge per column and key, joins not appended), filter normalization, list form rejected, join order, join keys required,
structure/type errors (a table of 23 cases), duplicate DGEs, line breaks (9 cases), live manifests, the original's example manifest.
Not implemented: the wrapper's own tests (missing file message), `dges` as a single dictionary, scalar types preserved beyond the cases above.

### join_and_filter_tsv arguments (`subworkflows/local/utils_nfcore_scrna-aggregation_pipeline/tests/arguments.function.nf.test`)
`lib/JoinFilterArguments.groovy` (pure Groovy, tests call it directly; hosted on the `loadAggregationManifest` wrapper like the manifest tests).
`JoinFilterArguments.build(entry)` takes one entry of `AggregationManifest.parse` and returns `[args, files]`: the arguments of `join_and_filter_tsv` for the donor,
joins and filters, and the original paths of the files to stage (each once, in order of use). The arguments have the order and text of dropseq's
`resolve_aggregation_manifest.join_and_filter_args` (the expected list in test 1 is that function's output for the same filters and joins), with `--set donor`
first (as `resolve()` does) and file paths replaced by their staged base names; values use `toString` (Python wrote `True` where Groovy writes `true`; the tool reads
either; a small float may be `1.0E-4`). Empty `include`/`exclude` lists are skipped. Two different paths with one base name in an entry, or a path with no file name,
throw `IllegalArgumentException`; `loadAggregationManifest` calls the builder per entry so this fails at load, before any process.
`toArgsFileText(args)` is the arguments file: one argument per line (an empty file for none). 7 tests: the order against the Python resolver, empty entry / donor only /
empty lists, staging once with local and gs:// names, base name collisions, number/boolean/donor formatting, the file text, the collision reported at load.
Checked by hand (2026-10-16, rebuilt python image; not an automated test): the builder's arguments file for an entry with a donor, a join, `exclude`, `max`, `includeFile` and an
`include` with a space and a leading `@`, run through `join_and_filter_tsv --args-file`, gave output identical to the same arguments on the command line; an empty file works.
The BUILD module tests will cover it in the suite.

### Library resolver (`subworkflows/local/utils_nfcore_scrna-aggregation_pipeline/tests/resolver.function.nf.test`, `resolver.live.nf.test`)
`lib/LibraryResolver.groovy` replaces `resolve_aggregation_manifest` (data flow: `docs/data_flow.md`). `loadArtifact(yamlText)` parses one artifact file (one dataset with a `uei`
and a `user_dge`); `resolve(entries, artifacts, analysisId, [reference, mmcModel])` matches each manifest entry to the artifact whose `user_dge` equals its `dge` and returns
`[libraries: id -> [libraryId, dge, cellMetadata, mmcModel, mmcAnnotations, args, files] in manifest order, reducedGtf, reference]`; `summaryText(result)` is the content of
`<analysis>.resolved_libraries.tsv`. Rules: the donor DGE is preferred over the selected-cells one; the MapMyCells model is the override, else the library's first model (annotations
`NA` if it has none, which gates the conversion); the references (or the alignment directory names) and the reduced GTFs must agree unless a reference is given; ids unique and not the
analysis id; the donor comes from the manifest entry. New checks (not in the Python): the same `user_dge` in two artifacts; libraries with MapMyCells results of different models;
a staged file named like the cell metadata, `<lib>.mmc.tsv`, `<lib>.join_and_filter_args.txt` or `<lib>.joined_filtered_cell_metadata.txt`. Artifacts in the tests are built from the
fields the resolver reads (`fixtures/artifact_lib_a.yaml` is a real artifact file). 9 tests: records in manifest order (extra artifacts ignored), MapMyCells model choice, mixed models,
no artifact / no user_dge / duplicate user_dge, id rules, reference / GTF / missing DGE or metadata, staged name collisions, the artifact reader, the summary text.
`resolver.live.nf.test` (see Live tests): resolving `tests/live_data/manifest.yaml` with the baseline's `artifacts/*.yaml` gives the same library, DGE, cell metadata, model, annotations and
reduced GTF as `resolved_manifest/libraries.tsv`, and the same arguments text as its args file.
Not implemented: a test that the donor from the manifest is used for a village DGE too (not enforced, as in the Python), and the stub-free cases of `loadArtifact` beyond those listed.

### Pipeline (`tests/pipeline.validation.nf.test`, `tests/pipeline.live.nf.test`)
`conf/test.config` (profile `test`, used by every nf-test run) supplies `--manifest tests/live_data/manifest.yaml` and `--analysis_id SMRI_V11.unfiltered`. The pipeline needs
`--manifest`, `--analysis_id` and `--outdir` (schema: `analysis_id` has only letters, digits, `.`, `_`, `-`). `pipeline.validation.nf.test` (4 tests, no process starts):
no manifest, no analysis id, an analysis id with a slash, and a manifest with an unknown key (the message names the file, `dge entry 1` and the key).
`pipeline.live.nf.test` runs the whole pipeline ONCE on the live manifest and, only if it succeeded, compares each published file with the baseline (md5 of the
decompressed content; mismatching lines are printed). Each wired edge adds its comparisons. Wired so far: `LOCATE_SCRNA_ARTIFACTS` (`<outdir>/locate/artifacts/<uei>.yaml` equal to
the baseline's `artifacts/`) and `RESOLVE_LIBRARIES` (its `<analysis>.resolved_libraries.tsv` is found in the run's work directory, exactly one, and has the baseline `libraries.tsv`'s library_id, dge, cell_metadata, mmc_model, mmc_annotations and reduced_gtf; nothing of it is in `--outdir`). The template smoke test (`tests/default.nf.test`) and the samplesheet (`assets/samplesheet.csv`, `schema_input.json`) were removed.
