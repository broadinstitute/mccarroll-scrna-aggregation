# TODO / status

Last updated: 2026-10-15 (session 3). Nothing is committed (all work since the template commit is uncommitted).

**Done and tested:** the pre-flight credentials check and 7 modules (table below). Full suite green: 50 tests (12 pre-flight, 32 module fixture,
5 live, 1 template pipeline smoke test) in ~325 s.
**Resume point: DONOR_CELL_TYPE_REPORT (order 8):** read prototype step 7, ask clarification questions (two options each), state the data
contract, rank candidate tests, stop for the user's selection (the user usually answers "recommended").

Companion docs: `SPEC_SUMMARY.md` (what the prototype does; step -> module table), `../testing.md` (running tests, live tests, fixtures, per-module
test catalog and contracts), `../development.md` (conventions, gotchas), `../credentials.md` (credentials, parameters).

## Ground rules (from the user)
- Source of truth: `scrna-aggregation_prototype.sh`. Modules + nf-test unit tests first, leaf-first, one at a time, on small fixtures; then ONE
  workflow wiring tested modules one edge at a time. No subworkflows (the template's init subworkflow stays).
- Process per unit: clarification questions (two options each) -> data contract -> severity-ranked candidate tests -> STOP for selection ->
  `nf-test generate` -> tests -> implement -> targeted tests.
- Favor clarity and testability over fewer lines. Fixtures are self-contained per module (never shared). One test file per unit
  (`main.nf.test`; a separate file only for live vs synthetic; different args via test-level `config`).
- Module names describe the step, not the tool (the tool keeps its own name).
- Live tests: for modules that read `gs://` (LOCATE, SUMMARIZE) and modules that produce merged published files (MERGE_LIBRARY_METADATA,
  MAKE_TRIPLET_DGE); new publishing modules (donor cell type report, metacells) get one too. Per-library intermediates (FORMAT_..., BUILD_...)
  get fixture tests only. Live tests compare equality with the baseline file at that stage (md5 first, details only on mismatch).
- Containers are parameters (`jn_test` locally). At the end of development switch the defaults to the production images and tags.
- Do not commit/push unless asked. Never write into `/Users/nemesh/nextflow_aggregation_shell_script/out` (read-only old baseline).
  `tests/run_all_tests.sh` has no options. Keep `docs/testing.md`, `docs/development.md` and `docs/credentials.md` updated.
- No long foreground commands (120 s limit): run in the background and wait for the notification.

## Environment
- nextflow 26.10.0, nf-test 0.9.5, docker (default nf-test profile `docker,test`). Local images (linux/amd64): `quay.io/broadinstitute/drop-seq_python:jn_test`,
  `quay.io/broadinstitute/drop-seq_java:jn_test`, `us.gcr.io/mccarroll-scrna-seq/drop-seq_private_java:jn_test`.
- `GOOGLE_PROJECT_ID=bican-um1-mccarroll` (not a secret). The baseline is `tests/live_data/baseline` (git-ignored), made by the prototype script on
  `tests/live_data/manifest.yaml`; the command is in `../testing.md`.
- `tests/default.nf.test` and `conf/test.config` are still the template's (a smoke test of the empty workflow); replace them with a manifest-driven
  integration test when the workflow is wired.

## Run the tests
```bash
export GOOGLE_PROJECT_ID=bican-um1-mccarroll
tests/run_all_tests.sh                                   # everything (needs the baseline, see ../testing.md)
nf-test test modules/local/<module>/tests/main.nf.test   # one file; --tag live runs all the live tests
```

## Modules (order follows the prototype's data flow)
| Order | Module (prototype step) | Container | Status |
|---:|---|---|---|
| 1 | LOCATE_SCRNA_ARTIFACTS (1a) | python | DONE: 6 fixture + 1 live |
| 2 | RESOLVE_AGGREGATION_MANIFEST (1b) | python | DONE: 7 fixture |
| 3 | SUMMARIZE_SCRNA_EXPERIMENTS (2a), per library | python | DONE: 2 fixture + 1 live |
| 4 | MERGE_LIBRARY_METADATA (2b, 6; tool `cat_tsvs`) | python | DONE: 4 fixture + 2 live |
| 5 | FORMAT_MAPMYCELLS_ANNOTATIONS (3b; tool `convert_mmc_csv`), only if `mmc_annotations != NA` | python | DONE: 4 fixture |
| 6 | BUILD_LIBRARY_CELL_METADATA (3d; tool `join_and_filter_tsv`), per library | python | DONE: 5 fixture |
| 7 | MAKE_TRIPLET_DGE (4, 5; manifest built inside the task) | java | DONE: 4 fixture + 1 live |
| 8 | DONOR_CELL_TYPE_REPORT (7) | python | NEXT |
| 9 | MAKE_METACELLS_FROM_TRIPLET_DGE (8, 9; group columns as params) | java | not started |

Then `workflows/scrna-aggregation.nf` and an integration test comparing the published outputs with the baseline.

## Wiring TODO (needed when building the workflow)
- **Manifest parsing (user decision):** the workflow parses the manifest YAML. The `dge` entries anchor the experimental data. The manifest schema
  (`dges[]`: `dge`, `libraryId`, `donor`, `filters` per column with `includeFile`/`excludeFile`/`include`/`exclude`/`min`/`max`; `joins` with
  `joinFile`/`leftColumn`/`joinColumn`; `dgeDefaults` projected onto each dge without the value) supplies the per-library filters, joins and files.
  Per library the workflow builds `meta.join_filter_args` and the `extra_files` for BUILD_LIBRARY_CELL_METADATA (`joinFile`, `includeFile`, `excludeFile`
  paths, localized by Nextflow, with the arguments rewritten to the staged basenames). Open: whether RESOLVE_AGGREGATION_MANIFEST keeps only the artifact/library
  resolution (today it also writes the `*.join_and_filter_args.txt` files; its help calls it a stand-in that goes away).
- **Paths (user decision):** all manifest paths are absolute (data on Google Cloud); local files must be passed as parameters so Nextflow localizes them.
  Planned, not coded: the pre-flight check verifies that every file the manifest names (DGEs, `joinFile`, `includeFile`, `excludeFile`) exists.
- **`ext.args` / `ext.prefix` in `conf/modules.config`:**
  - BUILD_LIBRARY_CELL_METADATA: `ext.args = { toShellArgs(meta.join_filter_args) }`; write `toShellArgs` (quotes each argument; nf-test function test for
    spaces, quotes, `$`) in `subworkflows/local/utils_nfcore_scrna-aggregation_pipeline/main.nf`.
  - FORMAT_MAPMYCELLS_ANNOTATIONS: `--column-prefix ${meta.mmc_model}_` plus `--level` from `params.mmc_level` if set. The workflow calls it only when
    `mmc_annotations != NA` and checks that the `cell_type_column` value is the same for all libraries.
  - MERGE_LIBRARY_METADATA is included twice, as `MERGE_LIBRARY_METRICS` and `MERGE_CELL_METADATA`: `ext.prefix = { "${meta.id}.library_metrics" }` /
    `.cell_metadata`, and `--index-col PREFIX --index-col cell_barcode` for the cell metadata (the live test configs already use these).
  - RESOLVE: `params.reference` / `params.mmc_model` through `ext.args` (add to the schema).
- **Meta:** run-level modules (LOCATE, RESOLVE, MERGE, MAKE_TRIPLET_DGE) use `meta.id` = analysis id; per-library modules use
  `meta = [id: <library_id>, analysis_id: <analysis id>]` plus `mmc_model` and `join_filter_args` as above.
- **Gather steps:** sort the per-library files and prefixes by library id (the merge order is the input order). The Java DGE task takes the three lists
  (prefixes, DGEs, barcode lists) in the same order. Read `libraries.tsv` with `splitCsv(sep:'\t', header:true)` and join by `library_id`; ignore its
  task-local `artifact_file`/`args_file` columns. Donor presence (header of the merged cell metadata) gates steps 7 to 9.
- **Params:** `java_image`, `python_image` and `image_tag` exist. MAKE_TRIPLET_DGE uses label `process_medium` (36 GB, heap 80% of `task.memory`): revisit with
  real needs. The reduced GTF comes from the resolved manifest.
- **`versions`:** no module emits versions yet; decide once for all (mccarroll_nextflow uses `topic: versions` with an `eval(... --version ...)`).
- **Integration test:** compare the workflow's outputs with the baseline (md5 via `LiveFiles`); check that the baseline was made from the same manifest; add
  multi-library live tests when multi-library data exists.

## Open questions / pending
- `googlebatch` profile is a stub; service account email, work bucket and location are deferred by the user.
- Real service-account key not tried (same mount mechanism); whether the Google client falls back to a key's `project_id` when `GOOGLE_CLOUD_PROJECT` is
  empty is untested.
- `docker.registry = 'quay.io'` is kept as in mccarroll_nextflow, whose `us-docker.pkg.dev/...` private images work with it; confirm on Batch/GCP (credentials to pull
  the private image).
- Offered, not answered: review the remaining module names (e.g. LOCATE_SCRNA_ARTIFACTS) before wiring.
- Unselected candidate tests to maybe add later: RESOLVE (library id equals analysis id, DGE with no artifact, dgeDefaults projection, stub); SUMMARIZE
  (malformed YAML, newest-trace selection, stub); MERGE_LIBRARY_METADATA (ext.prefix, same barcode with different PREFIX, stub); FORMAT (meta/name,
  no prefix, ext.prefix, stub); BUILD (duplicate join key, meta/name, ext.prefix, stub); MAKE_TRIPLET_DGE (single library, meta/names, stub).
- `manifest_no_donors.yaml` (no-donor scenario, see `tests/live_data/README.md`) has not been run.

## Pre-flight check and profiles (implemented; details in `../credentials.md`)
`checkLocalGcpCredentials` runs first in `PIPELINE_INITIALISATION` (docker profile only) and fails before any process if the credentials file is missing, not
valid JSON, of an unsupported `type`, lacks required fields, or is an `authorized_user` file without `GOOGLE_PROJECT_ID`. 12 tests in
`tests/preflight.function.nf.test`. The `docker` profile mounts `params.gcp_credentials_file` into task containers and sets
`GOOGLE_APPLICATION_CREDENTIALS` / `GOOGLE_CLOUD_PROJECT`.
