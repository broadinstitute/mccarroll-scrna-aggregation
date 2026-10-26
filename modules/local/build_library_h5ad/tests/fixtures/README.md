Tiny inputs for the BUILD_LIBRARY_H5AD tests (self-contained; not shared with other modules).

- dge.txt: a Drop-seq DGE (two '#' header lines, then GENE and 4 cells, 3 genes). Counts, genes x cells:

  | gene  | AAAA | CCCC | GGGG | TTTT |
  |-------|-----:|-----:|-----:|-----:|
  | GENEA |  1   |  0   |  3   |  0   |
  | GENEB |  0   |  0   |  0   |  0   |
  | GENEC |  2   |  5   |  0   |  7   |

  GENEB is zero in every cell (it must stay a gene of the file). CCCC is not in the cell metadata (it is filtered out).
- cell_metadata.tsv: 3 cells, in the order GGGG, AAAA, TTTT (not the order of the DGE columns), library LIB_A. AAAA has no cell type (the
  text NA) and TTTT has no pct_mt (NA): both must be encoded as missing values.
  Expected X (cells x genes, in the metadata order): GGGG [3, 0, 0], AAAA [1, 0, 2], TTTT [0, 0, 7]. Expected cell names: LIB_A_GGGG,
  LIB_A_AAAA, LIB_A_TTTT.
- reduced.gtf: GENEA (a gene row and an exon row, so that a gene is not counted twice), GENEB, GENEC and GENED (not in the DGE, so it is not
  in the file). Gene IDs ENSG01 to ENSG04 for GENEA to GENED.
- The tests use no extra argument, except those that name uppercase.config (--uppercase-column cell_barcode, the pipeline's default).
- cell_metadata_cell_not_in_dge.tsv: GGGG and ACGT (not in the DGE): the module must fail.
- reduced_missing_geneC.gtf: reduced.gtf without GENEC (the module must fail).
