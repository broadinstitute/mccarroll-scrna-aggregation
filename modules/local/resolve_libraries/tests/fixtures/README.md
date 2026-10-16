# Fixtures of RESOLVE_LIBRARIES

Artifact files as LOCATE_SCRNA_ARTIFACTS writes them (the paths are not read, only compared and copied into the summary).

- `artifacts_one/LIB_A.yaml`: village (donor DGE), MapMyCells model MODEL1, reference REF.
- `artifacts_two/`: LIB_A as above, and `LIB_B.yaml`: no village (selected-cells DGE), no MapMyCells, reference REF.
- `artifacts_conflict/`: LIB_A as above, and `LIB_B.yaml` with reference REF2, so resolving both must fail.

DGEs (the manifest entries' `dge` must be the `user_dge` of the artifact):
- LIB_A: `/fixtures/LIB_A/REF/cbrb/lr1/cell_selection/auto/standard_analysis/village/V1/LIB_A.donors.digital_expression.txt.gz`
- LIB_B: `/fixtures/LIB_B/REF/cbrb/lr1/cell_selection/auto/standard_analysis/LIB_B.selected.digital_expression.txt.gz`
