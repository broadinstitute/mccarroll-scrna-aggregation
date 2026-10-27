# Fixtures for LOCATE_SCRNA_ARTIFACTS tests

A synthetic, empty-file copy of the directory layout the single-cell pipeline produces, so the tool can be tested
without credentials or network. The tests mount this directory at `/fixtures` in the container, so the manifests
refer to `/fixtures/...` paths. Files are empty except the `properties.yaml` files the tool reads and the donor file.

| Path | Purpose |
|---|---|
| `LIB_A/` | complete library: village `V1` (donors DGE, cmd.tsv, `properties.yaml` with a `donorFile`), mmc model `MODEL1` (only `properties.yaml` and `LIB_A.csv`), two pipeline traces (the later one must be chosen), reference with a reduced GTF |
| `LIB_B/` | minimal library: selected-cells DGE only; no village, mmc, trace or reference (artifacts must be `NA`) |
| `donors/LIB_A.donors.txt` | the donor file named by the `donorFile` of LIB_A's village (expected `donor_file`) |
| `reference/REF/` | `REF.fasta.gz` and `REF.reduced.gtf`, referenced by LIB_A's alignment `properties.yaml` |
| `manifest_two_libraries.yaml` | LIB_A (donors DGE, no donor) and LIB_B (selected DGE, `donor: N1`) |
| `manifest_duplicate_uei.yaml` | two DGEs (selected, gmg) of LIB_A: must fail with a duplicate uei error |
| `expected/LIB_A.yaml`, `expected/LIB_B.yaml` | reviewed output of `manifest_two_libraries.yaml`; every non-`NA` path exists in this tree |

Regenerate `expected/` only after reviewing the change. Run the tool in the python image against this directory, then
check that each non-`NA` path exists and each `NA` is for something the tree lacks.
