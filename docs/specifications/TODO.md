# TODO

Only what is still to be done. Done work is in `DONE.md`; design decisions, gotchas and ground rules are in `../development.md`. Process for each item: clarification questions (two options each), data contract, severity-ranked candidate tests, STOP for the user's selection, then implement (see the ground rules in `../development.md`).

## Before the next release
- Commit the session 13 work (branch `jn_simplify_dataflow`; `tests/run_all_tests.sh` passed 110 of 110 on it, 791 s).
- Run `tests/batch_full_run/run.sh` on Google Batch: the record shapes changed (top-level `id`, no `meta`), and the new manifest file check reads `gs://` from the head job, which no Google Batch or Seqera run has done yet. If the head job's credentials cannot read a data bucket, the run now stops at the start.
- Then move the git tag `prod` to the latest commit (it is on `b6d1788`, the merge of PR #3) so Seqera runs pick up the changes.
- Delete the scratch data of the Google Batch checks: `gs://mccarroll_scrnaseq_central_temp/nextflow/aggregation_testing/{work,out}`, `gs://mccarroll_scrnaseq_central_temp/nextflow/pipeline-testing/nf-test-batch-work/` and `gs://bican-um1-mccarroll_temp/nextflow/batch-access-check-work/`.

## Needs more data
- **Tune memory** of the three Java steps (`MAKE_TRIPLET_DGE`, `DONOR_METACELLS`, `DONOR_CELL_TYPE_METACELLS`: now 15 GB, then 30 GB; the single live library peaked at 514 MB) and the default 6 GB of the other steps, with multi-library data sets on Google Batch. Keep the machine types in the `googlebatch` profile (`nextflow.config`) in step with the requests.

## Workflow data flow
The session 12 review is done (session 13, see `DONE.md`), except one optional item:
- A helper function for the "join with the libraries, collect, then `toSorted` by `position`" step (`metrics_sorted`, `built_sorted`). Check first that a typed function can read record fields (`a.position`) without a lint error.

## Tests and validation
- **Pre-flight idea (not coded):** warn when a manifest `donor` is given together with a village in the artifacts (accepted today, as in the Python).

## Optional / ideas
- `modules.json` lists nf-core pieces only; `CHANGELOG.md` has one entry.
