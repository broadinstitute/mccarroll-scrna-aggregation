process BUILD_LIBRARY_CELL_METADATA {
    tag "$meta.id"
    label 'process_single'

    // Image registry/name and tag are parameters so local (jn_test) and production images can differ.
    container "${params.python_image}:${params.image_tag}"

    input:
    // meta.id is the library id (written to the PREFIX column).
    // cell_metadata: the library's cell metadata TSV with a cell_barcode column.
    // mmc_tsv: formatted MapMyCells TSV (cell_id column) to left-join on cell_barcode, or [] for none.
    // extra_files: files that ext.args refers to (--join/--include-file ...), staged by basename, or [] for none.
    tuple val(meta), path(cell_metadata), path(mmc_tsv), path(extra_files)

    output:
    // PREFIX first, then the input columns, the MapMyCells columns and any joins; rows removed by filters are dropped
    tuple val(meta), path("${task.ext.prefix ?: meta.id}.joined_filtered_cell_metadata.txt"), emit: cell_metadata

    script:
    // ext.args: manifest donor/joins/filters (--set donor, --join, --max ...); they come after the MapMyCells join so can use its columns
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: meta.id
    def mmc_join = mmc_tsv ? "--join ${mmc_tsv} cell_barcode cell_id" : ''
    """
    join_and_filter_tsv \\
        --input ${cell_metadata} \\
        --output ${prefix}.joined_filtered_cell_metadata.txt \\
        --set-first --set PREFIX ${meta.id} \\
        ${mmc_join} \\
        ${args}
    """

    stub:
    def prefix = task.ext.prefix ?: meta.id
    """
    touch ${prefix}.joined_filtered_cell_metadata.txt
    """
}
