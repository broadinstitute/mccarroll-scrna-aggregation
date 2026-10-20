nextflow.enable.types = true

process MAKE_TRIPLET_DGE {
    tag "$meta.id"
    label 'process_medium'

    // The public Drop-seq image, tag 'current'. To use another tag (a branch build, say), override it with a withName: container setting in a config.
    container 'quay.io/broadinstitute/drop-seq_java:current'

    input:
    // meta.id is the analysis id. The three lists have one element per library, in the same (merge) order:
    //   prefixes: library ids, prepended to every cell barcode as <prefix>_<barcode>
    //   dges: tabular DGEs (GENE column then one column per cell; genes lexically sorted)
    //   barcode_lists: TSVs with a cell_barcode column; only these cells of the matching DGE are kept
    record(
        meta: Map,
        prefixes: List<String>,
        dges: List<Path>,
        barcode_lists: List<Path>
    )
    // tabular GTF with gene_id and gene_name columns; every gene of the DGEs must be in it
    reduced_gtf: Path

    output:
    // one record for the whole analysis:
    //   matrix: Matrix Market, genes (DGE row order) x cells (library order, then DGE column order), triplets sorted by {row, column}
    //   barcodes: one <prefix>_<barcode> per line, the matrix columns
    //   features: one gene_id, gene_name, 'Gene Expression' per line, the matrix rows
    triplet = record(
        meta: meta,
        matrix: file("matrix.mtx.gz"),
        barcodes: file("barcodes.tsv.gz"),
        features: file("features.tsv.gz")
    )

    script:
    if (dges.size() != prefixes.size() || barcode_lists.size() != prefixes.size()) {
        error "MAKE_TRIPLET_DGE needs one DGE and one barcode list per prefix, got ${prefixes.size()} prefixes, ${dges.size()} DGEs, ${barcode_lists.size()} barcode lists"
    }
    // The manifest as block-style YAML lines, one 'dges' entry per library in merge order. Paths are the staged
    // file names, relative to the task directory where manifest.yaml is written.
    def entryLines = (0..<prefixes.size()).collectMany { i ->
        [
            "  - dge: ${dges[i]}",
            "    prefix: ${prefixes[i]}",
            "    barcode_list: ${barcode_lists[i]}",
            "    barcode_column: cell_barcode",
        ]
    }
    // Written with printf (one quoted argument per line) rather than a heredoc, so the script's indent
    // stripping cannot change the YAML indentation.
    def manifestArgs = (['dges:'] + entryLines.toList()).collect { line -> "'${line}'" }.join(' ')
    // 80% of the task memory for the JVM heap, leaving room for the JVM itself.
    def javaMemMb = (task.memory.toMega() * 4).intdiv(5)
    """
    printf '%s\\n' ${manifestArgs} > manifest.yaml
    mkdir -p tmp
    MakeTripletDge \\
        -m ${javaMemMb}m \\
        --TMP_DIR \$PWD/tmp \\
        --VALIDATION_STRINGENCY SILENT \\
        --MANIFEST manifest.yaml \\
        --OUTPUT matrix.mtx.gz \\
        --OUTPUT_CELLS barcodes.tsv.gz \\
        --OUTPUT_FEATURES features.tsv.gz \\
        --REDUCED_GTF ${reduced_gtf}
    """

    stub:
    """
    touch manifest.yaml matrix.mtx.gz barcodes.tsv.gz features.tsv.gz
    """
}
