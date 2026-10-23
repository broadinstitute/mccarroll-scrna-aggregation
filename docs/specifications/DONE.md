# Done

What has been implemented and verified, kept as a record (moved out of the old TODO file, session 12). What is still to do is in `TODO.md`; design decisions and gotchas are in `../development.md`.

## State at the end of session 13

The pipeline produces the baseline result locally (docker), on Google Batch (`-profile googlebatch`) and on Seqera Platform (launcher `launchScrnaAggregation` in `broadinstitute/mccarroll_tw_clp`; the pipeline is registered as `scrnaAggregation_prod`, revision git tag `prod`, per workspace: `bican-um1_RNAseq` and `pipeline-testing`; a new workspace needs its own `tw pipelines add`).

- **Local:** `tests/run_all_tests.sh` passed 110 of 110 tests at the end of session 13 (791 s; needs `GOOGLE_PROJECT_ID`, Docker, network, Application Default
  Credentials and the baseline in `tests/live_data/baseline`, see `../testing.md`). `nextflow lint .` is clean (50 files, no errors or warnings).
- **Google Batch:** `tests/batch_full_run/run.sh` last passed 12 of 12 checks in session 10, before the session 13 changes (to re-run, see `TODO.md`).
- The baseline (`tests/live_data/baseline`) was remade with the public `current` images in session 13: the same 16 files, identical in content to the
  earlier `jn_test` baseline (the old one was then deleted).
- README has a workflow figure (Mermaid, rendered by GitHub; checked with `npx @mermaid-js/mermaid-cli`).
- The session 13 work (branch `jn_simplify_dataflow`) is not committed yet.

## Work log

### A. Commit the work (done in session 7)
Committed in 6 groups (old resolver modules removed, modules, workflow/config/resolver, tests, Google Batch checks, docs). Not pushed. `work/`, `.nf-test/` and `tests/live_data/baseline` are git-ignored; check `git status` for stray `testing*` directories before the next commit.

### B. Nextflow language: strict syntax and static typing (DONE in session 8, committed `b56efab`)
- Every script has `nextflow.enable.types = true` (Nextflow 26.10.0): `main.nf` (typed `params` block, types only; defaults in `conf/params.config`, included by `nextflow.config`), the init subworkflow (`Manifest` record),
  `workflows/scrna-aggregation.nf` (`Library` record, record joins by `id`, typed helper `toLibraries`) and the 8 modules (record inputs, named record outputs). Module tests use `record(...)` inputs.
- `collectFile` is replaced by the `exec` process `WRITE_TEXT_FILE` (3 aliases: resolved summary, args file, versions; the cell type column file was removed in session 10). `topic: versions` is gone; `WRITE_VERSIONS` writes the versions file.
- `help` decision: `String?` with default `null`; a bare `--help` prints the general help (intercepted in `PIPELINE_INITIALISATION`); `--help <name>` describes one parameter. 2 tests.
- New tests: 2 `WRITE_TEXT_FILE`, 1 `checkCellTypeColumn` two-list overload, 2 help. Suite: 97 tests, all passed. Details and rules learned: `../development.md` (Static typing).
- Behaviour changes to remember: the cell type column file and resolved summary are published by the `output` block (rewritten on re-runs) instead of `collectFile(storeDir:)`; undeclared params fail early.
- **Publishing migrated to the `output` block (session 8):** `publishDir` is gone from `conf/modules.config`. `SCRNA_AGGREGATION` has typed emits (13 channels of paths: `Value<Path>` or `Channel<Path>`), `MCCARROLL_SCRNA_AGGREGATION` passes them on, the entry workflow lists them under `publish:` and `main.nf` has the `output { }` block; `outputDir = params.outdir` and `workflow.output.mode = params.publish_dir_mode` are in `nextflow.config`. Same published files as before (live test unchanged). To check on Google Batch: publishing to a `gs://` `--outdir`.

### C. Workflow-level tests that the live data cannot give (started in session 9)
**Done (session 9):** `tests/pipeline.synthetic.nf.test`, 7 tests on local synthetic libraries (`tests/fixtures/synthetic/`, real processes in Docker, no credentials, network or baseline; documented in `../testing.md`):
1. (main test) a manifest with two MapMyCells libraries and donors: `min`, `max`, `include`, `exclude`, `includeFile`, `excludeFile`, `donor` and a join (from `dgeDefaults`) reach `BUILD_LIBRARY_CELL_METADATA` and the merged cell metadata, the matrix, the donor metacells (summed per donor and per donor and cell type) and the donor cell type report, with expected values worked out by hand.
2. (guard) two libraries with no donors and no MapMyCells results (the no-MapMyCells path, `mmc_tsv = null`, ran through the workflow for the first time): cells, counts and prefix stay with their own library, in manifest order (the reverse of alphabetical), the skip warnings are logged and no donor files are published.
3. (guard) a duplicate (`PREFIX`, `cell_barcode`) fails `MERGE_CELL_METADATA`.
4. (guard) libraries with different cell type columns (`LIB_MMC_SUPER` has the hierarchy supercluster > class) stop the run with the resolver's message.
5. `--mmc_level class` on the same libraries: cell type column, merged metadata, donor cell type report and metacells use `MODEL1_class_name`.
6. (guard) mixed donors (one library with a donor, one without) stop at the resolver before any per-library process.
7. `--mmc_model MODEL2` (a second MapMyCells model in `LIB_MMC_1` and `LIB_MMC_2`) selects that model in every library.

**Decided not to do (user, session 9):** merge order independent of task finish order (the order is the manifest order by construction), `dgeDefaults` beyond one join, a village library through the workflow, running `manifest_no_donors.yaml`, a second real library on `gs://`.
**Parameter `--reference` removed (user decision, session 9):** libraries with different references always fail in the resolver ("All DGEs must have the same reference"); the override did not change any output. Removed from `main.nf`, `conf/params.config`, `nextflow_schema.json`, the workflow, `LibraryResolver` and the docs (`docs/specifications/scrna-aggregation_prototype.sh` and `SPEC_SUMMARY.md` still describe the prototype's own `--reference`).
**Section C is complete.**
- Process reminder: ask clarification questions, state the data contract, list severity-ranked candidate tests, STOP for the user's selection (see Ground rules).

### Google Batch and Seqera (sessions 7, 10, 11)
- **Session 10 (2026-10-21): the full pipeline ran on Google Batch (committed).** `tests/batch_full_run/run.sh` (live manifest, `-profile googlebatch`, `gs://` work and out under `gs://mccarroll_scrnaseq_central_temp/nextflow/aggregation_testing/`): 13 of 13 checks passed on the first run (baseline equality, top-level listing, `WRITE_*` in the head job, all tasks COMPLETED in the public images). Peaks: `MAKE_TRIPLET_DGE` 514 MB, others under 200 MB, tasks 2 to 7 s: the 16 GB / 6 GB requests are far above need (decide whether to lower them with a multi-library run; the retry setup already matches `mccarroll_nextflow`).
  Changes: `googlebatch` profile sets the `broad-allow` network, subnetwork, tag and exact `machineType`s (a wildcard like `n1-*` still triggers the deprecated Cloud Info selection and its warning; see `../credentials.md`, Machine types; Java steps now 15 GB then 30 GB, 6 cpus fixed); the nf-core institutional configs are no longer loaded (their `googlebatch` profile overrode ours; `custom_config_*` params removed); `gcp_credentials_file` defaults to null (docker profile and pre-flight use the ADC path then). Seqera: the compute environment sets work dir, location, VPC, tag, Wave and Fusion and no service account (so default Compute account); untested with this pipeline. Re-run after the exact types: no Cloud Info warning.
- **Seqera Platform (done, session 11):** the launcher `launchScrnaAggregation` exists in `mccarroll_tw_clp` and the pipeline is registered in two workspaces; see the DONE note at the top for the first run and the open machine type question. (Earlier plan, session 10: deferred until the rest of the analysis was settled.)
- Session 7 findings (project access, VPC, service accounts, nf-test limits) are in `../development.md`; the three steps planned then (network settings in the profile, work bucket, whole-pipeline run) were done in session 10.

### Session 12
- Seqera open items closed (user). Prototype script now uses the public `quay.io/broadinstitute/drop-seq_java` image.
- Template cleanup: removed `conf/test_full.config`, `tower.yml`, the unused container profiles (conda, mamba, podman, shifter, charliecloud, wave, gpu, arm64), the unused `base.config` labels and the template TODO comments. Kept: `.github/` templates, `.nf-core.yml`, and the `docker`, `googlebatch`, `singularity`, `apptainer`, `debug` and `test` profiles.
- `manifest.homePage` and `contributors` filled in; README Credits, Seqera launch example.
- `versions`: the hard-coded `current` image tags are the version record (user decision); `WRITE_VERSIONS` writes `pipeline_info/scrna-aggregation_software_versions.yml` (Nextflow and pipeline versions only).
- Docs updated in session 6: `../output.md`, `../usage.md`, `../data_flow.md`, `../testing.md`, `../development.md`, `../credentials.md`; `docs/README.md` is the index.

### Session 13: workflow data flow simplifications 1 to 3
- `BUILD_LIBRARY_CELL_METADATA` takes `args: List<String>` and writes `<lib>.join_and_filter_args.txt` itself (`printf`, single-quoted; zero bytes for none). `WRITE_ARGS_FILE`, the `args_files` channel, its join and the id parsing from the file name are gone. 2 new module tests: the exact args file for a value with spaces, `$` and `'`, and a zero-byte file for no arguments.
- `artifact_files` and its join are gone: each library is combined with the artifacts directory and resolves `<id>.yaml`.
- `Library.mmc_annotations` is `String?` (null for none); `toLibraries` converts the resolver's `'NA'`.
- **Top-level `id`, no `meta` (user decision):** every module record is `record(id: String, <the fields it uses>)`; FORMAT also takes `mmc_model` (its `ext.args` reads `${mmc_model}`, the `ext.prefix` closures `${id}`). `Library` has `analysis_id`, `position` and `mmc_model` as fields; per-library results are joined back to the libraries by `id` to be sorted. `Manifest` is `record(id, manifest)`.
- Item 4: `libraries.join(annotations, by: 'id', remainder: true)` replaces the `mix` with null records. Item 5: the donor steps get the gated record directly (extra fields are accepted), with `combine(group_columns: [...])` or `+ record(group_columns: ...)`; the report takes `cell_type_inputs` as is. Item 6 dropped (nested paths are not staged; spike results in `../development.md`).
- New tests: FORMAT with the pipeline's `ext.args` closure (prefix from `mmc_model`), and a synthetic run with one MapMyCells library and one without.
- **Pre-flight file check:** `loadAggregationManifest` checks every file the manifest names (DGEs, `joinFile`, `includeFile`, `excludeFile`; local or `gs://`) before any process and lists all missing or uncheckable files in one error, each path once with its key and entries. Before, a missing join file failed only in BUILD (after LOCATE, SUMMARIZE, FORMAT and the metrics merge) as `FileNotFoundError: 'extra.tsv'`. 3 new tests (2 function, 1 synthetic pipeline); the manifest, arguments and resolver function tests now host on a local synthetic manifest so they stay offline.

## Modules (order follows the prototype's data flow)
| Order | Module (prototype step) | Container | Status |
|---:|---|---|---|
| 1 | LOCATE_SCRNA_ARTIFACTS (1a) | python | DONE: 6 fixture + 1 live |
| 2 | RESOLVE_AGGREGATION_MANIFEST (1b) | python | DELETED (session 6): replaced by the Groovy `LibraryResolver`, run in the workflow |
| 3 | SUMMARIZE_SCRNA_EXPERIMENTS (2a), per library | python | DONE: 2 fixture + 1 live |
| 4 | MERGE_LIBRARY_METADATA (2b, 6; tool `cat_tsvs`), included twice as MERGE_LIBRARY_METRICS and MERGE_CELL_METADATA | python | DONE: 4 fixture + 2 live |
| 5 | FORMAT_MAPMYCELLS_ANNOTATIONS (3b; tool `convert_mmc_csv`), only if `mmc_annotations != NA` | python | DONE: 4 fixture |
| 6 | BUILD_LIBRARY_CELL_METADATA (3d; tool `join_and_filter_tsv`), per library | python | DONE: 6 fixture (takes an args file, no `ext.args`) |
| 7 | MAKE_TRIPLET_DGE (4, 5; `manifest.yaml` written in the task work dir, not emitted) | java | DONE: 4 fixture + 1 live |
| 8 | DONOR_CELL_TYPE_REPORT (7; cell type column is a `val` input) | python | DONE: 3 fixture + 1 live |
| 9 | MAKE_METACELLS_FROM_TRIPLET_DGE (8, 9), included twice as DONOR_METACELLS and DONOR_CELL_TYPE_METACELLS | java | DONE: 5 fixture + 2 live (`ext.prefix` per call; header line ignored in the live comparison) |

Groovy (`lib/`), tested directly through function tests hosted on `loadAggregationManifest`: `AggregationManifest` (12 tests), `JoinFilterArguments` (7), `LibraryResolver` (12) and the pre-flight
check (12), plus `resolver.live.nf.test` (resolver vs the baseline's `resolved_manifest/`).

## Pre-flight check and profiles (implemented; details in `../credentials.md`)
`checkLocalGcpCredentials` runs first in `PIPELINE_INITIALISATION` (docker profile only) and fails before any process if the credentials file is missing, not
valid JSON, of an unsupported `type`, lacks required fields, or is an `authorized_user` file without `GOOGLE_PROJECT_ID`. 12 tests in
`tests/preflight.function.nf.test`. The `docker` profile mounts `params.gcp_credentials_file` into task containers and sets
`GOOGLE_APPLICATION_CREDENTIALS` / `GOOGLE_CLOUD_PROJECT`.
