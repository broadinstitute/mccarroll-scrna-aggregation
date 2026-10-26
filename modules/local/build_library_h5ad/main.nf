nextflow.enable.types = true

process BUILD_LIBRARY_H5AD {
    tag "$id"
    label 'process_single'

    // The public Drop-seq image, tag 'current'. To use another tag (a branch build, say), override it with a withName: container setting in a config.
    container 'quay.io/broadinstitute/drop-seq_python:current'

    input:
    // id is the library id (the PREFIX column of the cell metadata, and the prefix of the cell names).
    // dge: the library's tabular DGE (GENE column, then one column per cell barcode), optionally gzipped.
    // cell_metadata: the library's joined and filtered cell metadata TSV (BUILD_LIBRARY_CELL_METADATA), with PREFIX and cell_barcode columns;
    //   only these cells of the DGE are written.
    record(
        id: String,
        dge: Path,
        cell_metadata: Path
    )
    // tabular GTF with gene_name, gene_id and annotationType columns, the same for every library: gives each gene of the DGE its gene ID
    reduced_gtf: Path

    output:
    // one record per library:
    //   h5ad: h5ad/<ext.prefix ?: id>.h5ad (published as it is, in the h5ad directory). X holds the raw counts, cells x genes (uint32), in the order
    //   of the cell metadata. obs is the cell metadata, indexed by <id>_<cell barcode> (the cell names of the aggregated matrix, so that the files
    //   of several libraries can be combined); the columns named by --uppercase-column (ext.args) are written in upper case (conf/modules.config:
    //   cell_barcode, as CELL_BARCODE). var is indexed by gene ID (index name gene_ids) and has the column gene_symbol. Strings are plain string arrays.
    h5ad = record(
        id: id,
        h5ad: file("h5ad/${task.ext.prefix ?: id}.h5ad")
    )

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: id
    """
    mkdir h5ad
    build_library_h5ad \\
        --dge ${dge} \\
        --cell-metadata ${cell_metadata} \\
        --reduced-gtf ${reduced_gtf} \\
        --output h5ad/${prefix}.h5ad \\
        ${args}
    """

    stub:
    def prefix = task.ext.prefix ?: id
    """
    mkdir h5ad
    touch h5ad/${prefix}.h5ad
    """
}
