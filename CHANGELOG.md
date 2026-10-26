# mccarroll/scrna-aggregation: Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v1.0.0dev - [date]

Initial release of mccarroll/scrna-aggregation, created with the [nf-core](https://nf-co.re/) template.

### `Added`

- Manifest-driven aggregation: `--manifest`, `--analysis_id`, `--mmc_model`, `--mmc_level`; library resolver in the workflow with a plain-text `pipeline_info/<analysis>.resolved_libraries.txt`; per-library summaries, merged metrics, MapMyCells formatting and cell metadata building.
- A per-library h5ad file (`h5ad/<library>.h5ad`): the counts of the library's DGE, its cell metadata as `obs` (cells named `<library>_<cell barcode>`) and gene IDs and symbols as `var` (`BUILD_LIBRARY_H5AD`, tool `build_library_h5ad` of the Drop-seq python image).

### `Fixed`

### `Dependencies`

### `Deprecated`
