# TODO

Only what is still to be done. Done work is in `DONE.md`; design decisions, gotchas and ground rules are in `../development.md`. Process for each item: clarification questions (two options each), data contract, severity-ranked candidate tests, STOP for the user's selection, then implement (see the ground rules in `../development.md`).

## Where we are: end of session 18 (2026-10-28)
- Pull request 6 is merged (h5ad step, optional QC step with outputs in `qc_plots/`, donor-level join, live QC test, Google Cloud Batch script, docs) and the git tag `prod` is on its merge, `6a25b5d`. The whole suite passed 141 of 141 and the Google Cloud Batch run passed 23 of 23 checks before the merge.
- Drop-seq pull request 594 is merged and the public image `current` is rebuilt (digest `sha256:8680c016…1152`).
- Decided: the workflow does not run QC by default (`run_qc` false); the tests do (`run_qc = true` in `tests/nextflow.config`). A manifest `donor` on a village is rejected by the resolver (a donor column exists only for a village).
- Colima: the profile `rosetta` runs the suite about twice as fast; see the last section of `../testing.md`. Check `docker context show` prints `colima-rosetta` before running the tests.
- The branch `jn_simplify_pipeline` (from `main`) is for the data flow simplifications below. Nothing is changed on it yet.

## Next: simplify the data flow (survey of session 18)
The data flow is sound (one record per library joined on `id`, one ordered list for the merged outputs, each gate in one place). The findings are repetition. Every item should leave the outputs unchanged, so the existing 141 tests (including the live one) check each step: after each item run `nextflow lint .` and the synthetic tests, and the whole suite once at the end. Process for each item as above; the choice still to make: items 1 to 4 only (recommended: mechanical, covered by the tests), or 1 to 6 (also touches `main.nf`, the init subworkflow and the schema checks).

Quick wins (`workflows/scrna-aggregation.nf`):
1. `library_order` is a projection of `libraries` (`id`, `analysis_id`, `position`) used in one join: join `summaries` with `libraries` directly and delete it.
2. Three gates use `.combine(x).flatMap { cond ? [item] : [] }` (`metacell_inputs`, `cell_type_inputs`, the QC one): use `.filter { ... }`. Check first that typed-DSL lint accepts it.
3. Three separate `.subscribe` warnings, two on `cell_type_column`: merge them into one block.
4. `Library.dge` and `Library.cell_metadata` are strings and `file(...)` is applied in three places (`build_input`, `built_sorted`, the H5AD join): make `toLibraries` produce `Path` fields once and drop the two `libraries.map { record(id, dge: file(...)) }` lambdas.

Medium (top-level plumbing):
5. `MCCARROLL_SCRNA_AGGREGATION` in `main.nf` only forwards 7 parameters and 15 emits to `SCRNA_AGGREGATION` (about 60 lines): have the entry workflow call `SCRNA_AGGREGATION` directly; the 15 outputs are then listed twice (emit, `publish:`) instead of three times.
6. The four QC options travel through every layer as four parameters: bundle them into one typed record `QcOptions` (one `take:` item per layer; simpler `checkQc*` functions).

Larger, optional (later):
7. The resolver uses the artifacts' `'NA'` string for "none" and `toLibraries` turns it back into `null`: use `null` in `LibraryResolver.resolve()` and drop the conversions (touches the resolver tests and `summaryText`).
8. `main.nf` declares nf-core template parameters that nothing here uses (`pipelines_testdata_base_path`, `trace_report_suffix`, the `config_profile_*` set): remove them (touches the schema and the nf-core utilities).
9. The helper for "join with the libraries, collect, then `toSorted` by `position`" (`metrics_sorted`, `built_sorted`), only if a typed function can read record fields (`a.position`) without a lint error.

Also: **purge leftover nf-core template code and documentation** (a separate pass, after or before the items above; check each candidate before deleting, and keep what the pipeline still uses). Candidates found by a quick look in session 18, none checked in detail:
- `.github/`: `CONTRIBUTING.md`, `ISSUE_TEMPLATE/`, `PULL_REQUEST_TEMPLATE.md`, `actions/` (do they match this repo's workflow, and are there workflows that run?). `.nf-core.yml` (the nf-core lint config; does it still do anything?).
- `subworkflows/nf-core/` (`utils_nextflow_pipeline`, `utils_nfcore_pipeline`, `utils_nfschema_plugin`, with their `tests/` and `meta.yml`, and `modules.json`): find which functions the pipeline calls (`workflowVersionToYAML`, `completionSummary`, the config and schema checks, `UTILS_NEXTFLOW_PIPELINE`) and drop the rest, or keep the three as installed code and delete only the unused stubs around them (the choice affects `modules.json` and the 4 nf-core test files in the suite).
- `main.nf`, `nextflow.config`, `nextflow_schema.json`, `conf/` (`base.config`, `test.config`): template parameters and profiles nothing uses (see item 8: `pipelines_testdata_base_path`, `trace_report_suffix`, `config_profile_*`, `help_full`, `show_hidden`, institutional profile hooks, the `test` profile).
- Docs: `docs/README.md`, `docs/usage.md` (sections copied from the template: the `-profile`, `-resume`, `-c` and `nf-core/configs` text, "Updating the pipeline", the links to `nf-core/launch`), `docs/output.md` (the "Pipeline information" boilerplate), `CHANGELOG.md` ("created with the nf-core template"), and the repository `README.md`.

Looked at and left alone: `cell_type_column` uses `''` for "none" (a value channel carrying `null` is risky); the head job reads the artifact YAMLs and donor files (errors appear before any process starts); the aliased modules (`MERGE_*`, the two `*_METACELLS`). Not read in depth: `AggregationManifest`, `JoinFilterArguments`, the modules' scripts and `conf/`.

## Needs more data
- **Tune memory** of the three Java steps (`MAKE_TRIPLET_DGE`, `DONOR_METACELLS`, `DONOR_CELL_TYPE_METACELLS`: now 15 GB, then 30 GB; the single live library peaked at 514 MB) and the default 6 GB of the other steps, with multi-library data sets on Google Batch. Keep the machine types in the `googlebatch` profile (`nextflow.config`) in step with the requests.

## Optional / ideas
- QC tests not written: a module test with a different set of donors across libraries is resolver-level only (`commonDonorFile` returns none, so no donor outputs; tested in `resolver.function.nf.test`), with no end-to-end test; tests 5 (conditions from a column), 7 (core cell types with an absent type), 8 and 9 (stub) of the `AGGREGATION_QC` candidate list were not selected.
- `modules.json` lists nf-core pieces only; `CHANGELOG.md` has one entry.
