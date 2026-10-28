# mccarroll/scrna-aggregation: Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v1.0.0dev - [date]

Initial release of mccarroll/scrna-aggregation, created with the [nf-core](https://nf-co.re/) template.

### `Added`

- Manifest-driven aggregation: `--manifest`, `--analysis_id`, `--mmc_model`, `--mmc_level`; library resolver in the workflow with a plain-text `pipeline_info/<analysis>.resolved_libraries.txt`; per-library summaries, merged metrics, MapMyCells formatting and cell metadata building.
- A per-library h5ad file (`h5ad/<library>.h5ad`): the counts of the library's DGE, its cell metadata as `obs` (cells named `<library>_<cell barcode>`) and gene IDs and symbols as `var` (`BUILD_LIBRARY_H5AD`, tool `build_library_h5ad` of the Drop-seq python image).
- An optional QC step (`--run_qc`, with `--qc_conditions_file`, `--qc_condition_column` and `--qc_core_cell_types`; `AGGREGATION_QC`, tool `aggregation_qc` of the Drop-seq python image): PDFs of library, donor and cell type QC and `<analysis>.donor_qc.txt`.
- Donor attributes can be joined to the cells on the donor (`join_and_filter_tsv` joins on a `--set` column); a manifest `donor` for a village is rejected.

### `Fixed`

### `Dependencies`

### `Deprecated`
