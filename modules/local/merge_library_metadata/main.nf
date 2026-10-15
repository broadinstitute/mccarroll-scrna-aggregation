process MERGE_LIBRARY_METADATA {
    tag "$meta.id"
    label 'process_single'

    // Image registry/name and tag are parameters so local (jn_test) and production images can differ.
    container "${params.python_image}:${params.image_tag}"

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
