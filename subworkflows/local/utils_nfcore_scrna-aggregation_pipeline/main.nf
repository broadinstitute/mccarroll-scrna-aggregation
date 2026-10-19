//
// Subworkflow with functionality specific to the mccarroll/scrna-aggregation pipeline
//

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT FUNCTIONS / MODULES / SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { UTILS_NFSCHEMA_PLUGIN     } from '../../nf-core/utils_nfschema_plugin'
include { paramsSummaryMap          } from 'plugin/nf-schema'
include { paramsHelp                } from 'plugin/nf-schema'
include { completionSummary         } from '../../nf-core/utils_nfcore_pipeline'
include { UTILS_NFCORE_PIPELINE     } from '../../nf-core/utils_nfcore_pipeline'
include { UTILS_NEXTFLOW_PIPELINE   } from '../../nf-core/utils_nextflow_pipeline'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW TO INITIALISE PIPELINE
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow PIPELINE_INITIALISATION {

    take:
    version           // boolean: Display version and exit
    validate_params   // boolean: Boolean whether to validate parameters against the schema at runtime
    monochrome_logs   // boolean: Do not use coloured log outputs
    nextflow_cli_args //   array: List of positional nextflow CLI args
    outdir            //  string: The output directory where the results will be saved
    manifest          //  string: Path to the aggregation manifest (YAML)
    analysis_id       //  string: Label of this aggregation
    help              // boolean: Display help message and exit
    help_full         // boolean: Show the full help message
    show_hidden       // boolean: Show hidden parameters in the help message

    main:

    ch_versions = channel.empty()

    //
    // Fail before any process starts if a local docker run has no usable GCP credentials file to mount
    //
    checkLocalGcpCredentials(workflow.profile, params.gcp_credentials_file, System.getenv('GOOGLE_PROJECT_ID'))

    //
    // Print version and exit if required and dump pipeline parameters to JSON file
    //
    UTILS_NEXTFLOW_PIPELINE (
        version,
        true,
        outdir,
        workflow.profile.tokenize(',').intersect(['conda', 'mamba']).size() >= 1
    )

    //
    // Validate parameters and generate parameter summary to stdout
    //
    command = "nextflow run ${workflow.manifest.name} -profile <docker/singularity/.../institute> --manifest manifest.yaml --analysis_id <ID> --outdir <OUTDIR>"

    UTILS_NFSCHEMA_PLUGIN (
        workflow,
        validate_params,
        null,
        help,
        help_full,
        show_hidden,
        "",
        "",
        command
    )

    //
    // Check config provided to the pipeline
    //
    UTILS_NFCORE_PIPELINE (
        nextflow_cli_args
    )

    //
    // Read and validate the aggregation manifest before any process starts (unknown keys, bad filters or joins, duplicate DGEs, files that
    // would be staged under one name); an invalid manifest stops the run here, naming the file and the DGE entry
    // Input: params.manifest, a YAML file. Emits: ch_entries, a value channel holding the list of entries (one map per DGE, manifest order:
    // dge, donor, filters, joins, with dgeDefaults projected onto each).
    //
    def manifest_entries = loadAggregationManifest(manifest)
    ch_entries = channel.value(manifest_entries)

    //
    // Input: params.manifest and params.analysis_id. Emits: ch_manifest, a value channel with one item, tuple val(meta), path(manifest), where
    // meta.id is the analysis id (the same for every run-level process)
    //
    ch_manifest = channel.value([ [ id: analysis_id ], file(manifest) ])

    emit:
    manifest    = ch_manifest   // value channel: tuple val(meta), path(manifest)
    entries     = ch_entries    // value channel: List of manifest entries (maps)
    versions    = ch_versions
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW FOR PIPELINE COMPLETION
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow PIPELINE_COMPLETION {

    take:
    outdir          //    path: Path to output directory where results will be published
    monochrome_logs // boolean: Disable ANSI colour codes in log output

    main:
    summary_params = paramsSummaryMap(workflow, parameters_schema: "nextflow_schema.json")

    //
    // Completion email and summary
    //
    workflow.onComplete {

        completionSummary(monochrome_logs)
    }

    workflow.onError {
        log.error "Pipeline failed. Please refer to troubleshooting docs: https://nf-co.re/docs/usage/troubleshooting"
    }
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// Fail fast when a local (docker profile) run cannot mount usable GCP credentials.
// If the host file is missing, Docker silently creates a directory at the mount source and tasks
// then fail later with an obscure credentials error.
//   profile:         comma-separated Nextflow profile string, e.g. 'docker'
//   credentialsFile: host path of the credentials JSON (params.gcp_credentials_file): gcloud Application Default
//                    Credentials (type authorized_user) or a service account key (type service_account)
//   projectId:       value of the GOOGLE_PROJECT_ID environment variable (null or empty if unset). The Google
//                    storage client needs a project; an authorized_user file has none, a service_account key does.
//
def checkLocalGcpCredentials(String profile, String credentialsFile, String projectId) {
    if (!profile.tokenize(',').contains('docker')) {
        return
    }
    def credentials = file(credentialsFile)
    if (!credentials.isFile()) {
        error("GCP credentials not found as a file at '${credentialsFile}'. " +
            "Run 'gcloud auth application-default login' or set --gcp_credentials_file to a credentials JSON " +
            "(Application Default Credentials or a service account key).")
    }
    def json
    try {
        json = new groovy.json.JsonSlurper().parseText(credentials.text)
    } catch (Exception e) {
        json = null
    }
    if (!(json instanceof Map)) {
        error("GCP credentials file '${credentialsFile}' is not valid JSON.")
    }
    def requiredFields = [
        authorized_user: ['client_id', 'client_secret', 'refresh_token'],
        service_account: ['client_email', 'private_key']
    ]
    if (!requiredFields.containsKey(json.type)) {
        error("GCP credentials file '${credentialsFile}' has unsupported credential type '${json.type}'; " +
            "expected one of ${requiredFields.keySet().join(', ')}.")
    }
    def missing = requiredFields[json.type].findAll { !json[it] }
    if (missing) {
        error("GCP credentials file '${credentialsFile}' (${json.type}) is missing required field(s): ${missing.join(', ')}.")
    }
    if (json.type == 'authorized_user' && !projectId) {
        error("A GCP project ID is required with Application Default Credentials. " +
            "Export GOOGLE_PROJECT_ID=<your project id> (the project ID, not the project number).")
    }
}

//
// Read and validate the aggregation manifest (YAML), before any process runs.
//   manifestPath: local or gs:// path of the manifest (params.manifest)
//   returns: one map per DGE in manifest order, [dge, donor, filters, joins], with dgeDefaults projected onto each
//            entry; see lib/AggregationManifest.groovy. Also checks that the files of each entry can be staged (lib/JoinFilterArguments.groovy).
//            Calls error() naming the path and the problem if invalid.
//
def loadAggregationManifest(String manifestPath) {
    def manifestFile = file(manifestPath)
    if (!manifestFile.exists()) {
        error("Aggregation manifest not found: '${manifestPath}'.")
    }
    try {
        def entries = AggregationManifest.parse(manifestFile.text)
        // builds the arguments of each entry only to report a problem (two files staged under one name) before any process runs
        entries.each { entry -> JoinFilterArguments.build(entry) }
        return entries
    } catch (IllegalArgumentException e) {
        error("Invalid aggregation manifest '${manifestPath}': ${e.message}")
    }
}
