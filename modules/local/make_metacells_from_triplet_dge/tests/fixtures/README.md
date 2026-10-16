Tiny inputs for the MAKE_METACELLS_FROM_TRIPLET_DGE tests (self-contained; not shared with other modules).
- matrix.mtx.gz / features.tsv.gz / barcodes.tsv.gz: 3 genes (GENEA-C) x 6 cells, 12 non-zero entries. Cells, in column order:
  1 LIB_A_AAAA, 2 LIB_A_CCCC, 3 LIB_A_GGGG, 4 LIB_B_AAAA, 5 LIB_B_GGGG, 6 LIB_B_TTTT.
  Counts (GENEA, GENEB, GENEC): c1 (1,3,0)  c2 (2,5,0)  c3 (100,0,300)  c4 (4,7,0)  c5 (200,0,400)  c6 (0,11,13).
- cell_metadata.tsv: PREFIX, cell_barcode, donor, cell_type. Pitfalls on purpose:
  - LIB_A_GGGG (c3) is not in the metadata (large counts: they would show if it were included);
  - LIB_B_GGGG (c5) has an empty donor (large counts, same reason);
  - AAAA is in both libraries with different donors (LIB_A: D1 Glut, LIB_B: D2 Glut).
  D1 = c1, c2; D2 = c4, c6. D1 Glut = c1, D1 GABA = c2, D2 Glut = c4, D2 GABA = c6.
Expected by donor (GENEA, GENEB, GENEC): D1 (3, 8, 0), D2 (4, 18, 13).
Expected by donor and cell type: D1:Glut (1,3,0), D1:GABA (2,5,0), D2:Glut (4,7,0), D2:GABA (0,11,13).
