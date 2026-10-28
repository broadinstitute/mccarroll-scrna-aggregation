# TODO

Only what is still to be done. Done work is in `DONE.md`; design decisions, gotchas and ground rules are in `../development.md`. Process for each item: clarification questions (two options each), data contract, severity-ranked candidate tests, STOP for the user's selection, then implement (see the ground rules in `../development.md`).

## Where we are: end of session 18 (2026-10-28)
- Branch `jn_aggregation_qc` is pushed and **pull request https://github.com/broadinstitute/mccarroll-scrna-aggregation/pull/6 is open** (h5ad step, QC step, donor-level join, live QC test, Google Cloud Batch script, docs). The whole suite passed 141 of 141 on the public image `current`; `nextflow lint .` is clean. The Google Cloud Batch run passed 23 of 23 checks after the `qc_plots/` change.
- Drop-seq pull request 594 is merged and the public image `current` is rebuilt (digest `sha256:8680c016…1152`).
- Decided: the workflow does not run QC by default (`run_qc` false); the tests do (`run_qc = true` in `tests/nextflow.config`).
- Colima: the profile `rosetta` runs the suite about twice as fast; see the last section of `../testing.md`. Check `docker context show` prints `colima-rosetta` before running the tests.

## Next
1. After the merge of pull request 6, move the git tag `prod` (it is on `d76e217`, the merge of PR #4) so Seqera runs pick up the h5ad and QC steps. Do it before turning `run_qc` on in a real run.

## Needs more data
- **Tune memory** of the three Java steps (`MAKE_TRIPLET_DGE`, `DONOR_METACELLS`, `DONOR_CELL_TYPE_METACELLS`: now 15 GB, then 30 GB; the single live library peaked at 514 MB) and the default 6 GB of the other steps, with multi-library data sets on Google Batch. Keep the machine types in the `googlebatch` profile (`nextflow.config`) in step with the requests.

## Optional / ideas
- QC tests not written: a module test with a different set of donors across libraries is resolver-level only (`commonDonorFile` returns none, so no donor outputs; tested in `resolver.function.nf.test`), with no end-to-end test; tests 5 (conditions from a column), 7 (core cell types with an absent type), 8 and 9 (stub) of the `AGGREGATION_QC` candidate list were not selected.
- A helper function for the "join with the libraries, collect, then `toSorted` by `position`" step (`metrics_sorted`, `built_sorted`). Check first that a typed function can read record fields (`a.position`) without a lint error.
- `modules.json` lists nf-core pieces only; `CHANGELOG.md` has one entry.
