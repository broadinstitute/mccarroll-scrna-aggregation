nextflow.enable.types = true

process MERGE_LIBRARY_METADATA {
    tag "$id"
    label 'process_single'

    // The public Drop-seq image, tag 'current'. To use another tag (a branch build, say), override it with a withName: container setting in a config.
    container 'quay.io/broadinstitute/drop-seq_python:current'

    input:
    // id is the analysis id. tsvs: one or more headered TSVs, concatenated in the order given
    // (the workflow gives them in manifest order).
    record(
        id: String,
        tsvs: List<Path>
    )

    output:
    // one file: union of the input columns, rows of all inputs; named <ext.prefix or id>.txt
    combined = record(
        id: id,
        combined: file("${task.ext.prefix ?: id}.txt")
    )

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: id
    """
    cat_tsvs \\
        --output ${prefix}.txt \\
        ${args} \\
        ${tsvs.join(' ')}
    """

    stub:
    def prefix = task.ext.prefix ?: id
    """
    touch ${prefix}.txt
    """
}
