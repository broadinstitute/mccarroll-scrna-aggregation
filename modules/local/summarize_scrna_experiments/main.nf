nextflow.enable.types = true

process SUMMARIZE_SCRNA_EXPERIMENTS {
    tag "$id"
    label 'process_single'

    // The public Drop-seq image, tag 'current'. To use another tag (a branch build, say), override it with a withName: container setting in a config.
    container 'quay.io/broadinstitute/drop-seq_python:current'

    input:
    // id is the library id (uei).
    // artifacts_yaml is <library_id>.yaml written by LOCATE_SCRNA_ARTIFACTS (one dataset)
    record(
        id: String,
        artifacts_yaml: Path
    )

    output:
    // one record per library:
    //   metrics: header + one row; first column 'library' is id
    //   tearsheet: 'label' / 'value' rows
    summary = record(
        id: id,
        metrics: file("${id}.library_metrics.txt"),
        tearsheet: file("tearsheets/${id}.standard_analysis_tearsheet.txt")
    )

    script:
    def args = task.ext.args ?: ''
    """
    summarize_scRNA_experiments \\
        --artifacts ${artifacts_yaml} \\
        --summary ${id}.library_metrics.txt \\
        --tearsheet-dir tearsheets \\
        ${args}
    """

    stub:
    """
    mkdir tearsheets
    touch ${id}.library_metrics.txt tearsheets/${id}.standard_analysis_tearsheet.txt
    """
}
