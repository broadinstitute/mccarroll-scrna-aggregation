process FORMAT_MAPMYCELLS_ANNOTATIONS {
    tag "$meta.id"
    label 'process_single'

    // The public Drop-seq image, tag 'current'. To use another tag (a branch build, say), override it with a withName: container setting in a config.
    container 'quay.io/broadinstitute/drop-seq_python:current'

    input:
    // meta.id is the library id. csv: MapMyCells result csv with '#' header lines and a cell_id column.
    tuple val(meta), path(csv)

    output:
    // tab-separated, no '#' lines; every column except cell_id is prefixed (ext.args --column-prefix)
    tuple val(meta), path("${task.ext.prefix ?: meta.id}.mmc.tsv"), emit: converted
    // Name of the cell type column, <prefix><level>_name: the name column of the chosen taxonomy level (default: the top level,
    // known only from the csv's '# taxonomy hierarchy' line). Read from the tool's one-line file; only the string leaves the task.
    // All levels stay in the TSV; later steps group by this column.
    tuple val(meta), eval("cat cell_type_column.txt"), emit: cell_type_column

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: meta.id
    """
    convert_mmc_csv \\
        --input ${csv} \\
        --output ${prefix}.mmc.tsv \\
        --cell-type-column-output cell_type_column.txt \\
        ${args}
    """

    stub:
    def prefix = task.ext.prefix ?: meta.id
    """
    touch ${prefix}.mmc.tsv
    echo stub_name > cell_type_column.txt
    """
}
