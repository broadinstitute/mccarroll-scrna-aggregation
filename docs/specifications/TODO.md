# TODO

Only what is still to be done. Done work is in `DONE.md`; design decisions, gotchas and ground rules are in `../development.md`. Process for each item: clarification questions (two options each), data contract, severity-ranked candidate tests, STOP for the user's selection, then implement (see the ground rules in `../development.md`).

## Before the next release
- Re-run `tests/run_all_tests.sh` after the session 12 config cleanup (needs `GOOGLE_PROJECT_ID`, Docker, network, credentials and the baseline; about 12 minutes), commit, then move the git tag `prod` to the latest commit (it is on `387aad2`) so Seqera runs pick up the changes.
- Delete the scratch data of the Google Batch checks: `gs://mccarroll_scrnaseq_central_temp/nextflow/aggregation_testing/{work,out}`, `gs://mccarroll_scrnaseq_central_temp/nextflow/pipeline-testing/nf-test-batch-work/` and `gs://bican-um1-mccarroll_temp/nextflow/batch-access-check-work/`.

## Needs more data
- **Tune memory** of the three Java steps (`MAKE_TRIPLET_DGE`, `DONOR_METACELLS`, `DONOR_CELL_TYPE_METACELLS`: now 15 GB, then 30 GB; the single live library peaked at 514 MB) and the default 6 GB of the other steps, with multi-library data sets on Google Batch. Keep the machine types in the `googlebatch` profile (`nextflow.config`) in step with the requests.

## Simplifications of the workflow data flow (review of session 12)
Review of `workflows/scrna-aggregation.nf` and the 8 modules (not `main.nf`, the init subworkflow or `lib/`). None of these should change the published files; the synthetic pipeline test and the live baseline comparison are the safety net. Items marked "verify" depend on how typed records behave in Nextflow 26.10 and need a quick spike first.

**Worth doing (clear wins, low risk), suggested first:**
1. **Drop `WRITE_ARGS_FILE`, `args_files` and a join.** `BUILD_LIBRARY_CELL_METADATA` takes `args: List<String>` and writes its own args file in the script (as `MAKE_TRIPLET_DGE` does for `manifest.yaml`). Removes an alias, a channel, a join, the fragile `f.name.replace('.join_and_filter_args.txt', '')` id parsing and the empty-file case. Risk: shell quoting of filter values (covered by the `JoinFilterArguments` tests and the synthetic pipeline test).
2. **Drop `artifact_files` and its join.** Each library's artifact is always `<id>.yaml` in the located directory: `libraries.combine(located)` plus a `map` that resolves it replaces the directory listing and the join on `id` (which silently drops a library without a YAML).
3. **`Library.mmc_annotations` as `String?` (null for none) instead of the `'NA'` sentinel.** Convert once in `toLibraries`; the two `LibraryResolver.NA` filters become truthiness checks.

**Probably worth it, verify first:**
4. **Replace the `mmc_tsvs` `mix` with null records** (`libraries_with_mmc`) by `libraries.join(annotations, by: 'id', remainder: true)`.
5. **Simpler donor gating, verify first:** `filter` on a `Value` is not allowed with static typing (see `../development.md`), which is why `metacell_inputs` and `cell_type_inputs` combine in `has_donors` / `column` and `flatMap` to `[item]` or `[]`. Look for a simpler form (for example one gate record shared by both steps), and check whether the three `.map { record(meta, matrix, features, ... ) }` re-listings can go if records with extra fields are accepted by a process input.
6. **`MAKE_TRIPLET_DGE`: one list of `record(prefix, dge, barcode_list)`** instead of the three parallel lists (`prefixes`, `dges`, `barcode_lists`), which makes a length mismatch impossible and removes the size check in the script. Verify that paths in nested records are staged.

**Smaller or optional:**
- A helper function for the repeated analysis meta `[ id: items[0].meta.analysis_id ]` and the "collect, then `toSorted` by `meta.position`" step (`metrics_sorted`, `built_sorted`).
- Records carry both `id` and `meta` (with `id`), so the workflow re-maps `record(id: item.meta.id, ...)` only to join. A top-level `id` in the module records would remove that but touches every module and test: leave as is.
- Comment fix: `MERGE_LIBRARY_METADATA` says the inputs are sorted "by library id"; they are in manifest order.

## Tests and validation
- **Unselected candidate tests** (add when touching the unit). LOCATE / SUMMARIZE: malformed YAML, newest-trace selection, stub. MERGE_LIBRARY_METADATA: ext.prefix, same barcode with different PREFIX, stub. FORMAT: meta / name, no prefix, ext.prefix, stub. BUILD: duplicate join key, meta / name, ext.prefix, stub. MAKE_TRIPLET_DGE: single library, meta / names, stub. DONOR_CELL_TYPE_REPORT: numeric-looking donor ids kept as text, `ext.args --umi-column`, stub. Workflow: entry args and files reaching BUILD; stub wiring run.
- **Module names:** the user was offered a review of the remaining names (e.g. `LOCATE_SCRNA_ARTIFACTS`) and has not answered.
- **Pre-flight ideas (not coded):** verify that every file the manifest names (DGEs, `joinFile`, `includeFile`, `excludeFile`) exists before any process starts; warn when a manifest `donor` is given together with a village in the artifacts (accepted today, as in the Python).

## Optional / ideas
- Remake the baseline (`tests/live_data/baseline`) with the public images (it was made with local `jn_test` builds; the pipeline reproduces it exactly). Command in `../testing.md`.
- A dedicated, narrower service account (`google.batch.serviceAccountEmail`); the Broad ones use long-lived JSON keys that should become short-lived tokens and are over-privileged (Khalid Shakir). Untested: a real service-account key through the docker profile mount, and whether the Google client falls back to a key's `project_id` when `GOOGLE_CLOUD_PROJECT` is empty.
- A single run mixing BICAN and scranseq libraries would need a cross-project grant (`roles/storage.objectViewer` for the VM service account on the other project's buckets).
- A workflow figure in the README; `modules.json` lists nf-core pieces only; `CHANGELOG.md` has one entry.
- Update `SPEC_SUMMARY.md` where it still describes the prototype's own `--reference` and the `ext.args` plan for the filter/join arguments (superseded).
