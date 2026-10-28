# Synthetic library tree for the workflow tests (`tests/pipeline.synthetic.nf.test`)

Tiny local libraries in the layout the single-cell pipeline writes (`<LIB>/REF/cbrb/lr1/cell_selection/auto/standard_analysis/...`), so the whole
pipeline runs on them with real processes and no gs://, network or credentials. `@ROOT@` in a text file is replaced by `SyntheticTree.materialize`
(tests/lib) with the absolute path of the copy in `.nf-test/synthetic_root`, which the test mounts into the task containers at the same path.

Run alone: `nf-test test tests/pipeline.synthetic.nf.test` (or `--tag pipeline_synthetic`). Needs Docker and the public python and java images only.
To audit a run, look at `.nf-test/synthetic_root` (inputs), `.nf-test/tests/<test id>/output` (published), `work/` and `meta/nextflow.log`.

| Library | Cells (cell_barcode) | Purpose |
|---|---|---|
| `LIB_PLAIN_1` | AAAA CCCC GGGG (num_transcripts 100 200 300; GENEA 1 0 2, GENEB 0 3 0, GENEC 4 0 5) | no donor, no MapMyCells |
| `LIB_PLAIN_2` | AAAA TTTT (50 80; GENEA 7 0, GENEB 0 8, GENEC 9 0) | same barcode AAAA as PLAIN_1 but other counts |
| `LIB_MMC_1` | AAAA CCCC GGGG TTTT ACAC; pct_mt .05 .25 .01 .5 .1; class Glut GABA Glut Vip Glut | MapMyCells `MODEL1`, filters min/max/include |
| `LIB_MMC_2` | same barcodes; pct_mt .03 .3 .02 .04 .05; class Glut Glut GABA Vip Glut | MapMyCells `MODEL1`, includeFile/excludeFile/exclude |
| `LIB_MMC_SUPER` | AAAA CCCC (num_retained_transcripts 1000 2000; class Glut GABA) | MapMyCells hierarchy supercluster > class, so its default cell type column is `MODEL1_supercluster_name` (the others have `MODEL1_class_name`) |
| `LIB_DUP` | AAAA AAAA (in the cell metadata) | a duplicate (PREFIX, cell_barcode) must fail the merge |
| `LIB_VILLAGE` | AAAA CCCC GGGG TTTT; donor N1 N1 N2 N3 in its (village) cell metadata; num_transcripts 100 200 300 400 | a village: the donor of each cell is in the cell metadata. For the donor-level join tests |

| File | Use |
|---|---|
| `manifest_plain.yaml` | PLAIN_2 then PLAIN_1 (reverse of alphabetical): the merge order is the manifest order |
| `manifest_filters.yaml` | donors N1/N2, a join (`files/extra.tsv`) from `dgeDefaults`, and the filters; expected cells: AAAA and ACAC of each library |
| `manifest_cell_type_levels.yaml` | LIB_MMC_1 (donor N1) and LIB_MMC_SUPER (donor N3): different cell type columns by default, the same with `--mmc_level class` |
| `manifest_mmc_model.yaml` | LIB_MMC_1 (N1) and LIB_MMC_2 (N2), run with `--mmc_model MODEL2` (each also has a `MODEL2` result with the classes Neuron / Glia) |
| `manifest_mixed_mmc.yaml` | LIB_PLAIN_1 (no MapMyCells results) then LIB_MMC_1 (MapMyCells `MODEL1`), no donors: only LIB_MMC_1 is converted and joined |
| `manifest_mixed_donors.yaml` | LIB_MMC_1 with a donor and LIB_PLAIN_1 without: the resolver stops the run |
| `manifest_missing_files.yaml` | PLAIN_2 and PLAIN_1 with a missing join file (from `dgeDefaults`) and a missing `includeFile`: the run stops before any process |
| `manifest_duplicate_cell.yaml` | LIB_DUP alone |
| `files/donor_attributes.tsv` | `donor`, `age` (numeric), `sex`: N1 63 male, N2 41 female (N3 is not in the file, on purpose) |
| `files/donor_attributes_duplicate.tsv` | the same with N1 twice: a join on it must fail |
| `files/village_donors.txt` | N1 N2 N3, the `donorFile` of `LIB_VILLAGE`'s village stage (read only with `run_qc`) |
| `manifest_donor_join.yaml` | `LIB_VILLAGE` with a join of `donor_attributes.tsv` on `donor` |
| `manifest_donor_join_duplicate.yaml` | the same with `donor_attributes_duplicate.tsv`: the run must fail in BUILD_LIBRARY_CELL_METADATA |
| `manifest_donor_join_single.yaml` | `LIB_PLAIN_1` with `donor: N1` in the manifest and the same join: the donor column is created, then joined on |
| `manifest_donor_join_village_donor.yaml` | `LIB_VILLAGE` with `donor: N7` in the manifest: the cells already have their donors, which must not be replaced: the resolver stops the run before any library is processed |
| `files/core_cell_types.txt` | `Glut`, for the QC test of `--qc_core_cell_types` (given with plain libraries, which have no cell type column: the run warns) |
| `fake_credentials.json` | a fake service account key that only passes the pre-flight check |
| `reference/REF/` | empty fasta, and a reduced GTF with GENEA GENEB GENEC |

`cmd.tsv` has a `doublet` column (SUMMARIZE needs it) and the MMC libraries `num_retained_transcripts` (the cell type report needs it).

Three of the donor-level join tests need the fix of `join_and_filter_tsv` (Drop-seq pull request 594), which is in the public image tagged `current`. The fourth (a manifest donor on a village) stops at the resolver.
