Fixtures for the AGGREGATION_QC tests (self-contained). 12 cells, 2 libraries, 3 donors, 2 cell types.

- `cell_metadata.tsv`: PREFIX, cell_barcode, donor, num_retained_transcripts (the tool's default UMI column), M_class_name (the cell type column).
  - D1: 5 cells (UMIs 100k, 300k, 200k Glut; 50k, 70k GABA): median 100000, total 720000 (0.72 M), Glut median 200000.
  - D2: 4 cells (200k, 400k Glut; 40k, 60k GABA): median 130000 (even count), total 700000 (0.7 M), Glut median 300000.
  - D3: 3 cells (160k Glut; 80k, 120k GABA): median 120000, total 360000 (0.36 M), Glut median 160000.
  - fraction of nuclei: D1 5/12 = 0.417, D2 4/12 = 0.333, D3 3/12 = 0.25.
- `library_metrics.tsv`: one row per library with a few of the metrics (the tool skips the pages of the missing ones).
- `donors.txt`: the expected donors D1, D2, D3. `donors_other_name.txt`: the same donors in another order, with CRLF line endings, a blank line and no final newline.
- `conditions.tsv` (LIB_A sortA, LIB_B sortB); `conditions_missing_library.tsv` lacks LIB_B (must fail).
- `core_cell_types.txt`: `Glut`.
