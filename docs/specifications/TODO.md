# TODO

Only what is still to be done. Done work is in `DONE.md`; design decisions, gotchas and ground rules are in `../development.md`. Process for each item: clarification questions (two options each), data contract, severity-ranked candidate tests, STOP for the user's selection, then implement (see the ground rules in `../development.md`).

## Before the next release
- Commit the session 14 work (branch `jn_add_new_features`: module `BUILD_LIBRARY_H5AD`, its workflow edge, `conf/modules.config`, tests, docs, the README figure in `docs/figures/` and step 5b of the prototype script), open the PR, and after the merge move the git tag `prod` (it is on `d76e217`, the merge of PR #4) so Seqera runs pick up the h5ad step. Nothing of it is committed yet.
- Run what session 14 did not: the whole suite once (`tests/run_all_tests.sh`, 118 tests; session 14 ran the h5ad module tests (8), the synthetic pipeline tests (9) and the live pipeline test (2)) and the Google Batch check `tests/batch_full_run/run.sh`, which now also compares `h5ad/` with the baseline (edited, not run).
- Delete the scratch data of the Google Batch checks: `gs://mccarroll_scrnaseq_central_temp/nextflow/aggregation_testing/{work,out}`, `gs://mccarroll_scrnaseq_central_temp/nextflow/pipeline-testing/nf-test-batch-work/` and `gs://bican-um1-mccarroll_temp/nextflow/batch-access-check-work/`.

## New feature: optional aggregation QC step
The plan, with the decisions, the Python tool design, the Nextflow process and the order of work, is in `aggregation_qc_plan.md` (same directory). Not started. The Python tool (`aggregation_qc` in the Drop-seq repo) and the QC step of the prototype script come before the Nextflow process.

## Needs more data
- **Tune memory** of the three Java steps (`MAKE_TRIPLET_DGE`, `DONOR_METACELLS`, `DONOR_CELL_TYPE_METACELLS`: now 15 GB, then 30 GB; the single live library peaked at 514 MB) and the default 6 GB of the other steps, with multi-library data sets on Google Batch. Keep the machine types in the `googlebatch` profile (`nextflow.config`) in step with the requests.

## Workflow data flow
The session 12 review is done (session 13, see `DONE.md`), except one optional item:
- A helper function for the "join with the libraries, collect, then `toSorted` by `position`" step (`metrics_sorted`, `built_sorted`). Check first that a typed function can read record fields (`a.position`) without a lint error.

## Tests and validation
- **Find out where the `null/` directory in the repository root comes from, and stop it being created.** It is git-ignored and holds only `pipeline_info/` with 148 Nextflow reports, timelines and traces (about 131 MB), dated 19 to 21 October (session 8 to 9 test runs). The likely cause: `params.outdir` is `null` by default (`conf/params.config`), and `nextflow.config` writes the `timeline`, `report`, `trace` and `dag` files to `${params.outdir}/pipeline_info/...`, so any run without `--outdir` writes into a directory literally named `null` in the working directory. Candidates are the nf-test tests that run the pipeline script or a module with no `outdir` param (function tests, `tests/pipeline.validation.nf.test`, module tests). Nothing has been added since 21 October, although the h5ad tests of session 14 ran many tests, so something may already have fixed it: check by deleting `null/`, running the whole suite (`tests/run_all_tests.sh`) and looking for a new `null/`. If it comes back, find which test creates it, then give those runs an `outdir` (for example in `tests/nextflow.config`) or make the report paths not depend on a null `outdir`. This is not the Docker `null` volume described in `development.md` (that one is removed with `docker volume rm null`). Then delete the directory.
- **Donor-level join (new pipeline test, for a future session; not developed yet).** The only joins tested so far are at the cell level (`leftColumn: cell_barcode` with a `cell`/`extra_flag` file, in the synthetic pipeline test and in `BUILD_LIBRARY_CELL_METADATA`). Add a test that joins data at the donor level: a small file with the donor ID, the donor's age (numeric) and sex (`male`/`female`), named as a `joinFile` with `leftColumn: donor` (and the file's donor column as `joinColumn`), so that every cell gets the age and sex of its donor. Things to settle in the process (questions, data contract, severity-ranked candidate tests, then stop for selection):
  - the join must see the donor: `JoinFilterArguments` puts `--set donor` first and then the joins in manifest order, so a donor from the manifest is available, and a village's `donor` column comes from the cell metadata; check both cases (a manifest donor, and a village with several donors);
  - cells keep their number (many cells to one donor row; the Python merge is `many_to_one`, so duplicate donor IDs in the file must fail with a clear message) and a donor missing from the file gives missing values, not dropped cells;
  - the age stays numeric and the sex a category in the merged `<analysis>.cell_metadata.txt` and in the obs of each h5ad (through `sanitize_dataframe`), including a missing value in either column;
  - where: a synthetic pipeline test with a donor file fixture next to `files/extra.tsv`, a module test of `BUILD_LIBRARY_CELL_METADATA` with a donor-keyed join, and perhaps the live manifest (`tests/live_data/manifest.yaml` has no joins); update `docs/usage.md` with the example.
- **Pre-flight idea (not coded):** warn when a manifest `donor` is given together with a village in the artifacts (accepted today, as in the Python).

## Optional / ideas
- `modules.json` lists nf-core pieces only; `CHANGELOG.md` has one entry.
