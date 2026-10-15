process RESOLVE_AGGREGATION_MANIFEST {
    tag "$meta.id"
    label 'process_single'

    // Image registry/name and tag are parameters so local (jn_test) and production images can differ.
    container "${params.python_image}:${params.image_tag}"

    input:
    // meta.id is the aggregation analysis id; manifest is the aggregation YAML; artifacts_dir is the directory
    // written by LOCATE_SCRNA_ARTIFACTS (one <uei>.yaml per library)
    tuple val(meta), path(manifest), path(artifacts_dir)

    output:
    // one libraries.tsv per run. NOTE: its artifact_file and args_file columns hold task-local absolute paths;
    // downstream code must not use them (use library_id to find the artifact YAML and the args file).
    tuple val(meta), path("resolved/libraries.tsv"),                         emit: libraries_tsv
    // one <library_id>.join_and_filter_args.txt per library (one argument per line; may be empty)
    tuple val(meta), path("resolved/*.join_and_filter_args.txt"),            emit: args_files

    script:
    // task.ext.args carries the optional --reference and --mmc-model (set from params in conf/modules.config)
    def args = task.ext.args ?: ''
    """
    resolve_aggregation_manifest \\
        --manifest ${manifest} \\
        --artifacts-dir ${artifacts_dir} \\
        --analysis-id ${meta.id} \\
        --output-dir resolved \\
        ${args}
    """

    stub:
    """
    mkdir resolved
    touch resolved/libraries.tsv
    """
}
