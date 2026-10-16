process RESOLVE_LIBRARIES {
    tag "$meta.id"
    label 'process_single'

    // The resolver is Groovy (lib/LibraryResolver.groovy) and runs in the script block; the task only needs a shell. The python image is used
    // so no extra image is needed, and the task also works on cloud executors.
    container "${params.python_image}:${params.image_tag}"

    input:
    // meta.id is the analysis id; artifact_texts is the YAML text of each <uei>.yaml of the 'artifacts' directory of LOCATE_SCRNA_ARTIFACTS
    // (LibraryResolver.readArtifactTexts): the script block cannot read a staged path, and the resolver needs the content, not the files.
    tuple val(meta), val(artifact_texts)
    // the manifest entries (AggregationManifest.parse): [dge, donor, filters, joins] per library, in manifest order
    val entries
    // reference name that skips the check that all libraries have the same reference, or '' for none
    val reference
    // MapMyCells model to use instead of the first model of each library, or '' for none
    val mmc_model

    output:
    // <analysis>.resolved_libraries.tsv: header plus one tab-separated row per library, in manifest order (columns: library_id, dge,
    // cell_metadata, mmc_model, mmc_annotations, reduced_gtf, args_file, files; 'NA' for none, staged files separated by ';').
    // It is for inspection and for the workflow to scatter on; it is not published (see conf/modules.config).
    tuple val(meta), path("${meta.id}.resolved_libraries.tsv"), emit: summary

    script:
    // A resolver error (reference mismatch, duplicate id, mixed MapMyCells models ...) fails the task, so its message is in .command.err
    // and the task directory stays inspectable.
    def failure = null
    def summary = null
    try {
        def artifacts = artifact_texts.collect { LibraryResolver.loadArtifact(it) }
        def result = LibraryResolver.resolve(entries, artifacts, meta.id, [ reference: reference ?: null, mmcModel: mmc_model ?: null ])
        summary = LibraryResolver.summaryText(result)
    } catch (IllegalArgumentException e) {
        failure = e.message
    }
    // The heredoc bodies must not be indented (and not run through stripIndent: the multi-line summary would keep its first line's indent)
    if (failure != null) {
        "cat >&2 <<'RESOLVE_LIBRARIES_EOF'\nCannot resolve the libraries of ${meta.id}: ${failure}\nRESOLVE_LIBRARIES_EOF\nexit 1\n"
    } else {
        "cat > ${meta.id}.resolved_libraries.tsv <<'RESOLVE_LIBRARIES_EOF'\n${summary}RESOLVE_LIBRARIES_EOF\n"
    }

    stub:
    """
    printf 'library_id\\tdge\\tcell_metadata\\tmmc_model\\tmmc_annotations\\treduced_gtf\\targs_file\\tfiles\\n' > ${meta.id}.resolved_libraries.tsv
    """
}
