process MAKE_TRIPLET_DGE {
    tag "$meta.id"
    label 'process_medium'

    // Image registry/name and tag are parameters so local (jn_test) and production images can differ.
    container "${params.java_image}:${params.image_tag}"

    input:
    // meta.id is the analysis id. The three lists have one element per library, in the same (merge) order:
    //   prefixes: library ids, prepended to every cell barcode as <prefix>_<barcode>
    //   dges: tabular DGEs (GENE column then one column per cell; genes lexically sorted)
    //   barcode_lists: TSVs with a cell_barcode column; only these cells of the matching DGE are kept
    tuple val(meta), val(prefixes), path(dges), path(barcode_lists)
    // tabular GTF with gene_id and gene_name columns; every gene of the DGEs must be in it
    path reduced_gtf

    output:
    // Matrix Market, genes (DGE row order) x cells (library order, then DGE column order), triplets sorted by {row, column}
    tuple val(meta), path("matrix.mtx.gz"),    emit: matrix
    // one <prefix>_<barcode> per line, the matrix columns
    tuple val(meta), path("barcodes.tsv.gz"),  emit: barcodes
    // one gene_id, gene_name, 'Gene Expression' per line, the matrix rows
    tuple val(meta), path("features.tsv.gz"),  emit: features

    script:
    // A single staged file arrives as one Path, not a list.
    def dgeList = dges instanceof Collection ? dges : [dges]
    def barcodeListList = barcode_lists instanceof Collection ? barcode_lists : [barcode_lists]
    def prefixList = prefixes instanceof Collection ? prefixes : [prefixes]
    if (dgeList.size() != prefixList.size() || barcodeListList.size() != prefixList.size()) {
        error "MAKE_TRIPLET_DGE needs one DGE and one barcode list per prefix, got ${prefixList.size()} prefixes, ${dgeList.size()} DGEs, ${barcodeListList.size()} barcode lists"
    }
    // The manifest as one line of flow-style YAML, passed with --YAML (no manifest file to write and indent).
    def entries = prefixList.indices.collect { i ->
        "{dge: ${dgeList[i]}, prefix: ${prefixList[i]}, barcode_list: ${barcodeListList[i]}, barcode_column: cell_barcode}"
    }.join(', ')
    def manifest = "{dges: [${entries}]}"
    // 80% of the task memory for the JVM heap, leaving room for the JVM itself.
    def javaMemMb = (task.memory.toMega() * 0.8) as int
    """
    mkdir -p tmp
    MakeTripletDge \\
        -m ${javaMemMb}m \\
        --TMP_DIR \$PWD/tmp \\
        --VALIDATION_STRINGENCY SILENT \\
        --YAML '${manifest}' \\
        --OUTPUT matrix.mtx.gz \\
        --OUTPUT_CELLS barcodes.tsv.gz \\
        --OUTPUT_FEATURES features.tsv.gz \\
        --REDUCED_GTF ${reduced_gtf}
    """

    stub:
    """
    touch matrix.mtx.gz barcodes.tsv.gz features.tsv.gz
    """
}
