# TODO

Only what is still to be done. Done work is in `DONE.md`; design decisions, gotchas and ground rules are in `../development.md`. Process for each item: clarification questions (two options each), data contract, severity-ranked candidate tests, STOP for the user's selection, then implement (see the ground rules in `../development.md`).

## Where we are: end of session 18 (2026-10-28). Start here

**State**
- **Sessions 14 to 18 are committed in one commit** on the branch `jn_aggregation_qc` (the session 14 h5ad step, the QC step, the live QC test, the Google Cloud Batch script `tests/google_cloud_batch_run/`, the donor-level join, the docs). One project ID, `mccarroll-scrna-seq`, is used everywhere.
- **Drop-seq repository:** pull request 594 is merged (`join_and_filter_tsv` joins on a `--set` column, never replaces data, returns the exit status) and the public image tagged `current` was rebuilt (digest `sha256:8680c016…1152`). The temporary `jn_test` image and `tests/synthetic_jn_test.config` are gone. The Zamboni check is closed: the data has no `PREFIX` column, and the shell script is the source of truth (the Zamboni workflow is not consulted). The submodule `transcriptome_java/public` is back on `master`.
- **Tests:** the pipeline tests now run QC by default (`run_qc = true` in `tests/nextflow.config`; the pipeline default stays false). With the public `current` image the whole suite passed 141 of 141 (776 s) on 2026-10-28, after two `BUILD_LIBRARY_CELL_METADATA` tests were changed to use the fixture `cmd_no_donor.tsv` (`--set donor` no longer replaces a `donor` column, pull request 594). Earlier, with `jn_test`, 141 of 141 passed. Also `nextflow lint .` is clean (55 files). The Google Cloud Batch run passed 22 of 22 checks. `null/` was deleted and was not recreated by the suite.
- **Colima:** the profile `rosetta` (`vz`, Rosetta, `virtiofs`) runs the suite about twice as fast; see the last section of `../testing.md`. Check `docker context show` prints `colima-rosetta` before running the tests.

**Pick up here, in this order** (each item follows the process above: questions, data contract, candidate tests, stop)
1. (Done in session 18: whole suite, `jn_test` cleanup, commit.) Rerun the whole suite once more when convenient, now that every test uses `current`.
2. (Done in session 18: the Zamboni checks for pull request 594 are closed, see "Drop-seq repository" above.)
3. (Done in session 18: the docs of the QC feature.)
4. **Open decisions**: item 4 below (run QC by default; PDFs in a `qc/` subdirectory; move the `prod` tag).
5. **Housekeeping**: delete the Google Batch scratch data (see "Before the next release"); delete `null/` and check it does not come back (see "Tests and validation").

## Before the next release
- Open the pull request for the branch `jn_aggregation_qc` (it includes the session 14 h5ad step and the QC step), and after the merge move the git tag `prod` (it is on `d76e217`, the merge of PR #4) so Seqera runs pick up the h5ad and QC steps.
- (Done in session 17: the whole suite, 135 tests, passed on 2026-10-28, before the donor-join and resolver tests were added (expected total now 141, not yet run), and `tests/google_cloud_batch_run/run.sh` passed 22 of 22 checks, including the h5ad and QC files. Left: rerun the whole suite, the commit and the scratch data.)
- Delete the scratch data of the Google Batch checks: `gs://mccarroll_scrnaseq_central_temp/nextflow/aggregation_testing/{work,out}`, `gs://mccarroll_scrnaseq_central_temp/nextflow/pipeline-testing/nf-test-batch-work/` and `gs://bican-um1-mccarroll_temp/nextflow/batch-access-check-work/`.

## New feature: optional aggregation QC step
The plan, the decisions and the design are in `aggregation_qc_plan.md` (same directory); read its "Status and next step" first. **Done (sessions 15 and 16):** the Python tool `aggregation_qc` (public image `current`), the prototype step, and in this repo the module `AGGREGATION_QC`, the params, the workflow edge, publishing and the pre-flight checks (see `DONE.md`, "Aggregation QC", and `../development.md`). **Nothing of session 16 is committed** (branch `jn_aggregation_qc`; `git status` lists the files). **Left**, in this order; each item follows the process above (questions, data contract, severity-ranked candidate tests, STOP):

1. (Done in session 17: `tests/pipeline.live.nf.test` runs the pipeline with `run_qc = true`, reads the `gs://` donor file in the head job, and compares `donor_qc.txt` with the baseline, checks the 8 PDFs and the exact top-level listing; `tests/google_cloud_batch_run/run.sh` does the same on Google Cloud Batch. See `DONE.md`.)
2. (Done in session 18: `docs/output.md`, `docs/usage.md` (params, example, core cell types), `docs/data_flow.md`, the README and its figure, `SPEC_SUMMARY.md`, `CHANGELOG.md`.)
3. (Done in session 18: committed.)
4. **Open questions** (the plan's "Open items"): run QC by default in production runs or only on request (now only on request, `run_qc` default false), and publish the PDFs into a subdirectory such as `qc/` (now flat with the legacy names; decide before the first release). Also: move the `prod` tag of this repo before turning `run_qc` on in a real run (the Nextflow modules use the `current` image, which already has `aggregation_qc`).
5. **Not done, optional:** a module test with a different set of donors across libraries is resolver-level only (`commonDonorFile` returns none, so no donor outputs; tested in `resolver.function.nf.test`), with no end-to-end test; tests 5 (conditions from a column), 7 (core cell types with an absent type), 8 and 9 (stub) of the `AGGREGATION_QC` candidate list were not selected and not written.

## Needs more data
- **Tune memory** of the three Java steps (`MAKE_TRIPLET_DGE`, `DONOR_METACELLS`, `DONOR_CELL_TYPE_METACELLS`: now 15 GB, then 30 GB; the single live library peaked at 514 MB) and the default 6 GB of the other steps, with multi-library data sets on Google Batch. Keep the machine types in the `googlebatch` profile (`nextflow.config`) in step with the requests.

## Workflow data flow
The session 12 review is done (session 13, see `DONE.md`), except one optional item:
- A helper function for the "join with the libraries, collect, then `toSorted` by `position`" step (`metrics_sorted`, `built_sorted`). Check first that a typed function can read record fields (`a.position`) without a lint error.

## Tests and validation
- **Find out where the `null/` directory in the repository root comes from, and stop it being created.** It is git-ignored and holds only `pipeline_info/` with 148 Nextflow reports, timelines and traces (about 131 MB), dated 19 to 21 October (session 8 to 9 test runs). The likely cause: `params.outdir` is `null` by default (`conf/params.config`), and `nextflow.config` writes the `timeline`, `report`, `trace` and `dag` files to `${params.outdir}/pipeline_info/...`, so any run without `--outdir` writes into a directory literally named `null` in the working directory. Candidates are the nf-test tests that run the pipeline script or a module with no `outdir` param (function tests, `tests/pipeline.validation.nf.test`, module tests). Nothing has been added since 21 October, although the h5ad tests of session 14 ran many tests, so something may already have fixed it: check by deleting `null/`, running the whole suite (`tests/run_all_tests.sh`) and looking for a new `null/`. If it comes back, find which test creates it, then give those runs an `outdir` (for example in `tests/nextflow.config`) or make the report paths not depend on a null `outdir`. This is not the Docker `null` volume described in `development.md` (that one is removed with `docker volume rm null`). Then delete the directory. **Session 17:** the whole suite ran (135 tests) and wrote nothing new to `null/` (its newest file is from 21 October), so the cause may already be fixed; delete the directory and check again on the next whole-suite run.
- (Done in sessions 17 and 18: the donor-level join; pull request 594 is merged and the synthetic tests use the public image `current`. The resolver rejects a manifest `donor` for a village. See `DONE.md`.)
- (Done in session 17: a manifest `donor` for a village is rejected by the resolver, before any process starts. `resolve_aggregation_manifest.py` and the Zamboni workflow still accept it: a follow-up for the Drop-seq repository.)

## Optional / ideas
- `modules.json` lists nf-core pieces only; `CHANGELOG.md` has one entry.
