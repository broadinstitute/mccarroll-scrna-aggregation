#!/usr/bin/env nextflow

nextflow.enable.types = true
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    mccarroll/scrna-aggregation
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Github : https://github.com/mccarroll/scrna-aggregation
----------------------------------------------------------------------------------------
*/

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT FUNCTIONS / MODULES / SUBWORKFLOWS / WORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { SCRNA_AGGREGATION  } from './workflows/scrna-aggregation'
include { Manifest                } from './subworkflows/local/utils_nfcore_scrna-aggregation_pipeline'
include { PIPELINE_INITIALISATION } from './subworkflows/local/utils_nfcore_scrna-aggregation_pipeline'
include { PIPELINE_COMPLETION     } from './subworkflows/local/utils_nfcore_scrna-aggregation_pipeline'
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    PARAMETERS (types only: the default values are in conf/params.config)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Path-like parameters are Strings on purpose: they may be gs:// URLs, and the pipeline checks them itself
    (nf-schema and PIPELINE_INITIALISATION) with messages that name the parameter.
    A String? parameter is optional (null when not given); the others always have a default in conf/params.config.
    `help` is a String?: --help <parameter name> describes that parameter. A bare --help (the schema also allows a flag) reaches the
    nf-core help code as the string 'true' and fails there with "Specified param 'true' does not exist in JSON schema" (it did before typing too).
*/

params {
    // Input options
    manifest: String?               // YAML aggregation manifest (local path or gs://)
    analysis_id: String?            // label of this aggregation: prefix of the merged output files
    reference: String?              // reference name that skips the check that all libraries have the same one
    mmc_model: String?              // MapMyCells model to use instead of the first model of each library
    mmc_level: String?              // MapMyCells taxonomy level for the cell type column
    outdir: String?                 // directory where the results are published
    gcp_credentials_file: String    // GCP credentials JSON mounted into task containers (docker profile)

    // Boilerplate options
    publish_dir_mode: String
    monochrome_logs: Boolean
    help: String?                   // display the help and exit; --help <parameter name> describes that parameter
    help_full: Boolean
    show_hidden: Boolean
    version: Boolean
    validate_params: Boolean
    pipelines_testdata_base_path: String
    trace_report_suffix: String

    // Config options
    config_profile_name: String?
    config_profile_description: String?
    config_profile_contact: String?
    config_profile_url: String?
    custom_config_version: String
    custom_config_base: String
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    NAMED WORKFLOWS FOR PIPELINE
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// WORKFLOW: Run main analysis pipeline depending on type of input
//
workflow MCCARROLL_SCRNA_AGGREGATION {

    take:
    manifest: Value<Manifest>   // one item: record(meta: [id: analysis id], manifest: path)
    entries: Value<List<Map>>   // one item: the list of manifest entries, in manifest order
    reference: String?          // params.reference, the reference name that skips the same-reference check
    mmc_model: String?          // params.mmc_model, the MapMyCells model that replaces each library's first model

    main:

    //
    // WORKFLOW: Run pipeline
    //
    SCRNA_AGGREGATION (
        manifest,
        entries,
        reference,
        mmc_model
    )
}
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow {

    main:
    //
    // SUBWORKFLOW: Run initialisation tasks
    //
    // Emits: init.manifest (one Manifest record, meta.id is the analysis id) and init.entries (one list of manifest entries).
    init = PIPELINE_INITIALISATION (
        params.version,
        params.validate_params,
        params.monochrome_logs,
        args,
        params.outdir,
        params.manifest,
        params.analysis_id,
        params.help,
        params.help_full,
        params.show_hidden
    )

    //
    // WORKFLOW: Run main workflow
    //
    MCCARROLL_SCRNA_AGGREGATION (
        init.manifest,
        init.entries,
        params.reference,
        params.mmc_model
    )
    //
    // SUBWORKFLOW: Run completion tasks
    //
    PIPELINE_COMPLETION (
        params.outdir,
        params.monochrome_logs,
    )
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
