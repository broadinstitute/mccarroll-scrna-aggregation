nextflow.enable.types = true

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
    RECORD TYPES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

// The aggregation manifest: id is the analysis id (the same for every run-level process).
record Manifest {
    id: String
    manifest: Path
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW TO INITIALISE PIPELINE
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow PIPELINE_INITIALISATION {

    take:
    version: Boolean            // Display version and exit
    validate_params: Boolean    // Whether to validate parameters against the schema at runtime
    _monochrome_logs: Boolean   // Do not use coloured log outputs (unused here)
    nextflow_cli_args: List<String>   // List of positional nextflow CLI args
    outdir: String?             // The output directory where the results will be saved
    manifest: String?           // Path to the aggregation manifest (YAML)
    analysis_id: String?        // Label of this aggregation
    help: String?               // Display help message and exit (the name of a parameter to describe)
    help_full: Boolean          // Show the full help message
    show_hidden: Boolean        // Show hidden parameters in the help message

    main:

    //
    // Fail before any process starts if a local docker run has no usable GCP credentials file to mount
    //
    checkLocalGcpCredentials(workflow.profile, params.gcp_credentials_file, System.getenv('GOOGLE_PROJECT_ID'))

    //
    // Fail before any process starts if both QC condition parameters are given or a QC file cannot be read; warn about QC parameters that run_qc being false makes ignored
    //
    checkQcParams(params.run_qc, params.qc_conditions_file, params.qc_condition_column, params.qc_core_cell_types).each { warning -> log.warn warning }
    checkQcFiles(params.run_qc, params.qc_conditions_file, params.qc_core_cell_types)

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

    // A bare --help reaches params.help as the string 'true', which the nf-core help code below takes for the name of a parameter and fails on
    // ("Specified param 'true' does not exist in JSON schema"). Print the general help here instead, with the same options as that code.
    // --help <parameter name> and --help_full are left to the nf-core code.
    if (help == 'true') {
        log.info paramsHelp(
            [ beforeText: "", afterText: "", command: command, showHidden: show_hidden, fullHelp: false ],
            ""
        )
        exit(0, "")
    }

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
    // Input: params.manifest and params.analysis_id. Emits: ch_manifest, a value channel with one item, a Manifest record, where
    // id is the analysis id (the same for every run-level process)
    //
    ch_manifest = channel.value(record(id: analysis_id, manifest: file(manifest)))

    emit:
    manifest: Value<Manifest> = ch_manifest    // one item: record(id: analysis id, manifest: path)
    entries: Value<List<Map>> = ch_entries     // one item: the list of manifest entries (maps), in manifest order
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW FOR PIPELINE COMPLETION
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow PIPELINE_COMPLETION {

    take:
    _outdir: String?          // Path to output directory where results will be published (unused here)
    monochrome_logs: Boolean  // Disable ANSI colour codes in log output

    main:
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
//   credentialsFileParam: host path of the credentials JSON (params.gcp_credentials_file, null for the default): gcloud Application Default
//                    Credentials (type authorized_user) or a service account key (type service_account)
//   projectId:       value of the GOOGLE_PROJECT_ID environment variable (null or empty if unset). The Google
//                    storage client needs a project; an authorized_user file has none, a service_account key does.
//
def checkLocalGcpCredentials(profile: String, credentialsFileParam: String?, projectId: String?) {
    if (!profile.tokenize(',').contains('docker')) {
        return
    }
    // --gcp_credentials_file, else your gcloud Application Default Credentials (the same default as the docker profile mount)
    def credentialsFile = credentialsFileParam ?: "${System.getProperty('user.home')}/.config/gcloud/application_default_credentials.json"
    def credentials = file(credentialsFile)
    if (!credentials.isFile()) {
        error("GCP credentials not found as a file at '${credentialsFile}'. " +
            "Run 'gcloud auth application-default login' or set --gcp_credentials_file to a credentials JSON " +
            "(Application Default Credentials or a service account key).")
    }
    def json
    try {
        json = new groovy.json.JsonSlurper().parseText(credentials.text)
    } catch (Exception _e) {
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
    def missing = requiredFields[json.type].findAll { field -> !json[field] }
    if (missing) {
        error("GCP credentials file '${credentialsFile}' (${json.type}) is missing required field(s): ${missing.join(', ')}.")
    }
    if (json.type == 'authorized_user' && !projectId) {
        error("A GCP project ID is required with Application Default Credentials. " +
            "Export GOOGLE_PROJECT_ID=<your project id> (the project ID, not the project number).")
    }
}

//
// Check the parameters of the optional QC step, before any process runs.
//   runQc: params.run_qc; conditionsFile, conditionColumn, coreCellTypes: params.qc_conditions_file, qc_condition_column, qc_core_cell_types (null if not given)
//   returns: a warning for each QC parameter given while runQc is false (it is ignored); [] if none. Nothing is warned about when no QC parameter is given.
//   Calls error() if both conditionsFile and conditionColumn are given: they are two ways to give the same condition of each library.
//
def checkQcParams(runQc: Boolean, conditionsFile: String?, conditionColumn: String?, coreCellTypes: String?) -> List<String> {
    if (conditionsFile && conditionColumn) {
        error("Give either --qc_conditions_file or --qc_condition_column, not both: they are two ways to give the condition of each library.")
    }
    if (runQc) {
        return []
    }
    def ignored = conditionsFile ? [ '--qc_conditions_file' ] : []
    def ignoredColumn = conditionColumn ? [ '--qc_condition_column' ] : []
    def ignoredCore = coreCellTypes ? [ '--qc_core_cell_types' ] : []
    return (ignored + ignoredColumn + ignoredCore).collect { name -> "${name} is ignored because --run_qc is not set" }.toList()
}

//
// Check that the files of the QC parameters can be read, before any process runs (a missing file would otherwise fail the QC after all the other steps).
//   runQc: params.run_qc; conditionsFile, coreCellTypes: params.qc_conditions_file and qc_core_cell_types (local or gs:// path, null if not given)
//   returns: the paths checked ([] if none). Nothing is checked unless runQc is true (the parameters are ignored otherwise). Calls error() naming the parameter and the path for a file that
//   does not exist, is a directory, or cannot be read (no permission, no access to the bucket).
//
def checkQcFiles(runQc: Boolean, conditionsFile: String?, coreCellTypes: String?) -> List<String> {
    def conditions = runQc && conditionsFile ? [ checkReadable('--qc_conditions_file', conditionsFile) ] : []
    def core = runQc && coreCellTypes ? [ checkReadable('--qc_core_cell_types', coreCellTypes) ] : []
    return conditions + core
}

// Reads the file (these are small text files) and returns its path; error() naming the parameter and the path if that fails.
def checkReadable(parameter: String, path: String) -> String {
    try {
        java.nio.file.Files.readAllBytes(file(path))
    } catch (java.nio.file.NoSuchFileException _e) {
        error("The file of ${parameter} was not found: '${path}'.")
    } catch (IOException e) {
        error("The file of ${parameter} cannot be read: '${path}' (${e.getMessage()}).")
    }
    return path
}

//
// Read and validate the aggregation manifest (YAML), before any process runs.
//   manifestPath: local or gs:// path of the manifest (params.manifest)
//   returns: one map per DGE in manifest order, [dge, donor, filters, joins], with dgeDefaults projected onto each
//            entry; see lib/AggregationManifest.groovy. Also checks that the files of each entry can be staged (lib/JoinFilterArguments.groovy)
//            and that every file the manifest names exists (DGEs, joinFile, includeFile, excludeFile; local or gs://, read with this run's
//            credentials). Calls error() naming the path and the problem if invalid, listing every missing file at once.
//
def loadAggregationManifest(manifestPath: String) -> List<Map> {
    def manifestFile = file(manifestPath)
    if (!manifestFile.exists()) {
        error("Aggregation manifest not found: '${manifestPath}'.")
    }
    try {
        def entries = AggregationManifest.parse(manifestFile.text)
        // builds the arguments of each entry only to report a problem (two files staged under one name) before any process runs
        entries.each { entry -> JoinFilterArguments.build(entry) }
        AggregationManifest.checkFilesExist(entries, { path -> AggregationManifest.pathExists(file(path)) })
        return entries
    } catch (IllegalArgumentException e) {
        error("Invalid aggregation manifest '${manifestPath}': ${e.getMessage()}")
        return []   // not reached: error() stops the run
    }
}
