process LOCATE_SCRNA_ARTIFACTS {
    tag "$meta.id"
    label 'process_single'

    // Image registry/name and tag are parameters so local (jn_test) and production images can differ.
    container "${params.python_image}:${params.image_tag}"

    input:
    // meta.id is the aggregation analysis id; manifest is the YAML manifest with a top-level 'dges' list
    tuple val(meta), path(manifest)

    output:
    // directory 'artifacts' holding one <uei>.yaml per manifest DGE (one process run, one directory out)
    tuple val(meta), path("artifacts"), emit: artifacts_dir

    script:
    def args = task.ext.args ?: ''
    """
    locate_scRNA_artifacts \\
        --manifest ${manifest} \\
        --output-dir artifacts \\
        ${args}
    """

    stub:
    """
    mkdir artifacts
    """
}
