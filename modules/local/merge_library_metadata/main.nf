process MERGE_LIBRARY_METADATA {
    tag "$meta.id"
    label 'process_single'

    // The public Drop-seq image, tag 'current'. To use another tag (a branch build, say), override it with a withName: container setting in a config.
    container 'quay.io/broadinstitute/drop-seq_python:current'

    input:
    // meta.id is the analysis id. tsvs: one or more headered TSVs, concatenated in the order given
    // (the workflow sorts them by library id for a stable order).
    tuple val(meta), path(tsvs)

    output:
    // one file: union of the input columns, rows of all inputs; named <ext.prefix or meta.id>.txt
    tuple val(meta), path("${task.ext.prefix ?: meta.id}.txt"), emit: combined

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: meta.id
    """
    cat_tsvs \\
        --output ${prefix}.txt \\
        ${args} \\
        ${tsvs}
    """

    stub:
    def prefix = task.ext.prefix ?: meta.id
    """
    touch ${prefix}.txt
    """
}
