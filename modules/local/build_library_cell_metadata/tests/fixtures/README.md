Tiny TSVs for the BUILD_LIBRARY_CELL_METADATA tests (self-contained; not shared with other modules).
- cmd.tsv: cell metadata (numbers have no trailing zeros, because the tool rewrites numbers as pandas prints them), cells AAAA (pct_mt 0.05, donor d1), CCCC (0.25, d2), GGGG (0.01, d3).
- cmd_no_donor.tsv: cmd.tsv without the `donor` column, for the tests that `--set donor` (the tool refuses to `--set` a column the input already has).
- mmc.tsv: formatted MapMyCells result: AAAA Glut, GGGG GABA; CCCC has no annotation.
- extra.tsv: a secondary file joined on its `cell` column: AAAA yes, CCCC no (GGGG absent).
- args_*.txt: join_and_filter_tsv arguments, one per line, read by the tests with `readLines()` as the module's `args` list (the task writes the same text to its own arguments file):
  args_empty.txt (no donor, joins or filters: a zero-byte file); args_donor_filters.txt (`--set donor N1 --max pct_mt 0.1 --exclude M_class_name GABA`);
  args_join_extra.txt (`--join extra.tsv cell_barcode cell`); args_special_value.txt (`--set donor` with the value `N 1 $HOME 'r'`: spaces, a dollar sign and a quote).
