// Live check: can a Google Batch task read a gs:// object with the VM's default service account (no credentials mounted)?
// Reads the size and the first 1 KiB of one object (--gcs_object), so a large FASTQ is not downloaded.
// Not an nf-test: nf-test always passes a local -work-dir and Google Batch needs a gs:// one. Run from the repository root:
//   export GOOGLE_PROJECT_ID=bican-um1-mccarroll GOOGLE_LOCATION=us-central1
//   nextflow run tests/batch_access_check -c tests/batch_access_check/nextflow.config \
//     -work-dir gs://bican-um1-mccarroll_temp/nextflow/batch-access-check-work \
//     --gcs_object gs://<bucket>/<path>
// A 403 / Forbidden in the task output means the VM's service account cannot read that object.
params.gcs_object = null

process CHECK_GCS_READ {
    container 'quay.io/broadinstitute/drop-seq_python:current'
    label 'process_single'

    input:
    val gcs_object

    output:
    stdout emit: report

    script:
    """
    /usr/local/dropseq/venv/dropseq/bin/python - <<'PY'
    from google.cloud import storage
    bucket, name = "${gcs_object}".removeprefix("gs://").split("/", 1)
    blob = storage.Client().bucket(bucket).get_blob(name)
    assert blob is not None, "object not found: ${gcs_object}"
    head = blob.download_as_bytes(start=0, end=1023)
    print(f"OK size={blob.size} first_bytes_read={len(head)} object=${gcs_object}")
    PY
    """
}

workflow {
    if (!params.gcs_object) { error "Give --gcs_object gs://<bucket>/<path>" }
    // Input: one gs:// URL value. Emits: one stdout report string
    CHECK_GCS_READ(channel.value(params.gcs_object)).report.view()
}
