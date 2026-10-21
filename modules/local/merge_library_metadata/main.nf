nextflow.enable.types = true

process MERGE_LIBRARY_METADATA {
    tag "$meta.id"
    label 'process_single'

    // The public Drop-seq image, tag 'current'. To use another tag (a branch build, say), override it with a withName: container setting in a config.
    container 'quay.io/broadinstitute/drop-seq_python:current'

    input:
    // meta.id is the analysis id. tsvs: one or more headered TSVs, concatenated in the order given
    // (the workflow sorts them by library id for a stable order).
    record(
        meta: Map,
        tsvs: List<Path>
    )

    output:
    // one file: union of the input columns, rows of all inputs; named <ext.prefix or meta.id>.txt
    combined = record(
        meta: meta,
        combined: file("${task.ext.prefix ?: meta.id}.txt")
    )

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: meta.id
    """
    cat_tsvs \\
        --output ${prefix}.txt \\
        ${args} \\
        ${tsvs.join(' ')}
    """

    stub:
    def prefix = task.ext.prefix ?: meta.id
    """
    touch ${prefix}.txt
    """
}
