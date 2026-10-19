/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { paramsSummaryMap       } from 'plugin/nf-schema'
include { softwareVersionsToYAML } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { LOCATE_SCRNA_ARTIFACTS } from '../modules/local/locate_scrna_artifacts/main'
include { FORMAT_MAPMYCELLS_ANNOTATIONS } from '../modules/local/format_mapmycells_annotations/main'
include { BUILD_LIBRARY_CELL_METADATA } from '../modules/local/build_library_cell_metadata/main'
include { SUMMARIZE_SCRNA_EXPERIMENTS } from '../modules/local/summarize_scrna_experiments/main'
include { MERGE_LIBRARY_METADATA as MERGE_LIBRARY_METRICS } from '../modules/local/merge_library_metadata/main'
include { MERGE_LIBRARY_METADATA as MERGE_CELL_METADATA } from '../modules/local/merge_library_metadata/main'
include { MAKE_TRIPLET_DGE } from '../modules/local/make_triplet_dge/main'
include { DONOR_CELL_TYPE_REPORT } from '../modules/local/donor_cell_type_report/main'
include { MAKE_METACELLS_FROM_TRIPLET_DGE as DONOR_METACELLS } from '../modules/local/make_metacells_from_triplet_dge/main'
include { MAKE_METACELLS_FROM_TRIPLET_DGE as DONOR_CELL_TYPE_METACELLS } from '../modules/local/make_metacells_from_triplet_dge/main'

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

    // Input: the artifact texts (one item), the manifest entries (one item, a list; wrapped in a list so that combine does not flatten it), and the
    // optional --reference and --mmc_model. LibraryResolver.resolve matches each manifest entry with the artifacts of its library and decides what
    // each library is processed from (see lib/LibraryResolver.groovy).
    // Emits: one item, the resolver result Map [analysisId, libraries: [library id -> record], reducedGtf, reference]. A resolver error stops the run.
    ch_resolved = ch_artifact_texts
        .combine(ch_entries.map { entries -> [ entries ] })
        .map { meta, artifact_texts, entries ->
            try {
                def artifacts = artifact_texts.collect { text -> LibraryResolver.loadArtifact(text) }
                LibraryResolver.resolve(entries, artifacts, meta.id, [ reference: params.reference ?: null, mmcModel: params.mmc_model ?: null ])
            } catch (IllegalArgumentException e) {
                error("Cannot resolve the libraries of ${meta.id}: ${e.message}")
            }
        }

    // Input: the resolver result, one item.
    // Emits: <analysis>.resolved_libraries.txt, plain text for a person to read: the files and arguments each library is processed with.
    // Published to <outdir>/pipeline_info/; nothing reads it back.
    ch_resolved.collectFile(storeDir: "${params.outdir}/pipeline_info") { result ->
        [ "${result.analysisId}.resolved_libraries.txt", LibraryResolver.summaryText(result) ]
    }

    // Input: the resolver result, one item.
    // Emits: one item per library (scatter), tuple val(meta_lib), val(record); meta_lib = [id: library id, analysis_id, mmc_model ('NA' for none),
    // position (0-based position in the manifest: the order in which libraries are merged)],
    // record = [libraryId, position, dge, cellMetadata, mmcModel, mmcAnnotations ('NA' for none), args (List<String>), files (List<String>, [] for none)].
    ch_libraries = ch_resolved.flatMap { result ->
        result.libraries.collect { library_id, record ->
            [ [ id: library_id, analysis_id: result.analysisId, mmc_model: record.mmcModel, position: record.position ], record ]
        }
    }

    // Input: LOCATE_SCRNA_ARTIFACTS.out.artifacts_dir, one item, tuple val(meta), path(artifacts directory).
    // Emits: one item per artifact YAML (scatter), tuple val(library id), path('<library id>.yaml'); the file name is the library id (artifact uei).
    ch_artifact_files = LOCATE_SCRNA_ARTIFACTS.out.artifacts_dir.flatMap { _meta, dir ->
        dir.listFiles().findAll { f -> f.name.endsWith(".yaml") }.collect { f -> [ f.name - '.yaml', f ] }
    }

    // Input: ch_libraries (tuple val(meta_lib), val(record), keyed by meta_lib.id) and ch_artifact_files (tuple val(library id), path(yaml)).
    // Emits: one item per library, tuple val(meta_lib), path(artifact yaml); joined on library id, so each library gets its own YAML.
    // A library without an artifact YAML would be dropped by join: the resolver already failed in that case.
    ch_library_artifacts = ch_libraries
        .map { meta_lib, _record -> [ meta_lib.id, meta_lib ] }
        .join(ch_artifact_files)
        .map { _library_id, meta_lib, yaml -> [ meta_lib, yaml ] }

    // Input: tuple val(meta_lib), path(artifact yaml), one item per library.
    // Emits: SUMMARIZE_SCRNA_EXPERIMENTS.out.metrics (tuple val(meta_lib), path('<library>.library_metrics.txt'), one row each) and
    // .tearsheet (tuple val(meta_lib), path('tearsheets/<library>.standard_analysis_tearsheet.txt')), one item per library.
    SUMMARIZE_SCRNA_EXPERIMENTS(ch_library_artifacts)

    // Input: SUMMARIZE_SCRNA_EXPERIMENTS.out.metrics, one item per library, tuple val(meta_lib), path(metrics).
    // Emits: one item, tuple val(meta) with meta.id = analysis id, path(list of metrics files in manifest order): the merge order is the input order.
    // toSortedList returns one list of the tuples (not flattened); the map reshapes it.
    ch_metrics_sorted = SUMMARIZE_SCRNA_EXPERIMENTS.out.metrics
        .toSortedList { a, b -> a[0].position <=> b[0].position }
        .map { items -> [ [ id: items[0][0].analysis_id ], items.collect { item -> item[1] } ] }

    // Input: one item, tuple val(meta), path(metrics files, in manifest order).
    // Emits: MERGE_LIBRARY_METRICS.out.combined, one item, tuple val(meta), path('<analysis>.library_metrics.txt') (ext.prefix in conf/modules.config).
    MERGE_LIBRARY_METRICS(ch_metrics_sorted)

    // Input: ch_libraries, one item per library, tuple val(meta_lib), val(record); record.args is the list of join_and_filter_tsv arguments.
    // Emits: one item per library, tuple val(library id), path('<library>.join_and_filter_args.txt'): the arguments one per line, written by
    // collectFile in the work directory (not published). Libraries with no arguments get an empty file.
    ch_args_files = ch_libraries
        .collectFile { meta_lib, record -> [ LibraryResolver.argsFileName(meta_lib.id), JoinFilterArguments.toArgsFileText(record.args) ] }
        .map { f -> [ f.name - '.join_and_filter_args.txt', f ] }

    // Input: ch_libraries, filtered to the libraries that have MapMyCells results (record.mmcAnnotations != 'NA').
    // Emits: one item per such library, tuple val(meta_lib), path(MapMyCells result csv); the csv is localized from its gs:// path.
    ch_mmc_csv = ch_libraries
        .filter { _meta_lib, record -> record.mmcAnnotations != LibraryResolver.NA }
        .map { meta_lib, record -> [ meta_lib, file(record.mmcAnnotations) ] }

    // Input: tuple val(meta_lib), path(csv), one item per library with MapMyCells results.
    // Emits: .converted (tuple val(meta_lib), path('<library>.mmc.tsv'), not published) and .cell_type_column (tuple val(meta_lib), val(column name)).
    FORMAT_MAPMYCELLS_ANNOTATIONS(ch_mmc_csv)

    // Input: .cell_type_column, one item per library with MapMyCells results, tuple val(meta_lib), val(column).
    // Emits: one item (value channel), val(the cell type column shared by all libraries, or '' if no library has MapMyCells results);
    // LibraryResolver.checkCellTypeColumn fails the run if the libraries disagree.
    ch_cell_type_column = FORMAT_MAPMYCELLS_ANNOTATIONS.out.cell_type_column
        .toList()
        .map { items -> LibraryResolver.checkCellTypeColumn(items.collectEntries { meta_lib, column -> [ (meta_lib.id): column ] }) ?: '' }

    // Input: ch_cell_type_column (one value), ch_libraries (only for the analysis id).
    // Emits: <analysis>.cell_type_column.txt, one file with the column name, published to <outdir>; nothing if there is no column.
    ch_cell_type_column
        .filter { column -> column }
        .combine(ch_libraries.first().map { meta_lib, _record -> meta_lib.analysis_id })
        .collectFile(storeDir: params.outdir, newLine: true) { column, analysis_id -> [ "${analysis_id}.cell_type_column.txt", column ] }

    // Input: ch_libraries, one item per library, tuple val(meta_lib), val(record).
    // Emits: tuple val(library id), val(meta_lib), path(cell metadata), val(list of extra files to stage, [] for none).
    ch_build_base = ch_libraries.map { meta_lib, record ->
        [ meta_lib.id, meta_lib, file(record.cellMetadata), record.files.collect { f -> file(f) } ]
    }

    // Input: FORMAT_MAPMYCELLS_ANNOTATIONS.out.converted, one item per library with results, tuple val(meta_lib), path(mmc tsv).
    // Emits: tuple val(library id), path(mmc tsv), keyed so it can be joined with ch_build_base.
    ch_mmc_tsv_by_id = FORMAT_MAPMYCELLS_ANNOTATIONS.out.converted.map { meta_lib, tsv -> [ meta_lib.id, tsv ] }

    // Input: ch_build_base (all libraries), ch_mmc_tsv_by_id (libraries with results; remainder: true keeps the others with a null), ch_args_files.
    // Emits: one item per library, tuple val(meta_lib), path(cell metadata), path(mmc tsv or []), path(args file), path(extra files or []):
    // the exact input of BUILD_LIBRARY_CELL_METADATA, with [] placeholders for the optional paths.
    ch_build_input = ch_build_base
        .join(ch_mmc_tsv_by_id, remainder: true)
        .join(ch_args_files)
        .map { _id, meta_lib, cell_metadata, extra_files, mmc_tsv, args_file -> [ meta_lib, cell_metadata, mmc_tsv ?: [], args_file, extra_files ] }

    // Input: tuple val(meta_lib), path(cell metadata), path(mmc tsv or []), path(args file), path(extra files or []), one item per library.
    // Emits: BUILD_LIBRARY_CELL_METADATA.out.cell_metadata, tuple val(meta_lib), path('<library>.joined_filtered_cell_metadata.txt'), one item per library.
    BUILD_LIBRARY_CELL_METADATA(ch_build_input)

    // Input: BUILD_LIBRARY_CELL_METADATA.out.cell_metadata, one item per library, tuple val(meta_lib), path(joined and filtered cell metadata);
    // ch_libraries, for the DGE each library is processed from (record.dge: the DGE the manifest names, localized from its gs:// path).
    // Emits: ONE list with one element per library, in manifest order (meta_lib.position): [library id, meta_lib, path(cell metadata), path(DGE)].
    // Both the merged cell metadata and the sparse DGE are made from this one list, so the rows of the merged metadata and the columns of the
    // matrix are in the same library order, and the i-th prefix, DGE and barcode list always belong to the same library.
    ch_built_sorted = BUILD_LIBRARY_CELL_METADATA.out.cell_metadata
        .map { meta_lib, cell_metadata -> [ meta_lib.id, meta_lib, cell_metadata ] }
        .join(ch_libraries.map { meta_lib, record -> [ meta_lib.id, file(record.dge) ] })
        .toSortedList { a, b -> a[1].position <=> b[1].position }

    // Input: ch_built_sorted, one list of [library id, meta_lib, cell metadata, DGE].
    // Emits: one item, tuple val(meta) with meta.id = analysis id, path(list of the per-library cell metadata files, in manifest order).
    ch_cell_metadata_files = ch_built_sorted.map { items ->
        [ [ id: items[0][1].analysis_id ], items.collect { item -> item[2] } ]
    }

    // Input: one item, tuple val(meta), path(per-library cell metadata files in manifest order).
    // Emits: MERGE_CELL_METADATA.out.combined, one item, tuple val(meta), path('<analysis>.cell_metadata.txt'), indexed by (PREFIX, cell_barcode):
    // a duplicate cell fails the task (ext.args and ext.prefix in conf/modules.config).
    MERGE_CELL_METADATA(ch_cell_metadata_files)

    // Input: ch_built_sorted.
    // Emits: one item, tuple val(meta) with meta.id = analysis id, val(list of prefixes = library ids), path(list of DGEs), path(list of barcode lists);
    // the three lists have one element per library, in the same (manifest) order.
    ch_triplet_input = ch_built_sorted.map { items ->
        [ [ id: items[0][1].analysis_id ], items.collect { item -> item[0] }, items.collect { item -> item[3] }, items.collect { item -> item[2] } ]
    }

    // Input: the resolver result, one item.
    // Emits: one item (value), path(reduced GTF), localized from its gs:// path; every library has the same one (checked by the resolver).
    ch_reduced_gtf = ch_resolved.map { result -> file(result.reducedGtf) }

    // Input: ch_triplet_input and ch_reduced_gtf, one item each.
    // Emits: MAKE_TRIPLET_DGE.out.matrix, .barcodes and .features, each one item, tuple val(meta), path(matrix.mtx.gz / barcodes.tsv.gz / features.tsv.gz):
    // genes x the cells of all libraries (barcodes are <library id>_<cell barcode>), in library order.
    MAKE_TRIPLET_DGE(ch_triplet_input, ch_reduced_gtf)

    // The donor steps need donors, which the resolver knows from the manifest and the artifacts (all libraries have donors or none do), and the
    // cell type steps also need a cell type column (some library has MapMyCells results). A missing piece skips the steps with a warning.
    // Input: the resolver result (one item) and ch_cell_type_column (one value, '' for none).
    // Emits: ch_donors, one item (true) only if the libraries have donors, else nothing; ch_cell_type, one item (the column name) only if there is one.
    ch_donors = ch_resolved.filter { result -> result.hasDonors }.map { _result -> true }
    ch_cell_type = ch_cell_type_column.filter { column -> column }
    ch_resolved.filter { result -> !result.hasDonors }.subscribe { result ->
        log.warn "The libraries of ${result.analysisId} have no donors (no donor in the manifest, no village in the artifacts): no donor reports or metacells"
    }
    ch_cell_type_column.filter { column -> !column }.subscribe { _column ->
        log.warn "No library has MapMyCells results: no donor by cell type report or metacells"
    }

    // Input: MAKE_TRIPLET_DGE.out.matrix, .features and .barcodes and MERGE_CELL_METADATA.out.combined, each one item, tuple val(meta), path(file);
    // meta is [id: analysis id] in all of them. Combined with ch_donors, so nothing is emitted for libraries without donors.
    // Emits: one item, tuple val(meta), path(matrix), path(features), path(barcodes), path(merged cell metadata).
    ch_metacell_inputs = MAKE_TRIPLET_DGE.out.matrix
        .join(MAKE_TRIPLET_DGE.out.features)
        .join(MAKE_TRIPLET_DGE.out.barcodes)
        .join(MERGE_CELL_METADATA.out.combined)
        .combine(ch_donors)
        .map { meta, matrix, features, barcodes, cell_metadata, _donors -> [ meta, matrix, features, barcodes, cell_metadata ] }

    // Input: ch_metacell_inputs (one item, only with donors).
    // Emits: DONOR_METACELLS.out.metacells, one item, tuple val(meta), path('<analysis>.donors.metacells.txt.gz'): expression summed per donor.
    DONOR_METACELLS(ch_metacell_inputs.map { meta, matrix, features, barcodes, cell_metadata -> [ meta, matrix, features, barcodes, cell_metadata, [ 'donor' ] ] })

    // Input: ch_metacell_inputs and ch_cell_type, so one item only with donors and a cell type column.
    // Emits: DONOR_CELL_TYPE_METACELLS.out.metacells, one item, tuple val(meta), path('<analysis>.donor_cell_type.metacells.txt.gz'): expression summed
    // per donor and cell type.
    DONOR_CELL_TYPE_METACELLS(
        ch_metacell_inputs.combine(ch_cell_type).map { meta, matrix, features, barcodes, cell_metadata, column ->
            [ meta, matrix, features, barcodes, cell_metadata, [ 'donor', column ] ]
        }
    )

    // Input: MERGE_CELL_METADATA.out.combined (one item), ch_donors and ch_cell_type, so one item only with donors and a cell type column.
    // Emits: DONOR_CELL_TYPE_REPORT.out.report, one item, tuple val(meta), path('<analysis>.donor_cell_type.txt'): the cells and median UMIs per donor
    // and cell type.
    DONOR_CELL_TYPE_REPORT(
        MERGE_CELL_METADATA.out.combined.combine(ch_donors).combine(ch_cell_type).map { meta, cell_metadata, _donors, column -> [ meta, cell_metadata, column ] }
    )

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
