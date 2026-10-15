# mccarroll/scrna-aggregation: Testing

Tests use [nf-test](https://www.nf-test.com) (0.9.5). Run everything from the repository root. For the coding
conventions and known pitfalls, see [development.md](development.md).

## Test conventions

- Unit tests sit next to the unit, as in nf-core: `modules/local/<tool>/tests/main.nf.test`, with a `nextflow.config`
  and `fixtures/` beside it. Pipeline-level tests go in the top-level `tests/`.
- Test names start with `Should ...`.
- One test file per concern. Keep tests for different behavior in separate files next to each other, so a file stays
  readable and can be run alone. nf-test has no way for one file to include another; it discovers every `*.nf.test`
  under the path you give it.

## How to run the tests

| What | Needs | Command |
|---|---|---|
| Pre-flight credentials check (12 tests, `preflight.function.nf.test`) | nothing | `nf-test test subworkflows/local/utils_nfcore_scrna-aggregation_pipeline/` (all tests in the directory) |
| `LOCATE_SCRNA_ARTIFACTS`, fixture tests (6) | Docker and the `jn_test` image | `nf-test test modules/local/locate_scrna_artifacts/tests/main.nf.test` |
| `RESOLVE_AGGREGATION_MANIFEST`, fixture tests (7) | Docker and the `jn_test` image | `nf-test test modules/local/resolve_aggregation_manifest/tests/main.nf.test` |
| `SUMMARIZE_SCRNA_EXPERIMENTS`, fixture tests (2) | Docker and the `jn_test` image | `nf-test test modules/local/summarize_scrna_experiments/tests/main.nf.test` |
| Template pipeline smoke test (1, `tests/default.nf.test`; to be replaced when the workflow is wired) | Docker, `GOOGLE_PROJECT_ID` | `nf-test test tests/default.nf.test` |
| Everything: 30 tests today (12 pre-flight, 15 module fixture, 2 live, 1 pipeline) | Docker, network, ADC, `GOOGLE_PROJECT_ID`, the baseline | `tests/run_all_tests.sh`, see Live tests below |

## Live tests (real `gs://` data)

Live tests read real `gs://` artifacts and compare with the validated prototype output. They are tagged `gcs`.
Currently: `LOCATE_SCRNA_ARTIFACTS` (`locate_scrna_artifacts/tests/gcs.nf.test`) and `SUMMARIZE_SCRNA_EXPERIMENTS`
(`summarize_scrna_experiments/tests/gcs.nf.test`). Add each new live test to this list and give it the tag `gcs`.

**How the live tests and the baseline fit together.** The prototype shell script
(`docs/specifications/scrna-aggregation_prototype.sh`) reproduces the steps of the old Zamboni aggregation workflow, and
its outputs were validated against that workflow. Run it on a manifest to write the baseline into
`tests/live_data/baseline/` (git-ignored). The live tests then run the Nextflow modules on the same real `gs://` data
and compare their output with that baseline. Live tests are added module by module as the modules are implemented, so
today only the modules listed above are covered. A full integration test, comparing the published outputs of the whole
workflow with the baseline, comes last and will use the same runner. Fixture unit tests (`main.nf.test`) need neither
the script, the baseline nor the network.

Current limits, to revisit with the integration test: nothing checks that the baseline was made from the manifest given
to the runner (the baseline must come from the same manifest), and the `SUMMARIZE_SCRNA_EXPERIMENTS` live test compares
one library per run (set `SCRNA_LIVE_LIBRARY` when the baseline has several).

Prerequisites: Docker, network access, the `jn_test` images (see `TODO_STATUS.md`), and your Google Cloud Application
Default Credentials: run `gcloud auth application-default login`, which writes
`$HOME/.config/gcloud/application_default_credentials.json`. These are your own local Google Cloud credentials, and
the same file is used by both steps: step 1 (the shell script) mounts it into its containers, and the tests mount it
into theirs (`gcp_credentials_file` parameter). The shell script additionally copies `gs://` inputs on the host with
`gcloud storage cp`, which uses the gcloud CLI's own login (`gcloud auth login`), a separate credential that the
tests do not need.

**Step 1: make the baseline** with the prototype shell script, using the manifest in the repo
(`tests/live_data/manifest.yaml`, see `tests/live_data/README.md`). The baseline is the output of the prototype's
validated serial run of the same steps; the live tests compare the Nextflow modules with it. It goes into
`tests/live_data/baseline/`, which is git-ignored (nothing generated is committed). Run from the repo root, using the same
image tag as the modules (`jn_test` for local images):

```bash
docs/specifications/scrna-aggregation_prototype.sh --manifest tests/live_data/manifest.yaml \
    --analysis-id SMRI_V11.unfiltered --out-dir tests/live_data/baseline --image-tag jn_test
```

It needs the same prerequisites as above plus `gcloud` on the host (it copies `gs://` inputs with
`gcloud storage cp`) and about 340 MB of scratch space for the reduced GTF (in `tests/live_data/baseline/tmp`). This exact command has not yet
been rerun for this documentation: the existing baseline came from an earlier run of the same script and manifest.

**Step 2: run all the tests with one command**, with no options. It runs every nf-test (fixture, pre-flight and live) and
needs the baseline from step 1, the same Google Cloud credentials as step 1 (your gcloud Application Default
Credentials file, see Prerequisites), and the project ID in the environment:

```bash
export GOOGLE_PROJECT_ID=bican-um1-mccarroll
tests/run_all_tests.sh
```

The script stops with a clear message, before starting Docker, if the project ID, the Google Cloud credentials file, `nf-test` or
the baseline is missing. It sets `SCRNA_LIVE_MANIFEST` (`tests/live_data/manifest.yaml`) and `SCRNA_LIVE_BASELINE_ROOT`
(`tests/live_data/baseline`) itself and then runs `nf-test test`. The live tests print the generated and baseline file
paths, `matches baseline (49 fields)` (LOCATE), `Metrics: matches baseline (48 columns)` and
`Tearsheet: matches baseline (9 lines)` (SUMMARIZE), and every differing field with both values if one fails.

**Run one live test by hand** (the variables the script sets, exported by hand; `SCRNA_LIVE_LIBRARY` names the library
when the baseline has more than one):

```bash
GOOGLE_PROJECT_ID=bican-um1-mccarroll \
SCRNA_LIVE_MANIFEST=$PWD/tests/live_data/manifest.yaml SCRNA_LIVE_BASELINE_ROOT=$PWD/tests/live_data/baseline \
nf-test test modules/local/summarize_scrna_experiments/tests/gcs.nf.test
```

`LOCATE` needs `SCRNA_LIVE_MANIFEST`; `SCRNA_LIVE_BASELINE_ROOT` is optional there (without it no comparison is made).
`SUMMARIZE` needs only `SCRNA_LIVE_BASELINE_ROOT` (its input is `artifacts/<library>.yaml` from the baseline).
`run_date` and `run_status` come from the newest Nextflow trace in the bucket, so a newer pipeline run for the library
makes those two columns differ from an older baseline.

Notes:

- To run one file or one test, see "Running one file or one test" below.
- A plain `nf-test test` also runs the live tests, which fail unless `SCRNA_LIVE_MANIFEST` and
  `SCRNA_LIVE_BASELINE_ROOT` are set. Use `tests/run_all_tests.sh`, or select by path.
- `nf-test.config` sets the default profile to `docker,test`, so every test runs its tools in Docker with no extra flag.
  Fixture tests need no credentials (their own `nextflow.config` sets the container mounts); checked by running them with
  no `~/.config/gcloud` credentials file. Pass `--profile` to override, for example `--profile test` for no Docker.
- Test output goes to `.nf-test/`, which is git-ignored.

## Running one file or one test

`tests/run_all_tests.sh` always runs everything. To run less while developing, use nf-test directly:

| Goal | Command |
|---|---|
| one file | `nf-test test modules/local/resolve_aggregation_manifest/tests/main.nf.test` |
| one test | add the ID nf-test prints in brackets: `nf-test test modules/local/resolve_aggregation_manifest/tests/main.nf.test@14bbfafa` (the ID comes from the test name, so it changes if the test is renamed) |
| see what would run | add `--dry-run` to any command: it lists the tests without running them |

The live test files (`gcs.nf.test`) need the variables described under "Live tests". nf-test has no option to select a
test by a name substring. Tests are tagged (`tag "..."` in each file) and `--tag` selects by tag, but nothing in the
project relies on tags.

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
| `gcs.nf.test` | Critical | live: real `gs://` manifest with the mounted credentials gives correctly named YAMLs with `gs://` paths; prints the YAML paths; with `SCRNA_LIVE_BASELINE_ROOT`, must equal the baseline field by field |

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
`gcs.nf.test` (live): the baseline `artifacts/<library>.yaml` gives metrics identical to `artifacts/<library>.library_metrics.txt`
(all columns) and a tearsheet identical to `tearsheets/<library>.standard_analysis_tearsheet.txt`.
