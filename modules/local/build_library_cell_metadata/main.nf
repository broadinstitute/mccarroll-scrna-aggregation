nextflow.enable.types = true

process BUILD_LIBRARY_CELL_METADATA {
    tag "$id"
    label 'process_single'

    // The public Drop-seq image, tag 'current'. To use another tag (a branch build, say), override it with a withName: container setting in a config.
    container 'quay.io/broadinstitute/drop-seq_python:current'

    input:
    // id is the library id (written to the PREFIX column).
    // cell_metadata: the library's cell metadata TSV with a cell_barcode column.
    // mmc_tsv: formatted MapMyCells TSV (cell_id column) to left-join on cell_barcode, or null for none.
    // args: the manifest's donor, joins and filters as join_and_filter_tsv arguments ([] for none). The script writes them one per line to
    //   <id>.join_and_filter_args.txt (a zero-byte file for none) in the task directory and the tool reads that with --args-file. It is the
    //   only source of these arguments (there is no ext.args).
    // extra_files: files that args refers to (--join/--include-file ...), staged by base name, or an empty list for none.
    record(
        id: String,
        cell_metadata: Path,
        mmc_tsv: Path?,
        args: List<String>,
        extra_files: List<Path>
    )

    output:
    // PREFIX first, then the input columns, the MapMyCells columns and any joins; rows removed by filters are dropped
    cell_metadata = record(
        id: id,
        cell_metadata: file("${task.ext.prefix ?: id}.joined_filtered_cell_metadata.txt")
    )

    script:
    // The arguments file comes after the MapMyCells join, so the manifest's filters can use its columns.
    def prefix = task.ext.prefix ?: id
    def mmc_join = mmc_tsv ? "--join ${mmc_tsv} cell_barcode cell_id" : ''
    // The arguments file, one argument per line: printf with each argument single-quoted (a ' becomes '\''), so the shell expands nothing.
    // No arguments give a zero-byte file (printf with no arguments would print one empty line).
    def args_file = "${id}.join_and_filter_args.txt"
    def write_args = args
        ? "printf '%s\\n' " + args.collect { arg -> "'" + arg.replace("'", "'\\''") + "'" }.join(' ') + " > ${args_file}"
        : ": > ${args_file}"
    """
    ${write_args}
    join_and_filter_tsv \\
        --input ${cell_metadata} \\
        --output ${prefix}.joined_filtered_cell_metadata.txt \\
        --set-first --set PREFIX ${id} \\
        ${mmc_join} \\
        --args-file ${args_file}
    """

    stub:
    def prefix = task.ext.prefix ?: id
    """
    touch ${prefix}.joined_filtered_cell_metadata.txt
    """
}
