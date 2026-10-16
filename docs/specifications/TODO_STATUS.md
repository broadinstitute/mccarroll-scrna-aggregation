# TODO / status

Last updated: 2026-10-16 (session 4). Branch `jn_initial_module_work`; last commit 9d10471. Session 4's work is NOT committed:
the MAKE_TRIPLET_DGE manifest-file change, the new DONOR_CELL_TYPE_REPORT module (`modules/local/donor_cell_type_report/`, untracked), the prototype's
`cell_type_column.txt` output, and doc updates (`docs/testing.md`, this file, `SPEC_SUMMARY.md`).

**Done and tested:** the pre-flight credentials check and 9 modules (table below). 61 tests (12 pre-flight, 40 module fixture,
8 live, 1 template pipeline smoke test). The new module's 7 tests passed individually; the full suite has not been rerun since. Full suite green at the end of session 4 (user ran `tests/run_all_tests.sh` after remaking the baseline
with the current prototype, so `tests/live_data/baseline` includes `<analysis>.cell_type_column.txt`).
**Resume point:** wiring `workflows/scrna-aggregation.nf` edge by edge. Done: edge 0 (inputs: `--manifest`, `--analysis_id` replace `--input`; `PIPELINE_INITIALISATION`
loads and validates the manifest via `loadAggregationManifest` and emits `manifest` = value `[meta(id=analysis), file]` and `entries` = value list) edge 1 (`LOCATE_SCRNA_ARTIFACTS`) and edge 2 (`RESOLVE_LIBRARIES`),
with `tests/pipeline.validation.nf.test` (4) and `tests/pipeline.live.nf.test` (runs the whole pipeline once, then compares published files with the baseline: artifacts match; and the resolved libraries summary matches the baseline's `libraries.tsv` columns).
Edge 2 (session 5): new local module `RESOLVE_LIBRARIES` (`modules/local/resolve_libraries/`, 3 fixture tests): input `tuple val(meta), val(artifact_texts)` (the text of each artifact YAML, read by the workflow with `LibraryResolver.readArtifactTexts`, because a script block cannot read a staged path), `val entries`, `val reference`, `val mmc_model` ('' for none); output `summary` = `<analysis>.resolved_libraries.tsv`. The resolver (Groovy) runs in the script block; a resolver error becomes `exit 1` with the message in `.command.err` (task directory stays inspectable). The summary is NOT published (`withName: 'RESOLVE_LIBRARIES' { publishDir = [ enabled: false ] }` in `conf/modules.config`; user decision: work directory only). The workflow scatters it with `splitCsv(sep: '\t', header: true)` into `ch_libraries`: `tuple val([id: library, analysis_id, mmc_model]), val(row)` (row = the summary columns as a map, 'NA' for none); nothing consumes `ch_libraries` yet. New params `--reference` and `--mmc_model` (config and schema). `SCRNA_AGGREGATION` now takes `ch_entries` as well.
Next: edge 3. Candidate test 4 (the `--mmc_model` / `--reference` overrides reaching the process) and test 6 (entry args and files in the row) of edge 2 were not selected; add them when touching this edge.
The edge queue: 3 SUMMARIZE + MERGE_LIBRARY_METRICS; 4 FORMAT_MAPMYCELLS + BUILD (args file via `collectFile`); 5 MAKE_TRIPLET_DGE + MERGE_CELL_METADATA; 6 DONOR_CELL_TYPE_REPORT + metacells;
7 delete RESOLVE_AGGREGATION_MANIFEST, final output layout, README. The output layout is still the default `publishDir` (`<outdir>/<first word of the process name>/`).
Decisions made (session 5):
- Plan: (1) manifest parser [done]; (2) argument builder [done; unit 3 must also check that no staged file name equals the library's cell metadata or MapMyCells input name, which
  only unit 3 knows]; (3) artifact reader + `LibraryResolver.resolve` [done; libraries with MapMyCells results must use one model] (replaces
  RESOLVE_AGGREGATION_MANIFEST, which is deleted at the end; first an equivalence test against the baseline's `resolved_manifest`); (4) wire the workflow one
  edge at a time.
- Result shape: `libraryId -> [dge, cellMetadata, mmcModel, mmcAnnotations, args, files]` plus run-level `reduced_gtf` and `reference`. The library id is the
  artifact `uei` (manifest `libraryId` is rejected). The artifact YAMLs are read by a `map` in the workflow and passed to the Groovy as parsed maps.
- Validation: manifest-only checks run in `PIPELINE_INITIALISATION` before LOCATE (call `loadAggregationManifest`); artifact-dependent checks after LOCATE.
- `join_and_filter_tsv` got `--args-file FILE` (one argument per line, verbatim, expanded in place; python repo branch `jn_modify_aggregation_python_tools`,
  merged to public main as #589). BUILD_LIBRARY_CELL_METADATA now takes the staged args file instead of `ext.args` [done, 6 tests, no `ext.args` at all] (no `toShellArgs`). The
  per-library args file is NOT published (user decision: it only has to be inspectable in the work directory, where the staged input lives); a run-level
  `<analysis>.resolved_libraries.tsv` (library_id, dge, cell_metadata, mmc_model, mmc_annotations, reduced_gtf, args_file name, files) is also NOT published (user decision, edge 2): it stays in the RESOLVE_LIBRARIES task directory.
Not yet run: `tests/run_all_tests.sh` with the manifest tests; nothing is committed.

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
- Docker containers cannot write into the Claude scratchpad (`/private/tmp/claude-502/...`): for prototype reruns use a git-ignored `testing*` directory at
  the repo root (and copy the reduced GTF from `tests/live_data/baseline/tmp/` into its `tmp/` to skip the 340 MB download). Read a tool's source with
  `docker run --rm --platform linux/amd64 --entrypoint cat <image> <path>` (python tools are under
  `/usr/local/dropseq/venv/dropseq/lib/python3.13/site-packages/dropseq/`); the images run under emulation on this arm64 Mac, so allow time.
- nextflow 26.10.0, nf-test 0.9.5, docker (default nf-test profile `docker,test`). Local images (linux/amd64): `quay.io/broadinstitute/drop-seq_python:jn_test`,
  `quay.io/broadinstitute/drop-seq_java:jn_test`, `us.gcr.io/mccarroll-scrna-seq/drop-seq_private_java:jn_test`.
- `GOOGLE_PROJECT_ID=bican-um1-mccarroll` (not a secret). The baseline is `tests/live_data/baseline` (git-ignored), made by the prototype script on
  `tests/live_data/manifest.yaml`; the command is in `../testing.md`.
- `tests/default.nf.test` was replaced by `tests/pipeline.*.nf.test`; `conf/test.config` now uses the live manifest. (Old note:) replace them with a manifest-driven
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
| 6 | BUILD_LIBRARY_CELL_METADATA (3d; tool `join_and_filter_tsv`), per library | python | DONE: 6 fixture (takes an args file, no `ext.args`) |
| 7 | MAKE_TRIPLET_DGE (4, 5; `manifest.yaml` written in the task work dir, not emitted) | java | DONE: 4 fixture + 1 live |
| 8 | DONOR_CELL_TYPE_REPORT (7; cell type column is a `val` input) | python | DONE: 3 fixture + 1 live |
| 9 | MAKE_METACELLS_FROM_TRIPLET_DGE (8, 9; group columns as params) | java | DONE: 5 fixture + 2 live (called twice; `ext.prefix` per call; header line ignored in the live comparison) |

Then `workflows/scrna-aggregation.nf` and an integration test comparing the published outputs with the baseline.

## Wiring TODO (needed when building the workflow)
- **Manifest parsing (user decision):** the workflow parses the manifest YAML. The `dge` entries anchor the experimental data. The manifest schema
  (`dges[]`: `dge`, `libraryId`, `donor`, `filters` per column with `includeFile`/`excludeFile`/`include`/`exclude`/`min`/`max`; `joins` with
  `joinFile`/`leftColumn`/`joinColumn`; `dgeDefaults` projected onto each dge without the value) supplies the per-library filters, joins and files.
  Per library the workflow builds the args file (`LibraryResolver` / `JoinFilterArguments`) and the `extra_files` for BUILD_LIBRARY_CELL_METADATA (`joinFile`, `includeFile`, `excludeFile`
  paths, localized by Nextflow, with the arguments rewritten to the staged basenames). RESOLVE_AGGREGATION_MANIFEST goes away (replaced by `LibraryResolver`).
- **Paths (user decision):** all manifest paths are absolute (data on Google Cloud); local files must be passed as parameters so Nextflow localizes them.
  Planned, not coded: the pre-flight check verifies that every file the manifest names (DGEs, `joinFile`, `includeFile`, `excludeFile`) exists.
- **`ext.args` / `ext.prefix` in `conf/modules.config`:**
  - BUILD_LIBRARY_CELL_METADATA: done: the manifest arguments go in a per-library args file (one argument per line) passed with
    `join_and_filter_tsv --args-file`; no `ext.args` and no shell quoting (see the Resume point).
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
- Prototype change (session 4): it now writes `<analysis>.cell_type_column.txt` to the out dir when there are MapMyCells results. The
  baseline got that file by copying it from a full rerun whose other outputs were identical except for embedded output-dir paths
  (`libraries.tsv`, the triplet YAML, and the `#MakeMetacellsFromTripletDge ...` header line of both metacells files). The metacells live test
  must skip or normalize that header line. Decide whether the workflow also publishes `<analysis>.cell_type_column.txt`.
- `googlebatch` profile is a stub; service account email, work bucket and location are deferred by the user.
- Real service-account key not tried (same mount mechanism); whether the Google client falls back to a key's `project_id` when `GOOGLE_CLOUD_PROJECT` is
  empty is untested.
- `docker.registry = 'quay.io'` is kept as in mccarroll_nextflow, whose `us-docker.pkg.dev/...` private images work with it; confirm on Batch/GCP (credentials to pull
  the private image).
- Offered, not answered: review the remaining module names (e.g. LOCATE_SCRNA_ARTIFACTS) before wiring.
- Unselected candidate tests to maybe add later: RESOLVE (library id equals analysis id, DGE with no artifact, dgeDefaults projection, stub); SUMMARIZE
  (malformed YAML, newest-trace selection, stub); MERGE_LIBRARY_METADATA (ext.prefix, same barcode with different PREFIX, stub); FORMAT (meta/name,
  no prefix, ext.prefix, stub); BUILD (duplicate join key, meta/name, ext.prefix, stub); MAKE_TRIPLET_DGE (single library, meta/names, stub); DONOR_CELL_TYPE_REPORT
  (numeric-looking donor ids kept as text, `ext.args --umi-column`, stub).
- `manifest_no_donors.yaml` (no-donor scenario, see `tests/live_data/README.md`) has not been run.

## Pre-flight check and profiles (implemented; details in `../credentials.md`)
`checkLocalGcpCredentials` runs first in `PIPELINE_INITIALISATION` (docker profile only) and fails before any process if the credentials file is missing, not
valid JSON, of an unsupported `type`, lacks required fields, or is an `authorized_user` file without `GOOGLE_PROJECT_ID`. 12 tests in
`tests/preflight.function.nf.test`. The `docker` profile mounts `params.gcp_credentials_file` into task containers and sets
`GOOGLE_APPLICATION_CREDENTIALS` / `GOOGLE_CLOUD_PROJECT`.
