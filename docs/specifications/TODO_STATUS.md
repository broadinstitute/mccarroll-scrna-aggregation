# TODO / status (update as you go)

Last updated: 2026-10-14. Pre-flight credentials check and the first module (LOCATE_SCRNA_ARTIFACTS) are done and tested.
Next: RESOLVE_AGGREGATION_MANIFEST (see "Implementation order").
Companion docs: `SPEC_SUMMARY.md` (behavior of the prototype), `../credentials.md` (users: credentials, env vars),
`../development.md` (developers: how to run every test, conventions, test catalog, gotchas).

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
- Keep `docs/credentials.md` and `docs/development.md` updated whenever modules, tests, params or env vars change.

## Environment
- nextflow 26.10.0, nf-test 0.9.5, docker. Local images (all linux/amd64):
  `quay.io/broadinstitute/drop-seq_python:jn_test`, `quay.io/broadinstitute/drop-seq_java:jn_test`,
  `us.gcr.io/mccarroll-scrna-seq/drop-seq_private_java:jn_test` (the prototype's Java image), plus private_python/r.
- Real data: `$D=/Users/nemesh/nextflow_aggregation_shell_script` with `manifest.yaml`, `manifest_no_donors.yaml`, and
  validated prototype output in `$D/out` (e.g. `out/artifacts/SMRI_V11_rxn1.yaml`, `out/resolved_manifest/`).
- Local gcloud project ID for `GOOGLE_PROJECT_ID`: `bican-um1-mccarroll`. Not secret; it is in the docs.
- `nextflow lint .` currently reports 2 known errors, both the hyphenated template name `SCRNA-AGGREGATION`
  (`main.nf:16`, `workflows/scrna-aggregation.nf:15`), to be fixed when wiring the workflow (decision Q5).
- `tests/default.nf.test` and `conf/test.config` are still the template's (pipeline test will fail until the workflow exists).
- Nothing is committed (all changes since the template commit are uncommitted; `.nf-test/` is now in `.gitignore`).

## How to run the tests (details in docs/development.md)
```bash
cd /Users/nemesh/mccarroll-scrna-aggregation
nf-test test subworkflows/local/utils_nfcore_scrna-aggregation_pipeline/                          # 12 pre-flight tests, no docker
nf-test test modules/local/locate_scrna_artifacts/tests/main.nf.test --profile docker,test        # 6 fixture tests, needs docker
GOOGLE_PROJECT_ID=bican-um1-mccarroll \
SCRNA_LIVE_MANIFEST=$D/manifest.yaml SCRNA_LIVE_BASELINE_DIR=$D/out/artifacts \
nf-test test modules/local/locate_scrna_artifacts/tests/gcs.nf.test --profile docker,test         # 1 live gs:// test (baseline dir optional)
```
Do not run `nf-test test .` without `SCRNA_LIVE_MANIFEST` set (it includes the live test).

## Implementation order (updated; follows the data flow of the prototype)
Local modules under `modules/local/<tool>/main.nf` (no suitable nf-core module exists for these tools).
The order below is proposed from the prototype's steps; the user chose LOCATE first, the rest is not yet confirmed.
| Order | Module (prototype step) | Container | Unit test approach | Status |
|---:|---|---|---|---|
| 1 | LOCATE_SCRNA_ARTIFACTS (1a) | python | local fixtures + live gs:// test | DONE: 6 fixture tests + 1 live test pass |
| 2 | RESOLVE_AGGREGATION_MANIFEST (1b) | python | artifacts YAML fixtures: reuse `locate_scrna_artifacts/tests/fixtures/expected/*.yaml` or real `$D/out/artifacts/*.yaml` | NEXT |
| 3 | SUMMARIZE_SCRNA_EXPERIMENTS (2a), per library | python | reads artifact URLs; local fixture paths if supported, else live gs:// | not started |
| 4 | CAT_TSVS (2b library metrics, and 6 cell metadata with --index-col) | python | gs-free; candidate tests below | not started |
| 5 | CONVERT_MMC_CSV (3b), only if mmc_annotations != NA | python | gs-free | not started |
| 6 | JOIN_AND_FILTER_TSV (3d), per library | python | gs-free | not started |
| 7 | MAKE_TRIPLET_DGE (4+5; generates the triplet manifest inside the task) | java | tiny DGE + tiny GTF | not started |
| 8 | DONOR_CELL_TYPE_REPORT (7) | python | gs-free | not started |
| 9 | MAKE_METACELLS_FROM_TRIPLET_DGE (8, 9; GROUP_COLUMNS as params) | java | tiny triplet DGE | not started |
Then: `workflows/scrna-aggregation.nf`, wired one edge at a time (fix the hyphenated names, replace the template's
samplesheet input with the manifest + `analysis_id` params), plus an integration test comparing with the validated
prototype outputs in `$D/out`.

## Done so far
1. **Pre-flight credentials check** (`checkLocalGcpCredentials(profile, credentialsFile, projectId)` in
   `subworkflows/local/utils_nfcore_scrna-aggregation_pipeline/main.nf`, called first in `PIPELINE_INITIALISATION`).
   Only active with the `docker` profile. Fails before any process if: the credentials path is missing or a directory;
   the file is not valid JSON; `type` is not `authorized_user`/`service_account`; required fields are missing;
   or it is an `authorized_user` file and `GOOGLE_PROJECT_ID` is unset. 12 tests in `tests/preflight.function.nf.test`
   (tag `preflight`). No network call is made; real acceptance by Google is shown by the first gs:// reading task.
2. **Profiles/params** (`nextflow.config`, `nextflow_schema.json`):
   - `docker` profile: runs `-u $(id -u):$(id -g) --platform=linux/amd64` (the old `emulate_amd64` profile was removed),
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
   `gcs.nf.test` (live gs:// with the real ADC mount; prints the generated YAML paths; optional `SCRNA_LIVE_BASELINE_DIR`
   compares field by field and printed 'matches baseline (49 fields)' against the prototype output).
   The tool also accepts local paths (`dropseq.util.storage`: GcsStore for gs://, LocalStore otherwise).

## Decisions made
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

## Open questions / pending
- Q5 hyphenated `SCRNA-AGGREGATION` identifiers: fix when wiring the workflow (recommended; not yet confirmed).
- `googlebatch` settings (service account email, work bucket, location) deferred by the user.
- `versions` emit/topic convention for local modules: not implemented for LOCATE; decide with the next module.
- Real service-account key not yet tried (mechanism is the same mount; documented as untested).
- Whether the Google client falls back to a service-account key's `project_id` when `GOOGLE_CLOUD_PROJECT` is empty is untested.
- `docker.registry = 'quay.io'` in `nextflow.config`: review before using the `us.gcr.io` Java image or GCP.
- Fixtures README and test catalog: see `docs/development.md` (test catalog) and `modules/local/locate_scrna_artifacts/tests/fixtures/README.md`.

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

## Testing gotchas (learned; also in docs/development.md)
- nf-test: where an `error()` message lands (stdout vs stderr) differs between environments. In expected-failure
  assertions search both: `(process.stdout + process.stderr).join('\n').contains('...')` (`function.` for functions).
- An nf-test `config` file loads BEFORE pipeline params, so `params.x` is null there; Docker turns `-v null:/path` into
  a named volume `null` (a directory at the mount point). Build such paths from `System.getProperty`/`getenv`.
  If seen: `docker volume rm null`.
- macOS: `sed -i ''`; no `zcat` for .gz (use `gzip -dc`); host python has no `yaml` (use the container's
  `/usr/local/dropseq/venv/dropseq/bin/python`, feeding scripts on stdin: `docker run -i ... python - < script.py`).
- Files under `/private/tmp/...` (scratchpad) are not visible to Docker bind mounts; mount from the repo instead.
- nf-test has no include mechanism for test files; use several `*.nf.test` files and tags.
