# mccarroll/scrna-aggregation: Development

Coding conventions and known pitfalls. How to run the tests, the live tests, the fixtures and the test catalog are in
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
