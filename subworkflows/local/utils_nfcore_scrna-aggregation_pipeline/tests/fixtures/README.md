Fixtures for the manifest tests (manifest.function.nf.test). Most manifests are inline YAML in the tests, so each case is next to its expectation.
- zamboni_aggregation.manifest.yaml: a copy of the manifest of the original Zamboni workflow's own validator test (two DGEs, dgeDefaults with a
  numeric `min` and a boolean `exclude`). Both DGEs have no filters, so each gets both default filters.
The real manifests of the live tests (tests/live_data/manifest.yaml, manifest_no_donors.yaml) are read from there.
- basename_collision.manifest.yaml: two different files with the same base name in one DGE entry (an error before any process runs).
- artifact_lib_a.yaml: a copy of the artifact file that LOCATE_SCRNA_ARTIFACTS writes for a library with a donor DGE and one MapMyCells model (the
  resolver tests build the other artifacts in the test from the few fields the resolver reads).
