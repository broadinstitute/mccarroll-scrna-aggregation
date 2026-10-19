process SUMMARIZE_SCRNA_EXPERIMENTS {
    tag "$meta.id"
    label 'process_single'

    // The public Drop-seq image, tag 'current'. To use another tag (a branch build, say), override it with a withName: container setting in a config.
    container 'quay.io/broadinstitute/drop-seq_python:current'

    input:
    // meta.id is the library id (uei); meta.analysis_id is the aggregation analysis id.
    // artifacts_yaml is <library_id>.yaml written by LOCATE_SCRNA_ARTIFACTS (one dataset)
    tuple val(meta), path(artifacts_yaml)

    output:
    // header + one row; first column 'library' is meta.id
    tuple val(meta), path("${meta.id}.library_metrics.txt"),                               emit: metrics
    // 'label' / 'value' rows
    tuple val(meta), path("tearsheets/${meta.id}.standard_analysis_tearsheet.txt"),         emit: tearsheet

    script:
    def args = task.ext.args ?: ''
    """
    summarize_scRNA_experiments \\
        --artifacts ${artifacts_yaml} \\
        --summary ${meta.id}.library_metrics.txt \\
        --tearsheet-dir tearsheets \\
        ${args}
    """

    stub:
    """
    mkdir tearsheets
    touch ${meta.id}.library_metrics.txt tearsheets/${meta.id}.standard_analysis_tearsheet.txt
    """
}
