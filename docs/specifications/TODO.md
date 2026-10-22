# TODO / status

Last updated: 2026-10-21 (session 10: first full run on Google Batch, Google Batch profile work, cell type column file removed). Branch `jn_google_cloud_analysis`. Sessions 4 to 10 are committed (session 10 in 4 commits); nothing is pushed and no pull request is open. Commit only when the user asks.

**State at the end of session 10:** everything is verified after the last code change. `tests/run_all_tests.sh`: 104 tests, 752 s, all passed. `tests/batch_full_run/run.sh` on Google Batch (`mccarroll-scrna-seq`): 12 of 12 checks passed with the exact machine types (`n1-standard-2` default, `n1-standard-8` for the Java steps), no Cloud Info warning, no `WRITE_*` executor warning. `nextflow lint .` is clean (50 files). Scratch from that run is still in `gs://mccarroll_scrnaseq_central_temp/nextflow/aggregation_testing/{work,out}` (delete when done).

**DONE (2026-10-21): the Python command line tool that launches this workflow on Seqera Platform.** It is `launchScrnaAggregation` in `broadinstitute/mccarroll_tw_clp` (`src/clp/launch_scrna_aggregation.py`, branch `jn_scrna_aggregation_cli`, pushed, not yet merged to `main`). Usage: `launchScrnaAggregation <manifest> --analysis-id <ID> --project <project> [--mmc-model M] [--mmc-level L] [--output-dir gs://...] [--dry-run]`. A local manifest is uploaded to `<outdir>/<analysis_id>.manifest.yaml` (the pipeline reads `params.manifest` from cloud storage); the default `outdir` is `gs://<standard_bucket>/projects/<project>/aggregation/<analysis_id>`. The pipeline is registered in Seqera as `scrnaAggregation_prod` (revision: the git tag `prod`, on `387aad2`), **per workspace**: so far in `bican-um1_RNAseq` and `pipeline-testing`; any other project's workspace needs its own `tw pipelines add`. A first Seqera run (`jn_agg_test1`, run `3G7rN707T3wUVc` in `pipeline-testing`, live manifest) got through LOCATE to MERGE_CELL_METADATA, then `MAKE_TRIPLET_DGE` sat in Google Batch QUEUED: `ZONE_RESOURCE_POOL_EXHAUSTED` for `c2d-highcpu-8` in `us-central1-c` (the compute environment pins no machine types, so Batch picked that one; the `googlebatch` profile's exact types are not used on Seqera). Its final result is not recorded here. **Open (to discuss with coworkers, nothing changed yet):** pin machine types either in the pipeline (move `machineType` out of the `googlebatch` profile) or in the workspace compute environment (`computeJobsMachineType`). Other open items: tune the Java step memory (now 15 GB, then 30 GB) with larger data sets (section D), and the unselected tests (section F).

## 1. Where we are

- **The workflow is fully wired and the whole test suite is green:** `tests/run_all_tests.sh` ran 104 tests with no failures at the end of session 10 (752 s)
  (needs `GOOGLE_PROJECT_ID`, Docker, network, Application Default Credentials and the baseline in `tests/live_data/baseline`, see `../testing.md`).
  `nextflow lint .` is clean (50 files, no errors or warnings).
- **What the pipeline does** (`main.nf` -> `workflows/scrna-aggregation.nf`; data-flow diagram in `../data_flow.md`):
  `PIPELINE_INITIALISATION` checks credentials and the manifest -> `LOCATE_SCRNA_ARTIFACTS` -> `LibraryResolver.resolve` (head job, Groovy) -> per library
  `SUMMARIZE_SCRNA_EXPERIMENTS`, `FORMAT_MAPMYCELLS_ANNOTATIONS` (only with MapMyCells results), `BUILD_LIBRARY_CELL_METADATA` -> merged `MERGE_LIBRARY_METRICS`,
  `MERGE_CELL_METADATA`, `MAKE_TRIPLET_DGE` -> with donors `DONOR_METACELLS`, and with donors and a cell type column `DONOR_CELL_TYPE_METACELLS` and `DONOR_CELL_TYPE_REPORT`.
  For the live manifest the published files equal the baseline made by the prototype script (md5 of the decompressed content; the metacell header line is ignored).
- **Live data limits:** one real library (`SMRI_V11_rxn1`, a village with donors and MapMyCells results), no filters or joins in its manifest. So several things are covered
  only by Groovy function tests, not through the workflow (see 2.C).

## 2. Follow-up TODO (roughly in priority order)

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

### D. Google Batch
- **Session 10 (2026-10-21): the full pipeline ran on Google Batch (committed).** `tests/batch_full_run/run.sh` (live manifest, `-profile googlebatch`, `gs://` work and out under `gs://mccarroll_scrnaseq_central_temp/nextflow/aggregation_testing/`): 13 of 13 checks passed on the first run (baseline equality, top-level listing, `WRITE_*` in the head job, all tasks COMPLETED in the public images). Peaks: `MAKE_TRIPLET_DGE` 514 MB, others under 200 MB, tasks 2 to 7 s: the 16 GB / 6 GB requests are far above need (decide whether to lower them with a multi-library run; the retry setup already matches `mccarroll_nextflow`).
  Changes: `googlebatch` profile sets the `broad-allow` network, subnetwork, tag and exact `machineType`s (a wildcard like `n1-*` still triggers the deprecated Cloud Info selection and its warning; see `../credentials.md`, Machine types; Java steps now 15 GB then 30 GB, 6 cpus fixed); the nf-core institutional configs are no longer loaded (their `googlebatch` profile overrode ours; `custom_config_*` params removed); `gcp_credentials_file` defaults to null (docker profile and pre-flight use the ADC path then). Seqera: the compute environment sets work dir, location, VPC, tag, Wave and Fusion and no service account (so default Compute account); untested with this pipeline. Re-run after the exact types: no Cloud Info warning.
- **Seqera Platform (done, session 11):** the launcher `launchScrnaAggregation` exists in `mccarroll_tw_clp` and the pipeline is registered in two workspaces; see the DONE note at the top for the first run and the open machine type question. (Earlier plan, session 10: deferred until the rest of the analysis was settled.)
- (Below: session 7 notes; "next steps" 1 and 3 are done in session 10, see above.)
- **Settled in session 7 (details and commands in `../credentials.md`):**
  - Google Batch tasks run as the VM's service account. With no `google.batch.serviceAccountEmail`, that is the project's default Compute Engine account. Nextflow itself (on the laptop) uses the user's ADC.
  - **No service account setup is needed when the job runs in the project that owns the data.** Passed: `mccarroll-scrna-seq` (`LOCATE_SCRNA_ARTIFACTS` on the live manifest, output identical to the baseline YAML, work dir `gs://mccarroll_scrnaseq_central_temp/...`) and
    `bican-um1-mccarroll` (read of one 8.4 GiB BICAN FASTQ in `bican-um1-mccarroll_standard`, work dir `bican-um1-mccarroll_temp`). Failed (expected): `bican-um1-mccarroll` jobs writing the scranseq work bucket (cross-project, `Permission denied`).
  - **The project is passed at run time** with `GOOGLE_PROJECT_ID` (and `GOOGLE_LOCATION`, `-work-dir gs://...`). User decisions: keep the environment variable (no `--gcp_project` parameter), and NO pre-flight check, only documentation that the project must have access to the root bucket where the data lives.
  - `bican-um1-mccarroll` has no `default` VPC: Google Batch failed with `CODE_GCE_RESOURCE_NOT_FOUND`; the fix is `google.batch.network = 'global/networks/broad-allow'` and `google.batch.subnetwork = 'regions/us-central1/subnetworks/broad-allow'` (also exists in `mccarroll-scrna-seq`, which also has `default`).
  - The `drop-seq_python` image has no `python3` on the PATH; its Python is `/usr/local/dropseq/venv/dropseq/bin/python`.
  - nf-test cannot run on Google Batch (it always passes a local `-work-dir`, and a second `-w` is rejected), so the Google Batch checks are plain `nextflow run` scripts: `tests/batch_access_check/` (generic object read) and `modules/local/locate_scrna_artifacts/tests/gcs_batch_check.nf` + `gcs_batch.config`.
    Both are untracked and uncommitted. Note `gcs_batch_check.nf` sits next to `tests/nextflow.config`, which Nextflow auto-loads (a fixtures mount); `gcs_batch.config` clears `process.containerOptions` for that reason.
- **Next steps for Google Batch (none started):**
  1. Add the `broad-allow` network settings to the `googlebatch` profile in `nextflow.config` (currently only in the two check configs; `mccarroll-scrna-seq` works with either network). Decide the default project is NOT hardcoded.
  2. Decide the work bucket for real runs (`mccarroll_nextflow_test` in `mccarroll-scrna-seq` looks intended, but its IAM lists only a Seqera user; the tests used `mccarroll_scrnaseq_central_temp/nextflow/pipeline-testing/...`).
  3. Run the whole pipeline once with `-profile googlebatch` (needs the work dir, `--outdir`, and a decision on `gs://` vs local `--outdir`) and tune memory (below).
  4. Optional: a dedicated, narrower service account (`google.batch.serviceAccountEmail`); the Broad ones use long-lived JSON keys that should become short-lived tokens, and are over-privileged (Khalid Shakir). Seqera Cloud runs use the compute environment's service account (untested).
  5. A single run that mixes BICAN and scranseq libraries would need a cross-project grant (`roles/storage.objectViewer` for the VM service account on the other project's buckets).
- Scratch files from the checks can be deleted: `gs://mccarroll_scrnaseq_central_temp/nextflow/pipeline-testing/nf-test-batch-work/` and `gs://bican-um1-mccarroll_temp/nextflow/batch-access-check-work/`.
- **Memory:** `MAKE_TRIPLET_DGE`, `DONOR_METACELLS` and `DONOR_CELL_TYPE_METACELLS` are set to `cpus = 6` and `memory = { 15.GB * task.attempt }` (session 10; was 16 GB) in `conf/modules.config` (JVM heap = 80% of `task.memory`,
  the user's starting guess; "not an especially memory hungry process"). The label is still `process_medium` (nf-core template: 6 CPUs, 8 h); only memory is overridden. The single
  live library peaked at 625 MB resident memory for `MAKE_TRIPLET_DGE`, so tune with real multi-library sizes on Google Batch. There is no retry strategy (`errorStrategy`) yet.
- Check on Google Batch: the public images pull (`quay.io/broadinstitute/drop-seq_python:current`, `quay.io/broadinstitute/drop-seq_java:current`; `docker.registry = 'quay.io'` only prefixes names
  without a host); `gs://` reads of the artifact directory, cell metadata, MapMyCells csv and the 340 MB reduced GTF in the head job and in tasks; `the `exec` process `WRITE_TEXT_FILE` (it must run in the head job: confirm that no `WRITE_*` task is submitted as a Google Batch job) and
  the `output` block with a `gs://` `--outdir`; a real service-account key (same mount mechanism, untried); whether the Google client falls back to a key's `project_id` when
  `GOOGLE_CLOUD_PROJECT` is empty (untested); `process.resourceLimits` in `conf/test.config` (15 GB) vs the tasks.
- To test another image tag later (a branch build, with Seqera Platform or a config): `process { withName: 'X' { container = '...' } }`. The tags are hard coded in each module (`current`).

### E. Pre-flight and validation ideas (not coded)
- The pre-flight check could verify that every file the manifest names (DGEs, `joinFile`, `includeFile`, `excludeFile`) exists before any process starts.
- A manifest `donor` together with a village in the artifacts is accepted (as in the Python); decide whether to warn.
- Mixed donors across libraries is an error by decision (all libraries have donors or none).

### F. Unselected candidate tests (add when touching the unit)
LOCATE / SUMMARIZE: malformed YAML, newest-trace selection, stub. MERGE_LIBRARY_METADATA: ext.prefix, same barcode with different PREFIX, stub. FORMAT: meta / name, no prefix, ext.prefix, stub.
BUILD: duplicate join key, meta / name, ext.prefix, stub. MAKE_TRIPLET_DGE: single library, meta / names, stub. DONOR_CELL_TYPE_REPORT: numeric-looking donor ids kept as text, `ext.args --umi-column`, stub.
Workflow: entry args and files reaching BUILD; stub wiring run. Module names: the user was offered a review of the
remaining names (e.g. `LOCATE_SCRNA_ARTIFACTS`) and has not answered.

### G. Housekeeping
- **Prototype script and baseline:** `docs/specifications/scrna-aggregation_prototype.sh` still runs the Java tools in the PRIVATE image `us.gcr.io/mccarroll-scrna-seq/drop-seq_private_java:<tag>`
  (lines 103 to 104, default tag `current`); the public `quay.io/broadinstitute/drop-seq_java:current` has the same two tools, so switch it. The current baseline was made with local `jn_test`
  builds; the pipeline (public `current` images) reproduces it exactly for the live manifest. Remake the baseline with the public images when convenient (command in `../testing.md`).
- **Template leftovers:** `conf/test_full.config` duplicates `conf/test.config` (same manifest); `.github/` still has the nf-core template files; `tower.yml`; `modules.json` lists nf-core
  pieces only; the README has no workflow figure; `CHANGELOG.md` has one entry.
- **`versions`:** user decision: the hard-coded `current` image tags are the version record, no per-module version collection. `WRITE_VERSIONS` writes `pipeline_info/scrna-aggregation_software_versions.yml` from `workflowVersionToYAML()` (Nextflow and the pipeline only).
- **Docs:** `../output.md`, `../usage.md`, `../data_flow.md`, `../testing.md`, `../development.md`, `../credentials.md` were updated in session 6; `docs/README.md` is the index. The `README.md` is a
  short manual-written version; add a workflow figure if wanted.

## 3. Design decisions made (all user decisions unless marked)

- **Manifest:** the workflow parses it (`AggregationManifest`, strict schema, `dgeDefaults` projected deeply, entry wins; `donor` / `filters` / `joins` per entry; `libraryId` rejected). Manifest-only
  errors are reported in `PIPELINE_INITIALISATION` before any process. All manifest paths are absolute (local files or `gs://`); files named in `joinFile` / `includeFile` / `excludeFile` are staged by
  Nextflow under their base names (two files with one base name are rejected, as is a name equal to the library's own cell metadata, MapMyCells TSV, args file or output).
- **Library resolution (`lib/LibraryResolver.groovy`, head job, no process):** the library id is the artifact `uei`; an entry is matched to its artifact by `entry.dge == artifact.user_dge`. The library's
  DGE is the one the MANIFEST names, of any type (NOT donors-else-selected-cells as in the Python `resolve_aggregation_manifest`); the DGE may hold more barcodes than the cell metadata, the metadata selects
  the cells later. Cell metadata is the one the finder chose (the village's if there is a village). A resolver error stops the run (`Cannot resolve the libraries of <analysis>: <reason>`). Checks: unique ids
  that differ from the analysis id, one reference, one reduced GTF, MapMyCells results of one model (or `--mmc_model`), same cell type column in every library, all libraries have
  donors or none. The old `RESOLVE_LIBRARIES` process (TSV round trip) and `RESOLVE_AGGREGATION_MANIFEST` module were deleted.
- **Donors are known upfront, not from file headers:** a library has donors if its manifest entry has a `donor` or its artifacts have a village (`village_properties != NA`); `hasDonors` is true for the run
  if all do. Donor steps are gated on that, the cell type steps on the presence of a cell type column; a skipped step logs a warning.
- **Order:** libraries are merged in MANIFEST order (`position` in the record and in `meta_lib`); the merged metrics, the merged cell metadata and the triplet DGE are all made from ONE sorted list.
- **Per library item (typed since session 8):** the `Library` record in `workflows/scrna-aggregation.nf`: `id`, `meta` (`[id, analysis_id, mmc_model, position]`), `dge`, `cell_metadata`, `mmc_annotations` ('NA' for none), `args: List<String>`, `files: List<String>`. `LibraryResolver` still returns Groovy maps (`libraryId`, `position`, `hasDonor`, ...); `toLibraries` converts them.
- **Arguments:** `JoinFilterArguments.build(entry)` gives `args` and `files`; the workflow writes `<lib>.join_and_filter_args.txt` with the `WRITE_ARGS_FILE` exec process (work directory only) and BUILD reads it with
  `join_and_filter_tsv --args-file` (python repo branch `jn_modify_aggregation_python_tools`, public main #589). No `ext.args` for BUILD.
- **Summary for people:** `<outdir>/pipeline_info/<analysis>.resolved_libraries.txt`, plain text (reference, reduced GTF, donors, per library the DGE, cell metadata, MapMyCells, extra files and arguments); nothing reads it back.
- **Publishing (explicit: the `output` block and `publish:` in `main.nf`; nothing is published unless listed; module tests run one process and publish nothing):** merged results FLAT in `--outdir` (`<analysis>.library_metrics.txt`,
  `<analysis>.cell_metadata.txt`, `matrix.mtx.gz`, `barcodes.tsv.gz`, `features.tsv.gz`, `<analysis>.donor_cell_type.txt`, `<analysis>.donors.metacells.txt.gz`, `<analysis>.donor_cell_type.metacells.txt.gz`); per-library records in directories (`artifacts/<uei>.yaml`,
  `tearsheets/<uei>.standard_analysis_tearsheet.txt`); `pipeline_info/`. Per-library library metrics, joined cell metadata, MapMyCells TSV and args files stay in the work directory.
- **Containers:** hard coded in each module: `quay.io/broadinstitute/drop-seq_python:current` and `quay.io/broadinstitute/drop-seq_java:current` (both public; both checked to contain every tool and option the
  modules use). No image parameters. nf-test runs cap memory at 4 GB in `tests/nextflow.config`.
- **Reduced GTF:** staged from `gs://` (340 MB) in the live test; no override parameter was added.
- **Parameters:** `--manifest`, `--analysis_id` (letters, digits, `.`, `_`, `-`), `--outdir`, `--mmc_model`, `--mmc_level`, `--gcp_credentials_file`.
- **Tests:** one `main.nf.test` per module (fixtures self-contained, never shared), `tests/pipeline.synthetic.nf.test` (3 workflow tests on synthetic local libraries), live tests compare with the baseline, `tests/pipeline.live.nf.test` (2 tests: the whole pipeline vs the baseline incl. the
  exact top-level listing of `--outdir`, per-library intermediates in the work directory, every task in a public `current` image; and a resolver error stopping the run) and `tests/pipeline.validation.nf.test`.

## 4. Gotchas learned (move to `../development.md` if they keep mattering)
- `combine` flattens list items: wrap a list in a list (`ch.map { [it] }`) or it spreads into separate elements.
- (Old, `collectFile` is gone: `WRITE_TEXT_FILE` also creates an empty file for empty text.) `splitCsv` takes a `"` at the START of a field as a quote (not in the middle).
- `join` on maps (`meta`) works by equality, but key by `meta.id` when the maps come from different places. `toSortedList` returns ONE list of tuples (not flattened); the typed workflow uses `collect()` + `toSorted`. More typing gotchas: `../development.md` (Static typing).
- (Old: a null `publishDir` path failed every task. The `output` block has no such problem.) `path 'x'` in the `output` block nests: a file that is already `tearsheets/<f>` needs `path '.'`. A `Value` emit is typed `Value<Path>`, a queue channel `Channel<Path>`.
- A process script block cannot read a staged path (use a head-job `map` or pass text); `error()` inside an operator closure stops the run with that message.
- nf-test gives each run `output/` and `work/` side by side; tests find per-library intermediates by walking `work/` (a task's file and the links to it).
- macOS: `sed -i ''`, no `zcat` (use `gzip -dc`), Docker cannot see the Claude scratchpad (`/private/tmp/...`), `git rm` refuses files with local modifications.
- Commands over 120 s must run in the background; a `( ... &)` subshell finishes the task immediately (use a log file and a wait loop, or `run_in_background`).

## 5. Ground rules (from the user)
- Source of truth: `scrna-aggregation_prototype.sh`. Modules + nf-test unit tests first, leaf-first, one at a time, on small fixtures; then ONE workflow wiring tested modules one edge at a time.
  No subworkflows (the template's init subworkflow stays).
- Process per unit: clarification questions (two options each, existing support first) -> data contract -> severity-ranked candidate tests -> STOP for selection -> `nf-test generate` -> tests -> implement ->
  targeted tests. Do not implement unselected tests.
- Favor clarity and testability over fewer lines. Fixtures are self-contained per module (never shared). One test file per unit (`main.nf.test`; a separate file only for live vs synthetic; different args
  via test-level `config`).
- Module names describe the step, not the tool (the tool keeps its own name).
- Live tests: for modules that read `gs://` and modules that produce merged published files; they compare equality with the baseline file at that stage (md5 first, details only on mismatch).
- Do not commit / push unless asked. Never write into `/Users/nemesh/nextflow_aggregation_shell_script/out` (read-only old baseline). `tests/run_all_tests.sh` has no options.
  Keep `docs/testing.md`, `docs/development.md`, `docs/credentials.md` and this file updated.
- No long foreground commands (120 s limit): run in the background and wait for the notification.
- Add channel data-flow comments (input shape, output shape, `meta.id`, cardinality) above every channel definition in workflows.

## 6. Environment
- Docker containers cannot write into the Claude scratchpad: for prototype reruns use a git-ignored `testing*` directory at the repo root (and copy the reduced GTF from
  `tests/live_data/baseline/tmp/` into its `tmp/` to skip the 340 MB download). Read a tool's source with
  `docker run --rm --platform linux/amd64 --entrypoint cat <image> <path>` (python tools are under `/usr/local/dropseq/venv/dropseq/lib/python3.13/site-packages/dropseq/`; the Python source of the
  aggregation tools is in `/Users/nemesh/dropseqrna/transcriptome_java/public/src/python/src/dropseq/aggregation/`); the images run under emulation on this arm64 Mac, so allow time.
- nextflow 26.10.0, nf-test 0.9.5, docker (default nf-test profile `docker,test`). Images (linux/amd64, pulled by Docker): `quay.io/broadinstitute/drop-seq_python:current` (digest `f28d971a...`) and
  `quay.io/broadinstitute/drop-seq_java:current` (digest `e3230deb...`), checked on 2026-10-19.
- `GOOGLE_PROJECT_ID=bican-um1-mccarroll` (not a secret). The baseline is `tests/live_data/baseline` (git-ignored), made by the prototype script on `tests/live_data/manifest.yaml`; the command is in `../testing.md`.

## 7. Run the tests
```bash
export GOOGLE_PROJECT_ID=bican-um1-mccarroll
tests/run_all_tests.sh                                   # everything, 104 tests, about 12 minutes (needs the baseline, see ../testing.md)
nf-test test modules/local/<module>/tests/main.nf.test   # one file; --tag live runs all the live tests
nf-test test tests/pipeline.live.nf.test                 # the whole pipeline once vs the baseline, about a minute
```
Companion docs: `SPEC_SUMMARY.md` (what the prototype does; step -> module table), `../data_flow.md` (how the manifest and artifacts flow), `../testing.md` (running tests, live tests, fixtures, per-module
test catalog and contracts), `../development.md` (conventions, gotchas), `../credentials.md` (credentials, parameters), `../output.md`, `../usage.md`.

## 8. Modules (order follows the prototype's data flow)
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

## 9. Pre-flight check and profiles (implemented; details in `../credentials.md`)
`checkLocalGcpCredentials` runs first in `PIPELINE_INITIALISATION` (docker profile only) and fails before any process if the credentials file is missing, not
valid JSON, of an unsupported `type`, lacks required fields, or is an `authorized_user` file without `GOOGLE_PROJECT_ID`. 12 tests in
`tests/preflight.function.nf.test`. The `docker` profile mounts `params.gcp_credentials_file` into task containers and sets
`GOOGLE_APPLICATION_CREDENTIALS` / `GOOGLE_CLOUD_PROJECT`.
