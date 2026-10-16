/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { paramsSummaryMap       } from 'plugin/nf-schema'
include { softwareVersionsToYAML } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { LOCATE_SCRNA_ARTIFACTS } from '../modules/local/locate_scrna_artifacts/main'
include { RESOLVE_LIBRARIES      } from '../modules/local/resolve_libraries/main'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow SCRNA_AGGREGATION {

    take:
    ch_manifest // value channel: tuple val(meta), path(manifest); meta.id is the analysis id
    ch_entries  // value channel: list of manifest entries [dge, donor, filters, joins], in manifest order

    main:

    ch_versions = channel.empty()

    // Input: ch_manifest, one item, tuple val(meta), path(manifest) (the aggregation YAML).
    // Emits: LOCATE_SCRNA_ARTIFACTS.out.artifacts_dir, one item, tuple val(meta), path('artifacts'): a directory with one <uei>.yaml per DGE of the manifest
    LOCATE_SCRNA_ARTIFACTS(ch_manifest)

    // Input: artifacts_dir, one item, tuple val(meta), path(artifacts directory).
    // Emits: one item, tuple val(meta), val(list of the YAML text of each <uei>.yaml): the resolver needs the content, not the files.
    ch_artifact_texts = LOCATE_SCRNA_ARTIFACTS.out.artifacts_dir.map { meta, dir -> [ meta, LibraryResolver.readArtifactTexts(dir) ] }

    // Input: the artifact texts (one item), the manifest entries (one item, a list), and the optional --reference and --mmc_model ('' for none).
    // Emits: RESOLVE_LIBRARIES.out.summary, one item, tuple val(meta), path('<analysis>.resolved_libraries.tsv'): one row per library, kept in the
    // task's work directory (not published) for inspection. A resolver error fails this task.
    RESOLVE_LIBRARIES(ch_artifact_texts, ch_entries, params.reference ?: '', params.mmc_model ?: '')

    // Input: the one summary item, tuple val(meta), path(tsv).
    // Emits: one item per library (scatter), tuple val(meta_lib), val(row); meta_lib = [id: library id, analysis_id, mmc_model ('NA' for none)],
    // row = the summary columns as a map (library_id, dge, cell_metadata, mmc_model, mmc_annotations, reduced_gtf, args_file, files; 'NA' for none).
    ch_libraries = RESOLVE_LIBRARIES.out.summary.flatMap { meta, tsv ->
        tsv.splitCsv(sep: '\t', header: true).collect { row ->
            [ [ id: row.library_id, analysis_id: meta.id, mmc_model: row.mmc_model ], row ]
        }
    }

    //
    // Collate and save software versions
    //
    def topic_versions = Channel.topic("versions")
        .distinct()
        .branch { entry ->
            versions_file: entry instanceof Path
            versions_tuple: true
        }

    def topic_versions_string = topic_versions.versions_tuple
        .map { process, tool, version ->
            [ process[process.lastIndexOf(':')+1..-1], "  ${tool}: ${version}" ]
        }
        .groupTuple(by:0)
        .map { process, tool_versions ->
            tool_versions.unique().sort()
            "${process}:\n${tool_versions.join('\n')}"
        }

    softwareVersionsToYAML(ch_versions.mix(topic_versions.versions_file))
        .mix(topic_versions_string)
        .collectFile(
            storeDir: "${params.outdir}/pipeline_info",
            name:  'scrna-aggregation_software_'  + 'versions.yml',
            sort: true,
            newLine: true
        ).set { ch_collated_versions }


    emit:
    versions       = ch_versions                 // channel: [ path(versions.yml) ]

}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
