# mccarroll/scrna-aggregation: Development and testing

Tests use [nf-test](https://www.nf-test.com) (0.9.5). Run everything from the repository root.

## Conventions

- Leaf-first, test-driven: each module is built and tested on its own before it is wired into the workflow.
- Unit tests sit next to the unit, as in nf-core: `modules/local/<tool>/tests/main.nf.test`, with a `nextflow.config`
  and `fixtures/` beside it. Pipeline-level tests go in the top-level `tests/`.
- Test names start with `Should ...`.
- One test file per concern. Keep tests for different behavior in separate files next to each other, so a file stays
  readable and can be run alone. nf-test has no way for one file to include another; it discovers every `*.nf.test`
  under the path you give it. Use tags to run a group across files.
- Tool containers are parameters (`--python_image`, `--image_tag`, default `jn_test`). Local images must already exist.
- Run `nextflow lint .` after changing config or Nextflow files. Two errors are known, both from the template's
  hyphenated name `SCRNA-AGGREGATION`, which will be fixed when the workflow is wired.

## How to run the tests

| What | Needs | Command |
|---|---|---|
| Pre-flight credentials check (12 tests, `preflight.function.nf.test`) | nothing | `nf-test test subworkflows/local/utils_nfcore_scrna-aggregation_pipeline/` (all tests in the directory), or `nf-test test --tag preflight` |
| `LOCATE_SCRNA_ARTIFACTS`, fixture tests (6) | Docker and the `jn_test` image | `nf-test test modules/local/locate_scrna_artifacts/tests/main.nf.test --profile docker,test` |
| `LOCATE_SCRNA_ARTIFACTS`, live `gs://` test (1) | Docker, network, ADC, the two variables below | see below |

Live test:

```bash
GOOGLE_PROJECT_ID=bican-um1-mccarroll \
SCRNA_LIVE_MANIFEST=<path to a manifest of real gs:// DGEs> \
nf-test test modules/local/locate_scrna_artifacts/tests/gcs.nf.test --profile docker,test
```

The live test prints the path of each generated artifact YAML. To also compare each one field by field to a
validated baseline, for example the `artifacts` directory of a prototype shell script run, add
`SCRNA_LIVE_BASELINE_DIR=<directory of <uei>.yaml files>`. The test then prints each baseline path and either
`matches baseline` or every differing field with both values, and it fails on any difference.

Notes:

- Run one test by name with `--filter`, and one by tag with `--tag`.
- Do not run `nf-test test .` unless `SCRNA_LIVE_MANIFEST` is set, because it includes the live test.
  Select by path instead.
- `nf-test.config` sets the default profile to `test`. `--profile docker,test` is needed for tests that
  run containers.
- Test output goes to `.nf-test/`, which is git-ignored.

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
| `gcs.nf.test` | Critical | live: real `gs://` manifest with the mounted credentials gives correctly named YAMLs with `gs://` paths; prints the YAML paths; with `SCRNA_LIVE_BASELINE_DIR`, must equal the baseline field by field |

## Gotchas

- **Error text can be on stdout or stderr** depending on the environment. In expected-failure tests assert on both:
  `(process.stdout + process.stderr).join('\n').contains('...')` (use `function.` for function tests).
- **`params` are null in an nf-test `config` file**, which loads before the pipeline params. Build paths there from
  `System.getProperty` or `System.getenv`. A null in a Docker mount like `-v ${params.x}:/path` makes Docker create a
  named volume called `null`, which shows up in the container as a directory. Remove it with `docker volume rm null`.
- On macOS, `sed -i` needs an empty suffix argument: `sed -i '' ...`.
