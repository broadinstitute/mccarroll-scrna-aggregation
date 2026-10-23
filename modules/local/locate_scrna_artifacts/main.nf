nextflow.enable.types = true

process LOCATE_SCRNA_ARTIFACTS {
    tag "$id"
    label 'process_single'

    // The public Drop-seq image, tag 'current'. To use another tag (a branch build, say), override it with a withName: container setting in a config.
    container 'quay.io/broadinstitute/drop-seq_python:current'

    input:
    // id is the aggregation analysis id; manifest is the YAML manifest with a top-level 'dges' list
    record(
        id: String,
        manifest: Path
    )

    output:
    // directory 'artifacts' holding one <uei>.yaml per manifest DGE (one process run, one directory out)
    artifacts_dir = record(
        id: id,
        artifacts: file("artifacts")
    )

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
