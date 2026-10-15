Tiny TSVs for the BUILD_LIBRARY_CELL_METADATA tests (self-contained; not shared with other modules).
- cmd.tsv: cell metadata (numbers have no trailing zeros, because the tool rewrites numbers as pandas prints them), cells AAAA (pct_mt 0.05, donor d1), CCCC (0.25, d2), GGGG (0.01, d3).
- mmc.tsv: formatted MapMyCells result: AAAA Glut, GGGG GABA; CCCC has no annotation.
- extra.tsv: a secondary file joined on its `cell` column: AAAA yes, CCCC no (GGGG absent).
