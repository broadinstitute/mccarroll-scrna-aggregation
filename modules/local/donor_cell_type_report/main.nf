process DONOR_CELL_TYPE_REPORT {
    tag "$meta.id"
    label 'process_single'

    // The public Drop-seq image, tag 'current'. To use another tag (a branch build, say), override it with a withName: container setting in a config.
    container 'quay.io/broadinstitute/drop-seq_python:current'

    input:
    // meta.id is the analysis id. cell_metadata: the merged <analysis>.cell_metadata.txt (tab-separated, with donor and
    // num_retained_transcripts columns by default). cell_type_column: name of its cell type column, the value emitted by
    // FORMAT_MAPMYCELLS_ANNOTATIONS (the same for all libraries). The workflow only calls this when the cell metadata has a
    // donor column and there is a cell type column.
    tuple val(meta), path(cell_metadata), val(cell_type_column)

    output:
    // donor, cell_type, num_nuclei, fraction_nuclei, median_umis_per_nucleus: one row per donor and cell type, in order of
    // first appearance. Cells with no donor are ignored; cells with no cell type count toward the donor's total only.
    tuple val(meta), path("${task.ext.prefix ?: meta.id}.donor_cell_type.txt"), emit: report

    script:
    // ext.args: optional --donor-column / --umi-column
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: meta.id
    """
    donor_cell_type_report \\
        --input ${cell_metadata} \\
        --output ${prefix}.donor_cell_type.txt \\
        --cell-type-column '${cell_type_column}' \\
        ${args}
    """

    stub:
    def prefix = task.ext.prefix ?: meta.id
    """
    touch ${prefix}.donor_cell_type.txt
    """
}
