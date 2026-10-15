# mccarroll/scrna-aggregation: Development

Coding conventions and known pitfalls. How to run the tests, the live tests, the fixtures and the test catalog are in
[testing.md](testing.md). Run everything from the repository root.

## Conventions

- Leaf-first, test-driven: each module is built and tested on its own before it is wired into the workflow.
- Test conventions (file layout, names, one file per concern) are in [testing.md](testing.md).
- Tool containers are parameters (`--python_image`, `--image_tag`, default `jn_test`). Local images must already exist.
- Run `nextflow lint .` after changing config or Nextflow files; it currently reports no errors (some unused-parameter
  warnings from the template remain). Workflow and include names must be valid identifiers: use underscores
  (`SCRNA_AGGREGATION`), never the hyphens of the pipeline name.

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
- **nf-test `--filter`** selects test types (process, workflow, pipeline, function), not test names. See "Running one file or
  one test" in [testing.md](testing.md).
- **nf-test needs `$HOME/.nf-test`** (its jar). If you point `HOME` elsewhere to simulate a missing credentials file, symlink it.
- **Shell variables do not persist** between separate commands in the agent tooling, and commands over 120 s must run in the
  background: pass `GOOGLE_PROJECT_ID=... command` inline.
- **Snapshots go stale.** Update one (`--update-snapshot`) only after inspecting the new output.
