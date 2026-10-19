# Live test inputs

Manifests of real `gs://` DGEs (bucket `mccarroll_scrnaseq_central_temp`, project `bican-um1-mccarroll`) used by the live
tests (`tests/run_all_tests.sh`) and as input of the prototype script
`docs/specifications/scrna-aggregation_prototype.sh`, which produces the baseline the live tests compare against.

| File | Scenario |
|---|---|
| `manifest.yaml` | library `SMRI_V11_rxn1`, village donor DGE (donors, MapMyCells). The validated reference run. |
| `manifest_no_donors.yaml` | same library without donors: selected-cells DGE, exercises the no-donor skip branches (not yet run) |

The baseline output (analysis id `SMRI_V11.unfiltered`) is generated into `tests/live_data/baseline/`, which is git-ignored,
so it is never committed. See `docs/testing.md`, "Live tests".
