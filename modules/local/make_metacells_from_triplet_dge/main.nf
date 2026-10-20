nextflow.enable.types = true

process MAKE_METACELLS_FROM_TRIPLET_DGE {
    tag "$meta.id"
    label 'process_medium'

    // The public Drop-seq image, tag 'current'. To use another tag (a branch build, say), override it with a withName: container setting in a config.
    container 'quay.io/broadinstitute/drop-seq_java:current'

    input:
    // meta.id is the analysis id.
    //   matrix, features, barcodes: the triplet DGE (MAKE_TRIPLET_DGE outputs); barcodes are <PREFIX>_<cell_barcode>
    //   cell_metadata: the merged <analysis>.cell_metadata.txt (tab-separated, with PREFIX, cell_barcode and the group columns)
    //   group_columns: list of one or more cell_metadata column names; cells with the same values in all of them form a metacell.
    //     The workflow calls this with ['donor'] and, when there is a cell type column, ['donor', <cell type column>].
    record(
        meta: Map,
        matrix: Path,
        features: Path,
        barcodes: Path,
        cell_metadata: Path,
        group_columns: List<String>
    )

    output:
    // Header line '#MakeMetacellsFromTripletDge ...', then GENE and one column per metacell (named by the group values joined
    // with ':'), one row per feature. Cells that are not in the cell metadata, or have an empty group value, are skipped.
    metacells = record(
        meta: meta,
        metacells: file("${task.ext.prefix ?: meta.id}.metacells.txt.gz")
    )

    script:
    // ext.args: optional extra tool arguments; ext.prefix: output name (default meta.id)
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: meta.id
    if (group_columns.isEmpty()) {
        error "MAKE_METACELLS_FROM_TRIPLET_DGE needs at least one group column"
    }
    def groupArgs = group_columns.collect { column -> "GROUP_COLUMNS='${column}'" }.join(' ')
    // 80% of the task memory for the JVM heap, leaving room for the JVM itself.
    def javaMemMb = (task.memory.toMega() * 4).intdiv(5)
    // The tool reads relative paths as URIs and fails, so every path is absolute (task directory).
    """
    mkdir -p tmp
    MakeMetacellsFromTripletDge \\
        -m ${javaMemMb}m \\
        MATRIX=\$PWD/${matrix} \\
        FEATURES=\$PWD/${features} \\
        BARCODES=\$PWD/${barcodes} \\
        MAPPING=\$PWD/${cell_metadata} \\
        CELL_BARCODE_COLUMN=cell_barcode \\
        TMP_DIR=\$PWD/tmp \\
        VALIDATION_STRINGENCY=SILENT \\
        OUTPUT=\$PWD/${prefix}.metacells.txt.gz \\
        ${groupArgs} \\
        ${args}
    """

    stub:
    def prefix = task.ext.prefix ?: meta.id
    """
    touch ${prefix}.metacells.txt.gz
    """
}
