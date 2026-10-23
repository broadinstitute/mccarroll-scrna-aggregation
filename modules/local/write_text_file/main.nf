nextflow.enable.types = true

// Writes one text file in the task work directory, in the Nextflow head job (no container, no script). It replaces collectFile for files made
// of known text. Include it under an alias per file (WRITE_RESOLVED_SUMMARY, WRITE_VERSIONS, ...) so each can be published on its own in a config.
process WRITE_TEXT_FILE {
    tag "$name"

    input:
    // name: the file name; text: its exact content (nothing is added)
    record(
        name: String,
        text: String
    )

    output:
    file(name)

    exec:
    task.workDir.resolve(name).text = text
}
