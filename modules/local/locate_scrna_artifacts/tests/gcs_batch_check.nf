// Live check: does LOCATE_SCRNA_ARTIFACTS read the real gs:// artifacts on Google Batch, with the VM's default service
// account (no service account configured, no credentials mounted)? Not an nf-test, because nf-test always passes a local
// -work-dir and Google Batch needs a gs:// one. Run from the repository root:
//   export GOOGLE_PROJECT_ID=bican-um1-mccarroll GOOGLE_LOCATION=us-central1
//   nextflow run modules/local/locate_scrna_artifacts/tests/gcs_batch_check.nf \
//     -c modules/local/locate_scrna_artifacts/tests/gcs_batch.config \
//     -work-dir gs://mccarroll_scrnaseq_central_temp/nextflow/pipeline-testing/nf-test-batch-work
// A 403 on storage.objects.get in the task log means the VM's service account cannot read the artifact bucket.
include { LOCATE_SCRNA_ARTIFACTS } from '../main'

workflow {
    // Input: one manifest file. Emits: record(meta, artifacts: path('artifacts')) directory of <uei>.yaml files (one item)
    LOCATE_SCRNA_ARTIFACTS( channel.of(record(meta: [ id:'live_analysis' ], manifest: file("${projectDir}/../../../../tests/live_data/manifest.yaml"))) )
    LOCATE_SCRNA_ARTIFACTS.out.artifacts_dir.view { result -> "artifacts for ${result.meta.id}: ${result.artifacts.listFiles()*.name.sort()}" }
}
