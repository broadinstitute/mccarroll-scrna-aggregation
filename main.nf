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
    mmc_model: String?              // MapMyCells model to use instead of the first model of each library
    mmc_level: String?              // MapMyCells taxonomy level for the cell type column
    run_qc: Boolean                 // run the optional aggregation QC step
    qc_conditions_file: String?     // QC: TSV (library, condition), local path or gs://
    qc_condition_column: String?    // QC: cell metadata column holding the condition of each library
    qc_core_cell_types: String?     // QC: file with one core cell type per line
    outdir: String?                 // directory where the results are published
    gcp_credentials_file: String?   // GCP credentials JSON mounted into task containers (docker profile)

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
    manifest: Value<Manifest>   // one item: record(id: analysis id, manifest: path)
    entries: Value<List<Map>>   // one item: the list of manifest entries, in manifest order
    mmc_model: String?          // params.mmc_model, the MapMyCells model that replaces each library's first model
    run_qc: Boolean             // params.run_qc, run the optional QC step
    qc_conditions_file: String? // params.qc_conditions_file
    qc_condition_column: String? // params.qc_condition_column
    qc_core_cell_types: String? // params.qc_core_cell_types

    main:

    //
    // WORKFLOW: Run pipeline
    //
    results = SCRNA_AGGREGATION (
        manifest,
        entries,
        mmc_model,
        run_qc,
        qc_conditions_file,
        qc_condition_column,
        qc_core_cell_types
    )

    // The published files, one channel of paths each (see the output block below).
    emit:
    artifacts: Value<Path> = results.artifacts
    tearsheets: Channel<Path> = results.tearsheets
    library_metrics: Value<Path> = results.library_metrics
    cell_metadata: Value<Path> = results.cell_metadata
    h5ad: Channel<Path> = results.h5ad
    matrix: Value<Path> = results.matrix
    barcodes: Value<Path> = results.barcodes
    features: Value<Path> = results.features
    donor_cell_type_report: Channel<Path> = results.donor_cell_type_report
    qc_pdfs: Channel<Path> = results.qc_pdfs
    qc_donor_qc: Channel<Path> = results.qc_donor_qc
    donor_metacells: Channel<Path> = results.donor_metacells
    donor_cell_type_metacells: Channel<Path> = results.donor_cell_type_metacells
    resolved_summary: Value<Path> = results.resolved_summary
    versions_file: Value<Path> = results.versions_file
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
    // Emits: init.manifest (one Manifest record, id is the analysis id) and init.entries (one list of manifest entries).
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
    results = MCCARROLL_SCRNA_AGGREGATION (
        init.manifest,
        init.entries,
        params.mmc_model,
        params.run_qc,
        params.qc_conditions_file,
        params.qc_condition_column,
        params.qc_core_cell_types
    )
    //
    // SUBWORKFLOW: Run completion tasks
    //
    PIPELINE_COMPLETION (
        params.outdir,
        params.monochrome_logs,
    )

    // Each name is a channel of paths from the main workflow; the output block says where it is published, under --outdir.
    publish:
    artifacts = results.artifacts
    tearsheets = results.tearsheets
    library_metrics = results.library_metrics
    cell_metadata = results.cell_metadata
    h5ad = results.h5ad
    matrix = results.matrix
    barcodes = results.barcodes
    features = results.features
    donor_cell_type_report = results.donor_cell_type_report
    qc_pdfs = results.qc_pdfs
    qc_donor_qc = results.qc_donor_qc
    donor_metacells = results.donor_metacells
    donor_cell_type_metacells = results.donor_cell_type_metacells
    resolved_summary = results.resolved_summary
    versions_file = results.versions_file
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    OUTPUT: where the published files go, relative to --outdir (outputDir in nextflow.config)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Nothing else is published: the per-library intermediates stay in the work directories. The merged results are flat in --outdir.
*/

output {
    // per-library records: artifacts/<uei>.yaml (the directory LOCATE writes) and tearsheets/<uei>.standard_analysis_tearsheet.txt
    artifacts                 { path '.' }
    tearsheets                { path '.' }   // the task output is already tearsheets/<uei>.standard_analysis_tearsheet.txt
    // merged results, flat
    library_metrics           { path '.' }
    cell_metadata             { path '.' }
    h5ad                      { path '.' }   // the task output is already h5ad/<uei>.h5ad
    matrix                    { path '.' }
    barcodes                  { path '.' }
    features                  { path '.' }
    donor_cell_type_report    { path '.' }
    // the optional QC step (run_qc): the PDFs and donor_qc.txt, flat with the legacy names
    qc_pdfs                   { path '.' }
    qc_donor_qc               { path '.' }
    donor_metacells           { path '.' }
    donor_cell_type_metacells { path '.' }
    // pipeline_info/
    resolved_summary          { path 'pipeline_info' }
    versions_file             { path 'pipeline_info' }
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
