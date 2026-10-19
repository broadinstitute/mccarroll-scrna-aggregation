process BUILD_LIBRARY_CELL_METADATA {
    tag "$meta.id"
    label 'process_single'

    // The public Drop-seq image, tag 'current'. To use another tag (a branch build, say), override it with a withName: container setting in a config.
    container 'quay.io/broadinstitute/drop-seq_python:current'

    input:
    // meta.id is the library id (written to the PREFIX column).
    // cell_metadata: the library's cell metadata TSV with a cell_barcode column.
    // mmc_tsv: formatted MapMyCells TSV (cell_id column) to left-join on cell_barcode, or [] for none.
    // args_file: the manifest's donor, joins and filters as join_and_filter_tsv arguments, one per line (an empty file for none), read with
    //   --args-file. It is the only source of these arguments (there is no ext.args), and as a staged input it stays in the task directory.
    // extra_files: files that args_file refers to (--join/--include-file ...), staged by base name, or [] for none.
    tuple val(meta), path(cell_metadata), path(mmc_tsv), path(args_file), path(extra_files)

    output:
    // PREFIX first, then the input columns, the MapMyCells columns and any joins; rows removed by filters are dropped
    tuple val(meta), path("${task.ext.prefix ?: meta.id}.joined_filtered_cell_metadata.txt"), emit: cell_metadata

    script:
    // The arguments file comes after the MapMyCells join, so the manifest's filters can use its columns.
    def prefix = task.ext.prefix ?: meta.id
    def mmc_join = mmc_tsv ? "--join ${mmc_tsv} cell_barcode cell_id" : ''
    """
    join_and_filter_tsv \\
        --input ${cell_metadata} \\
        --output ${prefix}.joined_filtered_cell_metadata.txt \\
        --set-first --set PREFIX ${meta.id} \\
        ${mmc_join} \\
        --args-file ${args_file}
    """

    stub:
    def prefix = task.ext.prefix ?: meta.id
    """
    touch ${prefix}.joined_filtered_cell_metadata.txt
    """
}
