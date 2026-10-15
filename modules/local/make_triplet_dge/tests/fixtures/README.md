Tiny inputs for the MAKE_TRIPLET_DGE tests (self-contained; not shared with other modules).
- lib_a.dge.txt: genes GENEA GENEB GENEC (sorted), cells AAAA CCCC GGGG; lib_b.dge.txt: cells AAAA TTTT (AAAA is a different cell).
- lib_a.cells.tsv: keeps AAAA and GGGG (CCCC is filtered out); lib_b.cells.tsv: keeps AAAA and TTTT.
- reduced.gtf: gene_id/gene_name of the three genes (ENSG01-03).
Expected merge of LIB_A + LIB_B: barcodes LIB_A_AAAA LIB_A_GGGG LIB_B_AAAA LIB_B_TTTT; 7 non-zero entries (GENEB's only kept count is LIB_B_TTTT = 8).
