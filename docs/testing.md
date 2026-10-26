# mccarroll/scrna-aggregation: Testing

Tests use [nf-test](https://www.nf-test.com) (0.9.5). Run everything from the repository root. For coding conventions and known pitfalls, see [development.md](development.md).

## Contents

- [Test conventions](#test-conventions)
- [How to run the tests](#how-to-run-the-tests)
- [Unit tests](#unit-tests)
- [Pipeline tests on synthetic libraries](#pipeline-tests-on-synthetic-libraries)
- [Live tests](#live-tests-real-data-compared-with-the-baseline)
- [Whole pipeline on Google Batch](#whole-pipeline-on-google-batch)

## Test conventions

- Unit tests sit next to the unit, as in nf-core: `modules/local/<tool>/tests/main.nf.test`, with a `nextflow.config` and `fixtures/` beside it (each fixture directory has a README). Pipeline-level tests go in the top-level `tests/`. Fixtures are tiny, synthetic and never shared between units.
- Test names start with `Should ...`.
- Typed processes (`nextflow.enable.types = true`) take `record(...)` inputs: nf-test rejects a plain Groovy Map there. A single output is a named record (`name = record(...)`), and a test reads `process.out.<name>[0].<field>`.
- One test file per unit (`main.nf.test`). A second file is used only when the tests serve different purposes, such as fixtures (`main.nf.test`) versus real data (`gcs.nf.test`). A test that needs another config (for example another `ext.args`) uses `config "./x.config"` inside its `test` block.

## How to run the tests

| What | Needs | Command |
|---|---|---|
| Unit tests of the Groovy code and pre-flight check (46) | nothing | `nf-test test subworkflows/local/utils_nfcore_scrna-aggregation_pipeline/` (the live resolver test in that directory also needs the baseline) |
| Unit tests of one module | Docker (the public images; `WRITE_TEXT_FILE` needs nothing) | `nf-test test modules/local/<module>/tests/main.nf.test` |
| Pipeline tests on synthetic libraries (9) | Docker only: no credentials, network or baseline | `nf-test test tests/pipeline.synthetic.nf.test` |
| Pipeline input validation and `--help` (6) | `GOOGLE_PROJECT_ID`; no containers start | `nf-test test tests/pipeline.validation.nf.test` |
| Live tests (12) | Docker, network, credentials, `GOOGLE_PROJECT_ID` and the baseline | `export GOOGLE_PROJECT_ID=bican-um1-mccarroll` once, then `nf-test test --tag live` (see [Live tests](#live-tests-real-data-compared-with-the-baseline)) |
| Whole pipeline on Google Batch (a script, not an nf-test; costs a little money) | `nextflow`, `gsutil`, Application Default Credentials, `GOOGLE_PROJECT_ID`, `GOOGLE_LOCATION` and the baseline | `tests/batch_full_run/run.sh` (see [Whole pipeline on Google Batch](#whole-pipeline-on-google-batch)) |
| Everything: 118 tests (the Google Batch script is not included) | the same as the live tests | `export GOOGLE_PROJECT_ID=bican-um1-mccarroll` once, then `tests/run_all_tests.sh` (checks the prerequisites first and stops at once with a clear message, for example "no baseline") |

To run less: add the ID nf-test prints in brackets to select one test (`...main.nf.test@14bbfafa`; the ID changes if the test is renamed), `--dry-run` to list what would run, or select by tag (`live`, `gcs`, `pipeline_synthetic`). A plain `nf-test test` also runs the live tests, which fail without the baseline, so use the script or select by path. `nf-test.config` sets the default profile to `docker,test`. Test output goes to `.nf-test/` (git-ignored).

## Unit tests

One line per unit; the fixtures and the exact assertions are in each unit's `tests/` directory.

| Unit (`tests/` next to it) | Tests | What they check |
|---|---|---|
| Pre-flight credentials check (`preflight.function.nf.test`) | 12 | fails before any process, naming the problem and the remedy, for a missing, unreadable, non-JSON, wrongly typed or incomplete credentials file, or no project ID; passes for valid `authorized_user` and `service_account` files; skipped without the `docker` profile |
| Manifest parsing (`manifest.function.nf.test`) | 14 | `dgeDefaults` are projected deeply onto each entry; unknown keys, bad types, duplicate DGEs and line breaks in values are rejected with a message naming the entry; every missing file the manifest names (and every file that cannot be checked) is reported at once, with its key and entries |
| `join_and_filter_tsv` arguments (`arguments.function.nf.test`) | 7 | donor, joins and filters become the right arguments in the right order (as the Python resolver writes them); files are staged once by base name; two files with one base name are rejected |
| Library resolver (`resolver.function.nf.test`) | 13 | each manifest entry is matched to its artifact; libraries are in manifest order; one reference, one reduced GTF and one MapMyCells model are enforced; all libraries have donors or none; cell type column and staged-name checks |
| `LOCATE_SCRNA_ARTIFACTS` | 6 | one artifact YAML per library; missing optional artifacts are `NA`; the latest trace is chosen; a duplicate experiment fails |
| `SUMMARIZE_SCRNA_EXPERIMENTS` | 2 | one metrics row and tearsheet per library with exact values; all-`NA` artifacts still succeed |
| `WRITE_TEXT_FILE` | 2 | the text is written byte for byte; empty text gives an empty file |
| `MERGE_LIBRARY_METADATA` | 4 | rows kept in input order; columns are united; with `--index-col`, a duplicate (`PREFIX`, `cell_barcode`) fails |
| `FORMAT_MAPMYCELLS_ANNOTATIONS` | 4 | columns are prefixed; the cell type column is the top taxonomy level or the one requested with `--level`; a bad level fails |
| `BUILD_LIBRARY_CELL_METADATA` | 6 | `PREFIX` first; the MapMyCells left join; donor, filters and an extra joined file from the arguments file; awkward argument values are applied as written |
| `BUILD_LIBRARY_H5AD` | 7 (6 and the live test) | cell names `<id>_<barcode>` in the cell metadata order with the bare barcode kept; counts of the DGE for the kept cells only; gene IDs from the reduced GTF with `gene_symbol`; missing values encoded; `CELL_BARCODE` with `--uppercase-column`; the fields the downstream reader requires (CSR `X`, plain string arrays, no `star_IsCell`); `id` and `h5ad/<id>.h5ad`. The h5ad is read with `aggregate_filter_adata` and `h5py` in the image, run with `docker` by the test |
| `MAKE_TRIPLET_DGE` | 4 | prefixed barcodes in library order; only the cells in each barcode list; features; a duplicate barcode fails |
| `DONOR_CELL_TYPE_REPORT` | 3 | counts, fractions and medians per donor and cell type; cells without a donor or cell type are handled as documented; a missing column fails |
| `MAKE_METACELLS_FROM_TRIPLET_DGE` | 5 | sums per donor, and per donor and cell type; unmatched cells are in no metacell; the same barcode in two libraries stays separate; an unknown column fails |
| Pipeline input validation and `--help` (`tests/pipeline.validation.nf.test`) | 6 | a missing manifest, a missing or unsafe analysis id and a manifest with an unknown key stop the run before any process; `--help` and `--help <parameter>` print the help |

## Pipeline tests on synthetic libraries

`tests/pipeline.synthetic.nf.test` (9 tests): the whole pipeline on tiny local libraries, with real processes in Docker. They check what the live manifest (one library, no filters or joins) cannot: several libraries, and the donor, filters and joins of the manifest reaching the merged outputs. They are independent of the other tests: no `gs://`, no network, no credentials and no baseline (a fake service account key passes the pre-flight check, so `GOOGLE_PROJECT_ID` is not needed). Run them alone:

```bash
nf-test test tests/pipeline.synthetic.nf.test        # or: nf-test test --tag pipeline_synthetic
```

**Data:** `tests/fixtures/synthetic/` (its `README.md` describes each library): six libraries in the layout the single-cell pipeline writes, one manifest per test, extra files for joins and filters, and a reduced GTF. Text files hold the token `@ROOT@` where an absolute path is needed. `SyntheticTree.materialize` (`tests/lib/SyntheticTree.groovy`) copies the tree to `.nf-test/synthetic_root` and fills in the path. `tests/synthetic.config` mounts that directory into the task containers at the same path, because the artifacts written by `LOCATE_SCRNA_ARTIFACTS` hold absolute paths that the head job reads on the host too.

**To audit a run:** the inputs are in `.nf-test/synthetic_root`; the outputs are in `.nf-test/tests/<test id>/` (`output/` published, `work/` every task directory, `meta/nextflow.log`). nf-test prints the test id. Every test uses `--analysis_id SYN`.

### Test 1 (the main test): apply each manifest entry's donor, filters and join to its own library's cells, and run the donor steps

**Risk:** a filter, donor or join from one manifest entry could be dropped or applied to the wrong library, silently keeping or losing cells.

**Setup** (`manifest_filters.yaml`): two libraries with MapMyCells results (model `MODEL1`, cell type column `MODEL1_class_name`), each with five cells. Each entry has its own donor and filters. A join of `files/extra.tsv` (columns `cell`, `extra_flag`) is set once in `dgeDefaults`, so both entries get it.

| Library | Donor | Filter | Cell removed and why |
|---|---|---|---|
| `LIB_MMC_1` | `N1` | `pct_mt` `min` 0.015 | `GGGG` (`pct_mt` 0.01) |
| | | `pct_mt` `max` 0.4 | `TTTT` (`pct_mt` 0.5) |
| | | `MODEL1_class_name` `include` Glut, Vip | `CCCC` (class GABA) |
| `LIB_MMC_2` | `N2` | `cell_barcode` `includeFile` (`AAAA`, `CCCC`, `GGGG`, `ACAC`) | `TTTT` (not listed) |
| | | `cell_barcode` `excludeFile` (`CCCC`) | `CCCC` |
| | | `MODEL1_class_name` `exclude` GABA | `GGGG` (class GABA) |

Each filter removes a different cell, so a filter that is not applied changes the result. The six filter types (`min`, `max`, `include`, `exclude`, `includeFile`, `excludeFile`) are each used once.

**Checks after one run** (expected values worked out by hand from the fixtures):
- The merged cell metadata has exactly four rows: `AAAA` and `ACAC` of `LIB_MMC_1` with donor `N1`, then of `LIB_MMC_2` with donor `N2`. Every row has `extra_flag` `yes` (from the join) and class `Glut`.
- The matrix has the same four cells (`barcodes.tsv.gz`, in that order) and 8 nonzero entries: a filtered-out cell must not leak into the counts. GENEA is 1, 3, 7, 9 and GENEC is 4, 6, 3, 5 for the four cells; GENEB is zero in all of them.
- The donor metacells hold the expression summed per donor: `N1` is `LIB_MMC_1` `AAAA` + `ACAC` (GENEA 1 + 3 = 4, GENEC 4 + 6 = 10) and `N2` is `LIB_MMC_2` (GENEA 7 + 9 = 16, GENEC 3 + 5 = 8). The donor by cell type metacells have the same sums under `N1:Glut` and `N2:Glut`.
- The donor cell type report has two cells per donor, all `Glut`, with median `num_retained_transcripts` 300 (median of 100 and 500) for `N1` and 30 (median of 10 and 50) for `N2`.

### Test 2 (guard): merge two libraries in manifest order, keeping each cell's metadata and counts with its own library

**Risk:** the pipeline merges several libraries into one cell table and one matrix. If it mixed up the libraries, it could pair one library's metadata with another's counts and nothing would fail. The merge must also follow the manifest's order.

**Setup** (`manifest_plain.yaml`): two libraries with no donors and no MapMyCells results, both with a cell `AAAA` that has different data. The manifest lists `LIB_PLAIN_2` first, the reverse of alphabetical order, so sorting by library name would be caught.

| Library | Cells | `num_transcripts` | Counts of `AAAA` (genes A, B, C) |
|---|---|---|---|
| `LIB_PLAIN_1` | `AAAA`, `CCCC`, `GGGG` | 100, 200, 300 | 1, 0, 4 |
| `LIB_PLAIN_2` | `AAAA`, `TTTT` | 50, 80 | 7, 0, 9 |

**Checks after one run:**
- The merged cell metadata lists `LIB_PLAIN_2` `AAAA`, `LIB_PLAIN_2` `TTTT`, `LIB_PLAIN_1` `AAAA`, `LIB_PLAIN_1` `CCCC`, `LIB_PLAIN_1` `GGGG`, each with its own library's `num_transcripts` (50, 80, 100, 200, 300).
- The library metrics have one row per library, in the same order.
- `barcodes.tsv.gz` lists the same five cells as `<library>_<barcode>`, in the same order, and every matrix entry has the right count (the first `AAAA` column holds 7 and 9, which are `LIB_PLAIN_2`'s counts).
- With no donors and no MapMyCells results, the pipeline logs "have no donors" and "No library has MapMyCells results", and publishes no donor or cell type file. This is the first time the no-MapMyCells path runs through the workflow.

**Not checked:** a different finishing order of the tasks. The test compares manifest order with alphabetical order only.

### Test 3 (guard): fail in MERGE_CELL_METADATA when a library lists the same cell barcode twice

**Risk:** a duplicated cell would silently be counted twice in the merged table.

**Setup** (`manifest_duplicate_cell.yaml`): `LIB_DUP` has `AAAA` twice in its cell metadata.

**Checks:** the run fails, and the failed task is `MERGE_CELL_METADATA` (its log says "Duplicate keys found"), not an earlier step.

### Tests 4 to 7: resolver errors, the cell type level and the MapMyCells model

These run the whole pipeline through the resolver and the cell type step, on `manifest_cell_type_levels.yaml` (`LIB_MMC_1` with donor `N1`, and `LIB_MMC_SUPER` with donor `N3`) and `manifest_mixed_donors.yaml`.

**Test 4 (guard): stop when the libraries have different cell type columns.**
- *Risk:* the libraries are merged into one table with one cell type column. If two libraries named it differently, the merged column would be wrong or half empty.
- *Setup:* the cell type column is the top level of each library's MapMyCells hierarchy. `LIB_MMC_1` has `class > subclass`, so its default column is `MODEL1_class_name`. `LIB_MMC_SUPER` has `supercluster > class`, so its default is `MODEL1_supercluster_name`.
- *Checks:* the run fails with "The libraries have different cell type columns", naming each library and its column, and no donor process runs.

**Test 5: `--mmc_level class` sets the cell type column, report and metacells.**
- *Risk:* a level given on the command line might not reach `FORMAT_MAPMYCELLS_ANNOTATIONS`, or might reach only some libraries.
- *Setup:* the same two libraries as test 4, run with `--mmc_level class`. Both now have `MODEL1_class_name`.
- *Checks:* The merged metadata has 7 cells (5 from `LIB_MMC_1`, 2 from `LIB_MMC_SUPER`), each with the class from its own library's result. The report has one row per donor and class (for example `N1` `Glut`: 3 cells, fraction 0.6, median 300; `N3` `GABA`: 1 cell, fraction 0.5, median 2000), and the metacells have one column per donor and class (`N1:GABA`, `N1:Glut`, `N1:Vip`, `N3:GABA`, `N3:Glut`).

**Test 6 (guard): stop at the resolver when only some libraries have donors.**
- *Risk:* a matrix with donors for only some libraries would give donor metacells that silently leave out cells.
- *Setup:* `LIB_MMC_1` has a donor in its manifest entry and `LIB_PLAIN_1` has none.
- *Checks:* the run fails with "Either all libraries have donors or none do", naming both libraries, before any SUMMARIZE, FORMAT or BUILD task runs.

**Test 7: `--mmc_model MODEL2` selects that model in every library.**
- *Risk:* by default each library uses its first MapMyCells model. If the override did not reach every library, the cell type columns would mix models.
- *Setup* (`manifest_mmc_model.yaml`): `LIB_MMC_1` and `LIB_MMC_2` each have two models: `MODEL1` (the first, classes Glut, GABA, Vip) and `MODEL2` (classes Neuron, Glia). The other tests use the default, so they exercise `MODEL1`.
- *Checks:* the merged metadata has no `MODEL1` column and each cell carries its own library's `MODEL2` class; the report has the exact counts, fractions and medians per donor and class (for example `N2` `Glia`: 2 cells, fraction 0.4, median 35).

**Not covered:** a different finishing order of the tasks (the merge order is the manifest order by construction, so it cannot depend on it) and default filters merged with entry filters through the workflow (Groovy tests only). There is no `--reference` parameter: libraries with different references always fail in the resolver.

## Live tests (real data compared with the baseline)

Live tests run a module on real data and compare the result with the **baseline**: the output of the validated prototype shell script (`docs/specifications/scrna-aggregation_prototype.sh`) on the same manifest. They are tagged `live`. They exist for the modules that read `gs://` (also tagged `gcs`) and for the modules that produce the merged files we publish. The per-library intermediate modules (`FORMAT_MAPMYCELLS_ANNOTATIONS`, `BUILD_LIBRARY_CELL_METADATA`) have fixture tests only: their outputs are covered through the merged files they feed, and by the whole-pipeline live test.

Every comparison hashes first: the md5 of the generated file's content (decompressed for `.gz`, streamed so large DGEs are cheap) against the baseline file's. Equal md5s pass and print `matches baseline (md5 ...)`; only on a mismatch are fields or lines compared, to print what differs (at most 10 lines). The helper is `tests/lib/LiveFiles.groovy`, loaded through `libDir` in `nf-test.config`. The live tests read fixed paths in the repo: the manifest `tests/live_data/manifest.yaml` and the baseline `tests/live_data/baseline/` (git-ignored, made by step 1).

**Prerequisites:** Docker, network access, the public `current` Drop-seq images (Docker pulls them), and your Google Cloud Application Default Credentials (`gcloud auth application-default login`, which writes `$HOME/.config/gcloud/application_default_credentials.json`). Step 1 (the shell script) mounts this file into its containers and the tests mount it into theirs (`gcp_credentials_file` parameter). The shell script also copies `gs://` inputs on the host with `gcloud storage cp`, which uses the gcloud CLI's own login (`gcloud auth login`); the tests do not need that.

### Step 1: make the baseline

Run the prototype shell script on the manifest in the repo (`tests/live_data/manifest.yaml`, see `tests/live_data/README.md`). The output goes into `tests/live_data/baseline/`, which is git-ignored. Run from the repo root with the same image tag as the modules (`current`). The baseline in use was made this way with the public images in session 13 (digests `f28d971a...` python, `e3230deb...` java); it is identical, file for file, to the earlier one made with local `jn_test` builds:

```bash
docs/specifications/scrna-aggregation_prototype.sh --manifest tests/live_data/manifest.yaml \
    --analysis-id SMRI_V11.unfiltered --out-dir tests/live_data/baseline --image-tag current
```

It needs the prerequisites above plus `gcloud` on the host, and about 340 MB of scratch space for the reduced GTF (in `tests/live_data/baseline/tmp`).

### Step 2: run the tests

Needs the baseline from step 1, the credentials above and the project ID. Export the project ID once:

```bash
export GOOGLE_PROJECT_ID=bican-um1-mccarroll
```

Then run either:

```bash
tests/run_all_tests.sh        # everything (118 tests); stops before starting Docker if the project ID, credentials file, nf-test or baseline is missing
nf-test test --tag live       # only the live tests (11), with no pre-checks
```

### What the live tests cover

One file per module, each running every library in the baseline:

| Test file | Needs | Runs | Compares with the baseline |
|---|---|---|---|
| `locate_scrna_artifacts/tests/gcs.nf.test` | network, ADC | `LOCATE_SCRNA_ARTIFACTS` on the manifest's real `gs://` DGEs | each `artifacts/<library>.yaml` |
| `summarize_scrna_experiments/tests/gcs.nf.test` | network, ADC | `SUMMARIZE_SCRNA_EXPERIMENTS` on every `artifacts/<library>.yaml` | `artifacts/<library>.library_metrics.txt` and `tearsheets/<library>.standard_analysis_tearsheet.txt` |
| `merge_library_metadata/tests/live.nf.test` (2 tests) | baseline | `MERGE_LIBRARY_METADATA` on the per-library metrics, and on the per-library cell metadata with `--index-col PREFIX --index-col cell_barcode` | `<analysis>.library_metrics.txt` and `<analysis>.cell_metadata.txt` |
| `build_library_h5ad/tests/live.nf.test` | baseline | `BUILD_LIBRARY_H5AD` (with the pipeline's default `--uppercase-column cell_barcode`) on the baseline's local DGE (`tmp/<library>/`), `<library>.joined_filtered_cell_metadata.txt` and the reduced GTF in `tmp/` | `h5ad/<library>.h5ad`, by md5 of the bytes (the file is binary; the md5 holds while the image's python libraries do, so after an image update check the content with `aggregate_filter_adata --view_columns` and `--view_values` before remaking the baseline) |
| `make_triplet_dge/tests/live.nf.test` | baseline | `MAKE_TRIPLET_DGE` on the baseline's local DGE copies (`tmp/<library>/`) and `<library>.joined_filtered_cell_metadata.txt` barcode lists | `matrix.mtx.gz`, `barcodes.tsv.gz`, `features.tsv.gz` (decompressed content; 104,322 matrix lines for the current baseline) |
| `make_metacells_from_triplet_dge/tests/live.nf.test` | baseline | `MAKE_METACELLS_FROM_TRIPLET_DGE` on the baseline's matrix, features, barcodes and `<analysis>.cell_metadata.txt`, grouped by `donor` and by `donor` + the column in `<analysis>.cell_type_column.txt` | `<analysis>.donors.metacells.txt.gz` and `<analysis>.donor_cell_type.metacells.txt.gz`, without the `#MakeMetacellsFromTripletDge` header line (it holds absolute paths) |
| `donor_cell_type_report/tests/live.nf.test` | baseline | `DONOR_CELL_TYPE_REPORT` on `<analysis>.cell_metadata.txt` with the column named in the baseline's `<analysis>.cell_type_column.txt` (written by the prototype since 2026-10-16: remake an older baseline; the pipeline itself no longer publishes this file) | `<analysis>.donor_cell_type.txt` |

The last five need no network or credentials, but they read files that only the baseline has, so they also need step 1. `run_date` and `run_status` come from the newest Nextflow trace in the bucket, so a newer run of a library makes those two columns differ from an older baseline.

To run one live test by hand, pass its file to `nf-test test`, for example:

```bash
GOOGLE_PROJECT_ID=bican-um1-mccarroll nf-test test modules/local/summarize_scrna_experiments/tests/gcs.nf.test
```

### Whole-pipeline live test

`tests/pipeline.live.nf.test` (2 tests) runs the whole pipeline once on the live manifest and, only if it succeeded, compares each published file with the baseline (md5 of the decompressed content; mismatching lines are printed).
- The top level of `--outdir` has exactly the merged results, `artifacts/`, `tearsheets/`, `h5ad/` and `pipeline_info/`.
- Every merged result equals the baseline's (the metacell files without their `#MakeMetacellsFromTripletDge` line), as do `artifacts/<uei>.yaml` and `tearsheets/`; `h5ad/<uei>.h5ad` has the baseline's md5.
- The per-library intermediates in the run's work directory (library metrics, joined cell metadata, arguments file, MapMyCells TSV) are correct.
- `pipeline_info/<analysis>.resolved_libraries.txt` names the right DGE, cell metadata, model, annotations and reduced GTF, and `Donors: yes`.
- A second test sets `--analysis_id` to the library id and expects the run to stop with the resolver's message before SUMMARIZE, FORMAT or BUILD run.

## Whole pipeline on Google Batch

`tests/batch_full_run/run.sh` runs the whole pipeline on the live manifest (`tests/live_data/manifest.yaml`, analysis id `SMRI_V11.unfiltered`) with `-profile googlebatch`, and checks the result. It is a script and not an nf-test, because nf-test always passes a local `-work-dir` and Google Batch needs a `gs://` one. It is not part of `tests/run_all_tests.sh`. Background on the identities, projects and network: [credentials.md](credentials.md).

### Before you run it

- Application Default Credentials (`gcloud auth application-default login`), `nextflow`, `gsutil`, and the baseline in `tests/live_data/baseline` (see [Live tests](#live-tests-real-data-compared-with-the-baseline), step 1).
- The project must own the data and be able to write the work bucket. The live data is in `mccarroll-scrna-seq`.
- Both variables are required by the `googlebatch` profile (an unset one gives a null project, region or network):

```bash
export GOOGLE_PROJECT_ID=mccarroll-scrna-seq
export GOOGLE_LOCATION=us-central1
```

### Run it

```bash
tests/batch_full_run/run.sh [gs://<bucket>/<path>]
# default base: gs://mccarroll_scrnaseq_central_temp/nextflow/aggregation_testing
```

The script uses `<base>/work` as the work directory and `<base>/out` as `--outdir`. It first deletes `<base>/out` so that stale files cannot pass, then runs Nextflow, downloads `<base>/out` to `testing_batch_full_run/out`, and checks. It leaves `work` and `out` in the bucket (delete them when done). The run takes a few minutes, showing Nextflow's colored progress display (`-ansi-log true`, kept even though the script gives Nextflow no terminal) and then the checks. The script reads nothing from the terminal, so it can also be run in the background (`... &`) from an interactive shell. The `testing_batch_full_run/` directory is git-ignored; it holds the downloaded output, `nextflow.log`, and the trace (with `peak_rss`, written locally by `tests/batch_full_run/trace.config`).

### What it checks (each prints PASS or FAIL; the exit status is the number of failures, 1 if the run itself failed, 2 if a prerequisite is missing)

1. Each of the eight merged files equals the baseline (md5 of the decompressed content; the metacell files without their `#MakeMetacellsFromTripletDge` line). `artifacts/` and `tearsheets/` are not compared here (the nf-test live test does that locally).
2. The top level of `--outdir` is exactly the merged files, `artifacts/`, `tearsheets/`, `h5ad/` and `pipeline_info/`; each `h5ad/<library>.h5ad` has the md5 of the baseline's.
3. The `WRITE_*` exec processes ran in the head job (`native_id` is `-` in the trace) and every other task was submitted to Google Batch.
4. Every task is `COMPLETED`, and every Google Batch task ran in a public `quay.io/broadinstitute/drop-seq_python` or `drop-seq_java` image.

It then prints one line per task: the requested memory, `peak_rss` and `realtime`, to tune the memory in `conf/modules.config`.

### Last result (2026-10-21, `mccarroll-scrna-seq`, `us-central1`, with the exact machine types)

All 12 checks passed on the session 13 code, before the h5ad check was added (the 8 merged files equal the baseline, the top-level listing, `WRITE_*` in the head job, every task `COMPLETED` in the public images). The log had no Cloud Info deprecation warning and no "cannot be executed by 'google-batch' executor" warning. The Google Batch jobs used `n1-standard-2` for the default processes and `n1-standard-8` for the three Java steps (read back with `gcloud batch jobs describe`). Peak memory was 611 MB for `MAKE_TRIPLET_DGE`, about 130 MB for the metacell steps and under 200 MB for the others (requests: 15 GB for the Java steps, 6 GB for the rest), and each task ran for 2 to 9 seconds.

### Things that can go wrong

- `Missing Google project Id`: `GOOGLE_PROJECT_ID` is not exported. (Earlier, an nf-core institutional `googlebatch` profile overrode ours; the institutional configs are no longer loaded.)
- `CODE_GCE_RESOURCE_NOT_FOUND ... networks/default`: the profile sets the `broad-allow` network from `GOOGLE_PROJECT_ID`; check that the project has it.
- `Permission denied` or `403` on a bucket: the project in `GOOGLE_PROJECT_ID` cannot reach that bucket (see credentials.md, "The project must have access to the bucket where the data lives").
