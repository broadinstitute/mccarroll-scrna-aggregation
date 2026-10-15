# TODO / status (update as you go)

Last updated: 2026-10-15 (end of session 1).
Done and tested: pre-flight credentials check, LOCATE_SCRNA_ARTIFACTS, RESOLVE_AGGREGATION_MANIFEST,
SUMMARIZE_SCRNA_EXPERIMENTS, the test suite runner, and the template's hyphenated-name fix. The full suite is green:
`GOOGLE_PROJECT_ID=bican-um1-mccarroll tests/run_all_tests.sh` ran 30 tests in ~133 s (needs a baseline, see below).
**Resume point: CAT_TSVS (order 4).** Start with the clarification questions below ("Next: CAT_TSVS"), then the data
contract, then stop for the user's test selection (the user usually answers "recommended").
Companion docs: `SPEC_SUMMARY.md` (behavior of the prototype), `../credentials.md` (users: credentials, env vars),
`../testing.md` (how to run every test, live tests, fixtures, test catalog), `../development.md` (conventions, gotchas).

## Ground rules (from the user)
- Spec/source of truth: `scrna-aggregation_prototype.sh` (this directory); see `SPEC_SUMMARY.md`.
- Modules + nf-test unit tests FIRST, leaf-first, one at a time, on small fixtures. Unit tests live next to the module
  (`modules/local/<tool>/tests/`, nf-core style). Separate test files per concern (nf-test cannot include test files).
- Then ONE workflow wiring tested modules, one edge at a time. NO subworkflows (the template's init subworkflow stays).
- Process per unit: clarification questions (two options each) -> data contract -> severity-ranked candidate tests ->
  STOP for the user's selection -> nf-test generate -> tests -> implement -> run targeted tests.
- Containers: registry/name and tag are parameters (`jn_test` locally; production images later). No local-only hardcoding.
- Do not commit/push unless asked. Do not touch `/Users/nemesh/nextflow_aggregation_shell_script/out` (reading it as a
  baseline is fine); any prototype rerun uses a different out/tmp dir.
- Keep `docs/credentials.md`, `docs/testing.md` and `docs/development.md` updated whenever modules, tests, params or env vars change.
- Favor clarity and testability over fewer lines/steps. Keep the test suite simple: `tests/run_all_tests.sh` has no options
  and always runs everything; running a subset is done with plain `nf-test` commands documented in docs/testing.md.
- The baseline shell script is a separate manual step from the Nextflow tests (the runner never runs it).
- Live tests are as valuable as fixture tests (the user said the live ones are "by far the more useful"): give each module a
  live test against the baseline where the baseline has the expected output.
- Fixtures are self-contained per module: never share test data between two modules' tests.
- Do not run long commands in the foreground (120 s limit); use run_in_background and wait for the notification.

## Environment
- nextflow 26.10.0, nf-test 0.9.5, docker. `nf-test.config` default profile is `docker,test` (no `--profile` flag needed). Local images (all linux/amd64):
  `quay.io/broadinstitute/drop-seq_python:jn_test`, `quay.io/broadinstitute/drop-seq_java:jn_test`,
  `us.gcr.io/mccarroll-scrna-seq/drop-seq_private_java:jn_test` (the prototype's Java image), plus private_python/r.
- Real data: manifests are in the repo (`tests/live_data/manifest.yaml`, `manifest_no_donors.yaml`); the baseline is made by
  running the prototype script on them (docs/testing.md, "Live tests"). The original validated run is in
  `$D=/Users/nemesh/nextflow_aggregation_shell_script` (same manifests); validated prototype output in `$D/out` (e.g. `out/artifacts/SMRI_V11_rxn1.yaml`, `out/resolved_manifest/`).
- Local gcloud project ID for `GOOGLE_PROJECT_ID`: `bican-um1-mccarroll`. Not secret; it is in the docs.
- `nextflow lint .` reports no errors (the template's hyphenated `SCRNA-AGGREGATION` names were renamed to `SCRNA_AGGREGATION`
  in `main.nf` and `workflows/scrna-aggregation.nf`; some unused-parameter warnings from the template remain).
- `tests/default.nf.test` and `conf/test.config` are still the template's. The pipeline test passes as a smoke test of the (still
  empty) template workflow; its snapshot (`tests/default.nf.test.snap`: file names only) was regenerated on 2026-10-15 and
  must be replaced by a manifest-driven integration test when the workflow is wired. It needs `GOOGLE_PROJECT_ID` (pre-flight check).
- Nothing is committed (all changes since the template commit are uncommitted; `.nf-test/` is now in `.gitignore`).

## How to run the tests (details in docs/testing.md)
```bash
cd /Users/nemesh/mccarroll-scrna-aggregation
# 1. baseline (separate manual step; git-ignored output; needs gcloud, docker, network; not yet rerun by us, see Open questions)
docs/specifications/scrna-aggregation_prototype.sh --manifest tests/live_data/manifest.yaml \
    --analysis-id SMRI_V11.unfiltered --out-dir tests/live_data/baseline --image-tag jn_test
# 2. everything (30 tests today: 12 pre-flight, 15 module fixture, 2 live, 1 template pipeline smoke test)
export GOOGLE_PROJECT_ID=bican-um1-mccarroll
tests/run_all_tests.sh
# one file / one test (see docs/testing.md; live files need SCRNA_LIVE_MANIFEST and SCRNA_LIVE_BASELINE_ROOT)
nf-test test modules/local/resolve_aggregation_manifest/tests/main.nf.test
nf-test test modules/local/resolve_aggregation_manifest/tests/main.nf.test@14bbfafa
```
Until the baseline is regenerated in the repo, the old validated one works through a temporary symlink:
`ln -s /Users/nemesh/nextflow_aggregation_shell_script/out tests/live_data/baseline` (remove it afterwards).
A plain `nf-test test` also runs the live tests, which fail unless `SCRNA_LIVE_MANIFEST` and `SCRNA_LIVE_BASELINE_ROOT` are set.

## Implementation order (updated; follows the data flow of the prototype)
Local modules under `modules/local/<tool>/main.nf` (no suitable nf-core module exists for these tools).
The order below is proposed from the prototype's steps; the user chose LOCATE first, the rest is not yet confirmed.
| Order | Module (prototype step) | Container | Unit test approach | Status |
|---:|---|---|---|---|
| 1 | LOCATE_SCRNA_ARTIFACTS (1a) | python | local fixtures + live gs:// test | DONE: 6 fixture tests + 1 live test pass |
| 2 | RESOLVE_AGGREGATION_MANIFEST (1b) | python | own copies of artifacts YAML fixtures (self-contained); no live test yet | DONE: 7 fixture tests pass (own fixtures) |
| 3 | SUMMARIZE_SCRNA_EXPERIMENTS (2a), per library | python | own fixture tree with small real files (the tool reads the files the YAML points at) + live gs:// test | DONE: 2 fixture tests + 1 live test (matches baseline) |
| 4 | CAT_TSVS (2b library metrics, and 6 cell metadata with --index-col) | python | gs-free fixtures + a live test on the baseline (`<analysis>.library_metrics.txt`, `<analysis>.cell_metadata.txt`); candidates below | NEXT |
| 5 | CONVERT_MMC_CSV (3b), only if mmc_annotations != NA | python | gs-free | not started |
| 6 | JOIN_AND_FILTER_TSV (3d), per library | python | gs-free | not started |
| 7 | MAKE_TRIPLET_DGE (4+5; generates the triplet manifest inside the task) | java | tiny DGE + tiny GTF | not started |
| 8 | DONOR_CELL_TYPE_REPORT (7) | python | gs-free | not started |
| 9 | MAKE_METACELLS_FROM_TRIPLET_DGE (8, 9; GROUP_COLUMNS as params) | java | tiny triplet DGE | not started |
Then: `workflows/scrna-aggregation.nf`, wired one edge at a time (replace the template's samplesheet input with the
manifest + `analysis_id` params; replace the template's `tests/default.nf.test` and snapshot), plus an integration test
comparing the published outputs with the baseline (this will also need: the baseline-vs-manifest consistency check and
multi-library handling in the live tests, see docs/testing.md "Current limits").

## Done so far
1. **Pre-flight credentials check** (`checkLocalGcpCredentials(profile, credentialsFile, projectId)` in
   `subworkflows/local/utils_nfcore_scrna-aggregation_pipeline/main.nf`, called first in `PIPELINE_INITIALISATION`).
   Only active with the `docker` profile. Fails before any process if: the credentials path is missing or a directory;
   the file is not valid JSON; `type` is not `authorized_user`/`service_account`; required fields are missing;
   or it is an `authorized_user` file and `GOOGLE_PROJECT_ID` is unset. 12 tests in `tests/preflight.function.nf.test`
   (tag `preflight`). No network call is made; real acceptance by Google is shown by the first gs:// reading task.
2. **Profiles/params** (`nextflow.config`, `nextflow_schema.json`):
   - `docker` profile (now also the nf-test default, with `test`): runs `-u $(id -u):$(id -g) --platform=linux/amd64` (the old `emulate_amd64` profile was removed),
     mounts `params.gcp_credentials_file` read-only at `/opt/gcp/adc.json`, sets `GOOGLE_APPLICATION_CREDENTIALS` and
     `GOOGLE_CLOUD_PROJECT` (from `$GOOGLE_PROJECT_ID`).
   - `googlebatch` profile: STUB only (executor google-batch; project/location from `GOOGLE_PROJECT_ID`/`GOOGLE_LOCATION`).
     Settings deferred: service account email (`google.batch.serviceAccountEmail`), gs:// work dir bucket.
   - New params: `gcp_credentials_file` (default `$HOME/.config/gcloud/application_default_credentials.json`; on a
     cluster point it at a service account key JSON), `python_image` (`quay.io/broadinstitute/drop-seq_python`), `image_tag` (`jn_test`).
     A Java image param is still needed with the Java modules.
3. **LOCATE_SCRNA_ARTIFACTS** (`modules/local/locate_scrna_artifacts/`):
   `tuple val(meta), path(manifest)` -> `tuple val(meta), path('artifacts')` as `artifacts_dir` (one `<uei>.yaml` per
   library; the workflow scans the directory to fan out). `meta.id` = analysis id. No `versions` emit yet.
   Tests (`tests/`): `main.nf.test` (synthetic fixture tree mounted at `/fixtures`, no credentials: one YAML per library,
   duplicate-uei failure, NA for missing artifacts, donor carried, meta/dir shape, exact expected YAML + every path exists),
   `gcs.nf.test` (live gs:// with the real ADC mount; prints the generated YAML paths; optional `SCRNA_LIVE_BASELINE_ROOT` (the prototype out dir; replaces the old `SCRNA_LIVE_BASELINE_DIR`)
   compares field by field and printed 'matches baseline (49 fields)' against the prototype output).
   The tool also accepts local paths (`dropseq.util.storage`: GcsStore for gs://, LocalStore otherwise).

4. **RESOLVE_AGGREGATION_MANIFEST** (`modules/local/resolve_aggregation_manifest/`):
   `tuple val(meta), path(manifest), path(artifacts_dir)` -> `libraries_tsv` (`tuple val(meta), path('resolved/libraries.tsv')`)
   and `args_files` (`tuple val(meta), path('resolved/*.join_and_filter_args.txt')`). `meta.id` = analysis id.
   Optional `--reference`/`--mmc-model` via `task.ext.args`. The workflow must ignore the `artifact_file`/`args_file` columns
   (task-local absolute paths) and join by `library_id` (artifact YAML = `artifacts/<library_id>.yaml`).
   TODO when wiring: add `params.reference`/`params.mmc_model` (schema) and set `ext.args` in `conf/modules.config`.
   No `versions` emit (decision: decide once for all modules when wiring the workflow).

5. **SUMMARIZE_SCRNA_EXPERIMENTS** (`modules/local/summarize_scrna_experiments/`):
   `tuple val(meta), path(artifacts_yaml)` with `meta = [id: <library_id>, analysis_id: <analysis id>]` ->
   `metrics` (`<id>.library_metrics.txt`, header + one row, 48 columns) and `tearsheet`
   (`tearsheets/<id>.standard_analysis_tearsheet.txt`). Tests: 2 fixture tests (own fixtures) + live `gcs.nf.test`.
   The tool reads the files the artifact YAML points at (even local ones), so fixtures contain small real files.
6. **Test suite runner** `tests/run_all_tests.sh`: no options; checks `GOOGLE_PROJECT_ID`, the credentials file, `nf-test` and
   the baseline, then runs a plain `nf-test test` (all tests, including the live ones). Live tests use
   `SCRNA_LIVE_MANIFEST` (default `tests/live_data/manifest.yaml`) and `SCRNA_LIVE_BASELINE_ROOT`
   (`tests/live_data/baseline`, git-ignored; LOCATE's live test was changed from `SCRNA_LIVE_BASELINE_DIR`).
   Live inputs live in the repo: `tests/live_data/` (manifests + README).
7. **Template fixes**: workflow/include names renamed `SCRNA-AGGREGATION` -> `SCRNA_AGGREGATION` (`main.nf`,
   `workflows/scrna-aggregation.nf`); `nextflow lint .` is clean; `tests/default.nf.test.snap` regenerated (file names only).
8. **Docs split**: `docs/testing.md` (running tests, live tests, fixtures, test catalog) and `docs/development.md` (conventions,
   gotchas); `docs/README.md` links both.

## Decisions made
- Design principle: favor clarity and testability over fewer lines/steps. RESOLVE_AGGREGATION_MANIFEST stays as a tested
  Python tool/module (its help calls it a stand-in that "goes away with" the Nextflow workflow, but reimplementing manifest
  parsing, filters/joins and cross-library checks in Groovy was judged less clear and harder to test). Keep LOCATE and
  RESOLVE as separate modules (RESOLVE tests need no credentials). The workflow does one fan-out (splitCsv of
  libraries.tsv joined to the args files by library_id); no merging of per-library tasks.
- LOCATE_SCRNA_ARTIFACTS is the first module (architectural spike for credentials) and emits a directory.
- Q2 gs:// access: containers get credentials by mounting a credentials JSON (own `gcloud auth application-default login`
  locally; service account key file on the cluster; platform-provided service account on Batch/Seqera). Project ID via
  `GOOGLE_PROJECT_ID` env var; the pipeline has no default project (user exports it).
- Q3 test data: small committed synthetic fixtures beside each module (`tests/fixtures/`), plus a live test against the
  real data where gs:// is involved. Real baselines come from the validated prototype output.
- Q6 docker platform: folded into the `docker` profile (no separate emulation profile).
- Unit tests next to modules; one test file per concern; pre-flight tests all in one file.
- Project ID `bican-um1-mccarroll` is not a secret and appears in docs.
- Assumed, not explicitly confirmed: one local module per tool (Q4).
- Meta convention: run-level modules (LOCATE, RESOLVE) use `meta.id` = analysis id; per-library modules (SUMMARIZE onward)
  use `meta = [id: <library_id>, analysis_id: <analysis id>]`. Optional tool arguments come from `task.ext.args` (set from
  params in `conf/modules.config` when wiring). Named emits, one file per emit where possible.
- No `versions` emit yet in any module; decide once for all modules when wiring the workflow.
- Q5 (hyphenated names) fixed by renaming; the template's pipeline test is kept as a smoke test (snapshot regenerated) until
  the workflow is wired. nf-test default profile is `docker,test` (verified fixture tests need no credentials).
- The baseline is generated by the prototype script into `tests/live_data/baseline` (git-ignored), run as its own step.

## Open questions / pending
- The prototype script has NOT been rerun into `tests/live_data/baseline` (the live tests were verified against the old
  validated baseline via a symlink). The documented command comes from the script's usage text. Run it once (output only
  into the repo baseline dir, never `$D/out`) to confirm it, including its Docker mounts for a path inside the repo.
- `googlebatch` settings (service account email, work bucket, location) deferred by the user.
- `versions` emit/topic convention for local modules (see Decisions).
- When wiring: `params.reference`/`params.mmc_model` (schema + `ext.args`), a Java image param, the baseline-vs-manifest
  consistency check, multi-library live tests, a `workflows` pipeline test with the credentials pre-flight (needs
  `GOOGLE_PROJECT_ID`).
- Real service-account key not yet tried (mechanism is the same mount; documented as untested).
- Whether the Google client falls back to a service-account key's `project_id` when `GOOGLE_CLOUD_PROJECT` is empty is untested.
- `docker.registry = 'quay.io'` in `nextflow.config`: review before using the `us.gcr.io` Java image or GCP.
- `tests/default.nf.test.snap` is untracked and `tests/default.nf.test` still the template's (see Done 7).
- Unselected candidate tests to maybe add later: RESOLVE (library id equals analysis id, DGE with no artifact, dgeDefaults
  projection, stub); SUMMARIZE (malformed YAML, newest-trace selection, stub).

## Next: CAT_TSVS (module 4). Clarification questions to ask first (two options each, existing support listed first)
1. Input shape: `tuple val(meta), path(files)` (meta.id = analysis id; the workflow gathers per-library files with
   `collect`/`groupTuple`, sorted by library for stable order) vs a plain list. Check the tool's `--help` first
   (`cat_tsvs --output X [--index-col C ...] files...`).
2. How `--index-col PREFIX --index-col cell_barcode` is passed: `task.ext.args` (matches LOCATE/RESOLVE/SUMMARIZE) vs a
   module input.
3. Output name: from `task.ext.prefix`/`meta.id` (`<analysis_id>.library_metrics.txt`, `<analysis_id>.cell_metadata.txt`)
   vs fixed names; one module reused for both uses with different `ext.args`/`ext.prefix` per call.
4. Test data: self-contained tiny TSVs (own fixtures) plus a live test on the baseline: baseline library files
   (`artifacts/<lib>.library_metrics.txt`, `<lib>.joined_filtered_cell_metadata.txt`) as input and
   `<analysis>.library_metrics.txt` / `<analysis>.cell_metadata.txt` as expected output. Baseline has one library, so the
   live test is the single-file pass-through (candidate 4); the multi-library cases need synthetic fixtures.

## Candidate tests for CAT_TSVS (module 4; awaiting user selection when we get there)
Fixture idea: tiny per-library TSVs sliced from the real `joined_filtered_cell_metadata.txt` (first ~5 rows, subset of
columns) plus a second synthetic "library" copy with a different PREFIX and an extra column.
| # | Severity | Behavior | Why |
|---:|---|---|---|
| 1 | Critical | Two libraries concatenated: row count = sum, column order, content/order preserved; stable snapshot | record loss/duplication |
| 2 | Critical | Duplicate (PREFIX, cell_barcode) with --index-col fails | duplicate cell would corrupt the combined DGE/metacells |
| 3 | High | Union of columns: file lacking a column gets empty values | multi-library metadata with differing MMC columns |
| 4 | High | Single input file passes through unchanged (the validated reference scenario) | matches prototype run |
| 5 | Medium | meta.id/prefix naming and `task.ext.prefix`; emits tuple(meta, file) | wiring contract |
| 6 | Medium | `ext.args` passes --index-col options; versions topic emitted | config contract |
| 7 | Low | stub run | structure only |
Recommended subset: 1, 2, 3, 4.

## Testing gotchas (learned; also in docs/development.md, Gotchas)
- nf-test: where an `error()` message lands (stdout vs stderr) differs between environments. In expected-failure
  assertions search both: `(process.stdout + process.stderr).join('\n').contains('...')` (`function.` for functions).
- An nf-test `config` file loads BEFORE pipeline params, so `params.x` is null there; Docker turns `-v null:/path` into
  a named volume `null` (a directory at the mount point). Build such paths from `System.getProperty`/`getenv`.
  If seen: `docker volume rm null`.
- macOS: `sed -i ''`; no `zcat` for .gz (use `gzip -dc`); host python has no `yaml` (use the container's
  `/usr/local/dropseq/venv/dropseq/bin/python`, feeding scripts on stdin: `docker run -i ... python - < script.py`).
- Files under `/private/tmp/...` (scratchpad) are not visible to Docker bind mounts; mount from the repo instead.
- nf-test has no include mechanism for test files; use several `*.nf.test` files.
- nf-test `--filter` selects test TYPES (process/workflow/pipeline/function), not names. One test: `file.nf.test@<id>` (the
  id printed in brackets). `--tag` selects by tag (union of several). `--dry-run` lists what would run.
- In a nf-test `when { process { """...""" } }` block the `${...}` inside the string is interpolated by nf-test in the test
  context: resolve variables before the `process` block and interpolate only simple values.
- macOS `sed` has no `\b`; the nf-test launcher needs `$HOME/.nf-test` (symlink it if you fake HOME to test missing credentials).
- Shell variables do not persist between tool calls and background commands: pass `GOOGLE_PROJECT_ID=... command` inline.
- A snapshot written by an earlier run can be stale; update only after inspecting the output (`--update-snapshot`).
