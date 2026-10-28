nextflow.enable.types = true

process AGGREGATION_QC {
    tag "$id"
    label 'process_single'

    // The public Drop-seq image, tag 'current'. To use another tag (a branch build, say), override it with a withName: container setting in a config.
    container 'quay.io/broadinstitute/drop-seq_python:current'

    input:
    // id is the analysis id (the prefix of the outputs). cell_metadata and library_metrics: the merged <analysis>.cell_metadata.txt and
    // <analysis>.library_metrics.txt. The rest is optional (null for none):
    // donor_file: the expected donors, one per line (LibraryResolver.commonDonorFile); without it there are no donor outputs.
    // cell_type_column: the name of the cell type column of the cell metadata; without it there are no cell type outputs.
    // conditions_file (a header and two columns, library and condition) or condition_column (a cell metadata column with one value per
    //   library), never both.
    // core_cell_types: headerless file, one core cell type per line.
    record(
        id: String,
        cell_metadata: Path,
        library_metrics: Path,
        donor_file: Path?,
        cell_type_column: String?,
        conditions_file: Path?,
        condition_column: String?,
        core_cell_types: Path?
    )

    output:
    // The PDFs and donor_qc.txt the tool wrote. Which exist depends on the gates the tool decides (see aggregation_qc_plan.md): the library PDFs
    // always, donor_qc.txt and the donor PDFs only with a donor file, the cell type PDFs only with a cell type column.
    qc = record(
        id: id,
        pdfs: files("*.pdf"),
        donor_qc: file("${task.ext.prefix ?: id}.donor_qc.txt", optional: true)
    )

    script:
    // ext.args: optional extra tool arguments, for example --umi-column; ext.prefix: the analysis id used for the titles and the output names (default id).
    // Each optional input adds its flag only when given. The tool decides which outputs to write and exits 0 when it skips one.
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: id
    def donor_arg = donor_file ? "--donor-file ${donor_file}" : ''
    def cell_type_arg = cell_type_column ? "--cell-type-column '${cell_type_column}'" : ''
    def conditions_arg = conditions_file ? "--conditions-file ${conditions_file}" : ''
    def condition_column_arg = condition_column ? "--condition-column '${condition_column}'" : ''
    def core_arg = core_cell_types ? "--core-cell-types ${core_cell_types}" : ''
    """
    aggregation_qc \\
        --cell-metadata ${cell_metadata} \\
        --library-metrics ${library_metrics} \\
        --analysis-id ${prefix} \\
        ${donor_arg} \\
        ${cell_type_arg} \\
        ${conditions_arg} \\
        ${condition_column_arg} \\
        ${core_arg} \\
        ${args}
    """

    stub:
    // The files the tool always writes
    def prefix = task.ext.prefix ?: id
    """
    touch ${prefix}.library_metrics.pdf ${prefix}.filtered_library_metrics.pdf
    """
}
