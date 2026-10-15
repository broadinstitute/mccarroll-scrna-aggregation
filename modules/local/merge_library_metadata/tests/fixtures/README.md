Tiny TSVs for the MERGE_LIBRARY_METADATA tests (self-contained; not shared with other modules).
- lib_a.tsv: LIB_A, cells AAAA CCCC.
- lib_b.tsv: LIB_B, cells AAAA GGGG (AAAA is the same barcode as in LIB_A, a different cell).
- lib_c_extra_column.tsv: LIB_C, one cell, with an extra `cell_type` column the others lack.
- lib_a_duplicate_cell.tsv: LIB_A AAAA again, a duplicate (PREFIX, cell_barcode) of lib_a.tsv.
