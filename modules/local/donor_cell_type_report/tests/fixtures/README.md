Tiny cell metadata for the DONOR_CELL_TYPE_REPORT tests (self-contained; not shared with other modules).
Tab-separated, columns PREFIX, cell_barcode, num_retained_transcripts (the tool's default UMI column), donor (its default
donor column), M_class_name (the cell type column passed as input). Rows interleave donors and cell types so that
first-appearance order is checked.

- cell_metadata.tsv: 7 cells, every cell has a donor and a cell type.
  - D1: Glut x3 (UMIs 100, 200, 400 -> median 200), GABA x1 (50); 4 cells -> fractions 0.75, 0.25.
  - D2: GABA x2 (10, 25 -> median 17.5, an even count), Glut x1 (7); 3 cells -> fractions 0.667, 0.333 (rounded to 3 places).
- cell_metadata_missing_donor_or_cell_type.tsv: cell_metadata.tsv plus 3 cells:
  - LIB_B ACGT: donor D1, no cell type (UMIs 999). Counts toward D1's total (5 cells -> 0.6, 0.2), no row, medians unchanged.
  - LIB_B CAGT: no donor, Glut (UMIs 5000). Ignored.
  - LIB_B GTCA: donor D3, no cell type. D3 has no typed cells, so it has no row at all.
