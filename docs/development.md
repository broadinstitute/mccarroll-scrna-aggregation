# mccarroll/scrna-aggregation: Development

Coding conventions, known pitfalls, ground rules, design decisions and the environment. What is left to do is in [specifications/TODO.md](specifications/TODO.md) and what is done in [specifications/DONE.md](specifications/DONE.md). How to run the tests, the live tests, the fixtures and the test catalog are in
[testing.md](testing.md). Run everything from the repository root.

## Conventions

- Leaf-first, test-driven: each module is built and tested on its own before it is wired into the workflow.
- Test conventions (file layout, names, file layout) are in [testing.md](testing.md).
- Tool containers are fixed in each module: `quay.io/broadinstitute/drop-seq_python:current` and `quay.io/broadinstitute/drop-seq_java:current` (public images; the tools,
  including `join_and_filter_tsv --args-file`, were checked in the `current` images). To use another tag, set `container` for a process in a config with `process { withName: 'X' { container = '...' } }`.
- Run `nextflow lint .` after changing config or Nextflow files; it reports no errors or warnings (keep it that way). Workflow and include names must be valid identifiers: use underscores
  (`SCRNA_AGGREGATION`), never the hyphens of the pipeline name.

- Module names describe the step (`BUILD_LIBRARY_CELL_METADATA`), not the tool (`join_and_filter_tsv`). Optional tool arguments come from `task.ext.args` (BUILD_LIBRARY_CELL_METADATA is the exception: the manifest's arguments come in a staged args file read with `--args-file`).
- Java modules: image `quay.io/broadinstitute/drop-seq_java:current`, JVM heap `(task.memory.toMega() * 4).intdiv(5)` MB (`as int` is rejected by typing), and `--TMP_DIR` in the task
  directory (the container's default temp dir is not writable). Fixture tests set a small `process.resourceLimits`.

- Shared Groovy for tests lives in `tests/lib/` (`libDir` in `nf-test.config`), for example `LiveFiles.contentMd5` for the live comparisons: put
  repeated test helpers there instead of copying them between test files. (`projectDir` is only visible inside `when`/`then` blocks, not in suite-level closures.)

## Static typing

- Every script has `nextflow.enable.types = true`. Channel items are records (`record(meta: Map, ...)`; the per-library `Library` record is in `workflows/scrna-aggregation.nf`), `meta` stays a Map field. A typed process with
  one output uses a named record output (`name = record(...)`), because lint warns about several outputs.
- `params` is a typed block in `main.nf` only (a params block elsewhere is a lint error): types there, defaults in `conf/params.config` (included by `nextflow.config`, listed in `nf-test.config` triggers).
  A `String?` param is optional; a param that is not declared is an error. Path-like params are Strings on purpose (`gs://`).
- `help` is a `String?` with default `null`: `--help <name>` describes a parameter; a bare `--help` is intercepted in `PIPELINE_INITIALISATION` and prints the general help.
- Typed workflow rules met here: no `.out` (use the call's return value), no `set`/`tap`/`Channel.`, explicit closure parameters, no `filter` on a `Value` (use `flatMap { x -> cond ? [x] : [] }`),
  `collect()` + `toSorted` instead of `toSortedList`, `join(by: 'id')` on records, `.toList()` for `Iterable` vs `List`, `e.getMessage()`, `exit(0, "")`, `error()` in a closure needs a value after it.
  `collectFile` has no typed form: `WRITE_TEXT_FILE` is an `exec` process (runs in the head job; to be confirmed on Google Batch).
- Lists in a script string render as `[a, b]`: use `.join(' ')`.
- nf-test: inputs of typed processes are `record(...)` and outputs are read as `process.out.<name>[0].<field>`; INFO log output (the help) is in `${metaDir}/nextflow.log`, not in `workflow.stdout`.

## Gotchas

- **Error text can be on stdout or stderr** depending on the environment. In expected-failure tests assert on both:
  `(process.stdout + process.stderr).join('\n').contains('...')` (use `function.` for function tests).
- **`params` are null in an nf-test `config` file**, which loads before the pipeline params. Build paths there from
  `System.getProperty` or `System.getenv`. A null in a Docker mount like `-v ${params.x}:/path` makes Docker create a
  named volume called `null`, which shows up in the container as a directory. Remove it with `docker volume rm null`.
- On macOS, `sed -i` needs an empty suffix argument: `sed -i '' ...`.
- **`sed` on macOS** has no `\b` word boundary; use a plain case-sensitive replacement or `perl -pi -e`.
- **`${...}` inside a nf-test `process { """...""" }` string** is interpolated by nf-test in the test context. Resolve
  variables before the `process` block and interpolate only simple values.
- **nf-test `--filter`** selects test types (process, workflow, pipeline, function), not test names. See "How to run the
  tests" in [testing.md](testing.md).
- **nf-test needs `$HOME/.nf-test`** (its jar). If you point `HOME` elsewhere to simulate a missing credentials file, symlink it.
- **Shell variables do not persist** between separate commands in the agent tooling, and commands over 120 s must run in the
  background: pass `GOOGLE_PROJECT_ID=... command` inline.
- **Snapshots go stale.** Update one (`--update-snapshot`) only after inspecting the new output.
- **`.gitignore` patterns from the nf-core template are anchored to the repo root** (`/data/`, `/testing/`, `/testing*`).
  Unanchored, `data/` and `testing*` silently ignored `docs/testing.md` and the `tests/fixtures/data/` fixture files, so they were
  missing from a push. After adding files, check `git status --short --ignored` for anything unexpectedly ignored
  (expected: `.claude/`, `.nf-test/`, `.nf-test.log`).
- **The Python tools rewrite numbers** (`0.9000` -> `0.9`, `0.20` -> `0.2`): fixtures should have no trailing zeros, and tests compare the rewritten text.
- **Build a manifest or any multi-line text in the process script as one line** (e.g. `--YAML '{...}'`): the script block's indentation breaks YAML written
  with a heredoc, and an expected-failure test can then pass for the wrong reason, so assert the tool's own message.
- **nf-test writes `.nf-test-*.nf` temp files in the repo root** while it runs (git-ignored; lint counts them, so run `nextflow lint .` when no test is running).
- **Files under `/private/tmp/...` (the agent scratchpad) are not visible to Docker bind mounts**: mount from inside the repo instead.
- **The host Python has no `yaml` module**: use the container's Python (`docker run -i ... /usr/local/dropseq/venv/dropseq/bin/python - < script.py`).
- **macOS has no `zcat` for `.gz`** (it looks for `.Z`): use `gzip -dc` or `gzcat`.

- **`combine` flattens list items**: wrap a list in a list (`ch.map { [it] }`) or it spreads into separate elements.
- **`splitCsv` takes a `"` at the START of a field as a quote** (not in the middle).
- **`join` on maps (`meta`) works by equality**, but key by `meta.id` when the maps come from different places.
- **`path 'x'` in the `output` block nests**: a file that is already `tearsheets/<f>` needs `path '.'`. A `Value` emit is typed `Value<Path>`, a queue channel `Channel<Path>`.
- **A process script block cannot read a staged path** (use a head-job `map` or pass text); `error()` inside an operator closure stops the run with that message.
- **nf-test gives each run `output/` and `work/` side by side**; tests find per-library intermediates by walking `work/` (a task's file and the links to it).
- **`git rm` refuses files with local modifications**. A `( ... &)` subshell finishes an agent command immediately: use a log file and a wait loop, or `run_in_background`.
- **The `drop-seq_python` image has no `python3` on the PATH**; its Python is `/usr/local/dropseq/venv/dropseq/bin/python`.

## Ground rules (from the user)

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

## Design decisions (all user decisions unless marked)

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

## Environment

- Docker containers cannot write into the Claude scratchpad: for prototype reruns use a git-ignored `testing*` directory at the repo root (and copy the reduced GTF from
  `tests/live_data/baseline/tmp/` into its `tmp/` to skip the 340 MB download). Read a tool's source with
  `docker run --rm --platform linux/amd64 --entrypoint cat <image> <path>` (python tools are under `/usr/local/dropseq/venv/dropseq/lib/python3.13/site-packages/dropseq/`; the Python source of the
  aggregation tools is in `/Users/nemesh/dropseqrna/transcriptome_java/public/src/python/src/dropseq/aggregation/`); the images run under emulation on this arm64 Mac, so allow time.
- nextflow 26.10.0, nf-test 0.9.5, docker (default nf-test profile `docker,test`). Images (linux/amd64, pulled by Docker): `quay.io/broadinstitute/drop-seq_python:current` (digest `f28d971a...`) and
  `quay.io/broadinstitute/drop-seq_java:current` (digest `e3230deb...`), checked on 2026-10-19.
- `GOOGLE_PROJECT_ID=bican-um1-mccarroll` (not a secret). The baseline is `tests/live_data/baseline` (git-ignored), made by the prototype script on `tests/live_data/manifest.yaml`; the command is in `../testing.md`.

## Google Batch and Seqera (settled in sessions 7 to 11; details and commands in [credentials.md](credentials.md))

- Google Batch tasks run as the VM's service account (with no `google.batch.serviceAccountEmail`, the project's default Compute Engine account); Nextflow itself uses the user's Application Default Credentials. No service account setup is needed when the job runs in the project that owns the data; a job in one project writing another project's bucket fails with `Permission denied`.
- The project is passed at run time with `GOOGLE_PROJECT_ID` (and `GOOGLE_LOCATION`, `-work-dir gs://...`): user decision, no `--gcp_project` parameter and no pre-flight check, only documentation that the project must have access to the bucket where the data lives.
- `bican-um1-mccarroll` has no `default` VPC (Google Batch fails with `CODE_GCE_RESOURCE_NOT_FOUND`): the `googlebatch` profile sets the `broad-allow` network and subnetwork.
- nf-test cannot run on Google Batch (it always passes a local `-work-dir`), so the Google Batch checks are plain `nextflow run` scripts: `tests/batch_full_run/run.sh` (whole pipeline), `tests/batch_access_check/` and `modules/local/locate_scrna_artifacts/tests/gcs_batch_check.nf` + `gcs_batch.config` (this one sits next to `tests/nextflow.config`, which Nextflow auto-loads; `gcs_batch.config` clears `process.containerOptions` for that reason).
- Memory: `MAKE_TRIPLET_DGE`, `DONOR_METACELLS` and `DONOR_CELL_TYPE_METACELLS` have `cpus = 6` and `memory = { 15.GB * task.attempt }` in `conf/modules.config` (the label is still `process_medium`, only memory is overridden). Keep the machine types of the `googlebatch` profile in step with these requests.
