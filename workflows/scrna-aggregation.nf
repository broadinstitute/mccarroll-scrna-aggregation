nextflow.enable.types = true

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { workflowVersionToYAML  } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { Manifest               } from '../subworkflows/local/utils_nfcore_scrna-aggregation_pipeline'
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
include { WRITE_TEXT_FILE as WRITE_RESOLVED_SUMMARY } from '../modules/local/write_text_file/main'
include { WRITE_TEXT_FILE as WRITE_VERSIONS } from '../modules/local/write_text_file/main'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RECORD TYPES (Manifest, the input of this workflow, is declared with the initialisation that makes it)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

// One library of the analysis, as LibraryResolver decided it is processed.
//   id: the library id (artifact uei); the key the library's records are joined on, and the id of its module records.
//   analysis_id: the id of the analysis-level records; position: 0-based position in the manifest, the order libraries are merged
//   mmc_model: the MapMyCells model, or null for none
//   dge, cell_metadata: gs:// or local paths as text; mmc_annotations: the MapMyCells result csv path as text, or null for none
//   args, files: the join_and_filter_tsv arguments of the manifest entry, and the files they refer to ([] for none)
record Library {
    id: String
    analysis_id: String
    position: Integer
    mmc_model: String?
    dge: String
    cell_metadata: String
    mmc_annotations: String?
    args: List<String>
    files: List<String>
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

// The libraries of a resolver result (LibraryResolver.resolve) as Library records, in the order of the result (manifest order).
// A function with a declared result type, so that the joins on the libraries are type checked.
def toLibraries(result: Map) -> Iterable<Library> {
    return result.libraries.keySet().collect { library_id ->
        def library = result.libraries[library_id]
        record(
            id: library_id,
            analysis_id: result.analysisId,
            position: library.position,
            mmc_model: library.mmcModel == LibraryResolver.NA ? null : library.mmcModel,
            dge: library.dge,
            cell_metadata: library.cellMetadata,
            mmc_annotations: library.mmcAnnotations == LibraryResolver.NA ? null : library.mmcAnnotations,
            args: library.args,
            files: library.files
        )
    }
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow SCRNA_AGGREGATION {

    take:
    manifest: Value<Manifest>      // one item: the aggregation YAML
    entries: Value<List<Map>>      // one item: the manifest entries [dge, donor, filters, joins], in manifest order
    mmc_model: String?             // --mmc_model, the MapMyCells model that replaces each library's first model

    main:

    // Input: manifest, one item. Emits: LOCATE_SCRNA_ARTIFACTS result, one item, record(id: analysis id, artifacts: a directory with one <uei>.yaml per DGE).
    located = LOCATE_SCRNA_ARTIFACTS(manifest)

    // Input: located (one item) and entries (one item, appended as a field so that nothing is flattened) and the optional --mmc_model.
    // LibraryResolver.resolve matches each manifest entry with the artifacts of its library and decides what each library is processed from
    // (see lib/LibraryResolver.groovy).
    // Emits: one item, the resolver result Map [analysisId, libraries: [library id -> library Map], reducedGtf, reference, hasDonors]. A resolver error stops the run.
    resolved = located
        .combine(entries: entries)
        .map { item ->
            try {
                def artifacts = LibraryResolver.readArtifactTexts(item.artifacts).collect { text -> LibraryResolver.loadArtifact(text) }
                LibraryResolver.resolve(item.entries, artifacts, item.id, [ mmcModel: mmc_model ])
            } catch (IllegalArgumentException e) {
                error("Cannot resolve the libraries of ${item.id}: ${e.getMessage()}")
                [:]   // not reached: error() stops the run; keeps the closure result a Map
            }
        }

    // Input: the resolver result, one item.
    // Emits: <analysis>.resolved_libraries.txt, plain text for a person to read: the files and arguments each library is processed with.
    // Published to <outdir>/pipeline_info/ (conf/modules.config); nothing reads it back.
    resolved_summary = WRITE_RESOLVED_SUMMARY(resolved.map { result ->
        record(name: "${result.analysisId}.resolved_libraries.txt", text: LibraryResolver.summaryText(result))
    })

    // Input: the resolver result, one item.
    // Emits: one item per library (scatter), Library; position is the position in the manifest (the order in which libraries are merged).
    libraries = resolved.flatMap { result -> toLibraries(result) }

    // Input: libraries. Emits: one item per library, record(id: library id, analysis_id, position): what the per-library results are joined
    // with (by id) to be put in manifest order and named after the analysis.
    library_order = libraries.map { library -> record(id: library.id, analysis_id: library.analysis_id, position: library.position) }

    // Input: libraries (Library), each combined with the artifacts directory of located (one item), where each library's YAML is <library id>.yaml
    // (the library id is the artifact uei; the resolver has already read every YAML).
    // Emits: one item per library, record(id: library id, artifacts_yaml: path); each library gets its own YAML.
    library_artifacts = libraries
        .combine(artifacts: located.map { item -> item.artifacts })
        .map { item -> record(id: item.id, artifacts_yaml: item.artifacts.resolve("${item.id}.yaml")) }

    // Input: record(id: library id, artifacts_yaml), one item per library.
    // Emits: SUMMARIZE_SCRNA_EXPERIMENTS result, one item per library, record(id: library id, metrics: path (one row), tearsheet: path); the tearsheet is published.
    summaries = SUMMARIZE_SCRNA_EXPERIMENTS(library_artifacts)

    // Input: summaries joined with library_order on id, one item per library. Emits: one item, record(id: analysis id, tsvs: the metrics files in manifest order).
    metrics_sorted = summaries
        .join(library_order, by: 'id')
        .collect()
        .map { items ->
            def sorted = items.toSorted { a, b -> a.position <=> b.position }
            record(id: sorted[0].analysis_id, tsvs: sorted.collect { item -> item.metrics }.toList())
        }

    // Input: one item, record(id: analysis id, tsvs). Emits: MERGE_LIBRARY_METRICS result, one item, record(id: analysis id, combined: path('<analysis>.library_metrics.txt')).
    merged_metrics = MERGE_LIBRARY_METRICS(metrics_sorted)

    // Input: libraries, filtered to the libraries that have MapMyCells results (mmc_annotations not null).
    // Emits: one item per such library, record(id: library id, csv: path(MapMyCells result csv), mmc_model); the csv is localized from its gs:// path.
    mmc_csv = libraries
        .filter { library -> library.mmc_annotations }
        .map { library -> record(id: library.id, csv: file(library.mmc_annotations), mmc_model: library.mmc_model) }

    // Input: record(id: library id, csv, mmc_model), one item per library with MapMyCells results.
    // Emits: FORMAT_MAPMYCELLS_ANNOTATIONS result, one item per such library, record(id: library id, converted: path (not published), cell_type_column: String).
    annotations = FORMAT_MAPMYCELLS_ANNOTATIONS(mmc_csv)

    // Input: annotations, one item per library with results.
    // Emits: one item (value), String: the cell type column shared by all libraries, or '' if no library has MapMyCells results;
    // LibraryResolver.checkCellTypeColumn fails the run if the libraries disagree.
    cell_type_column = annotations
        .collect()
        .map { items -> LibraryResolver.checkCellTypeColumn(items.collect { item -> item.id }.toList(), items.collect { item -> item.cell_type_column }.toList()) ?: '' }

    // Input: libraries (all), joined on id with the MapMyCells TSV of the libraries with results; remainder: true keeps the libraries without.
    // Emits: one item per library, Library plus mmc_tsv (path, or null for a library without MapMyCells results).
    libraries_with_mmc = libraries.join(annotations.map { item -> record(id: item.id, mmc_tsv: item.converted) }, by: 'id', remainder: true)

    // Input: libraries_with_mmc, one item per library.
    // Emits: one item per library, record(id: library id, cell_metadata: path, mmc_tsv: path or null, args: the join_and_filter_tsv arguments
    // ([] for none; the task writes them to <library>.join_and_filter_args.txt), extra_files: list of paths, [] for none):
    // the exact input of BUILD_LIBRARY_CELL_METADATA.
    build_input = libraries_with_mmc
        .map { item ->
            record(
                id: item.id,
                cell_metadata: file(item.cell_metadata),
                mmc_tsv: item.mmc_tsv,
                args: item.args,
                extra_files: item.files.collect { f -> file(f) }.toList()
            )
        }

    // Input: build_input. Emits: BUILD_LIBRARY_CELL_METADATA result, one item per library, record(id: library id, cell_metadata: path('<library>.joined_filtered_cell_metadata.txt')).
    built = BUILD_LIBRARY_CELL_METADATA(build_input)

    // Input: built (one item per library) joined on id with libraries, for the analysis id, the position and the DGE each library is processed from
    // (the DGE the manifest names, localized from its gs:// path).
    // Emits: ONE list with one record per library, in manifest order (position): record(id, analysis_id, position, cell_metadata: path, dge: path).
    // Both the merged cell metadata and the sparse DGE are made from this one list, so the rows of the merged metadata and the columns of the
    // matrix are in the same library order, and the i-th prefix, DGE and barcode list always belong to the same library.
    built_sorted = built
        .join(libraries.map { library -> record(id: library.id, analysis_id: library.analysis_id, position: library.position, dge: file(library.dge)) }, by: 'id')
        .collect()
        .map { items -> items.toSorted { a, b -> a.position <=> b.position } }

    // Input: built_sorted. Emits: one item, record(id: analysis id, tsvs: the per-library cell metadata files, in manifest order).
    cell_metadata_files = built_sorted.map { items ->
        record(id: items[0].analysis_id, tsvs: items.collect { item -> item.cell_metadata }.toList())
    }

    // Input: one item, record(id: analysis id, tsvs). Emits: MERGE_CELL_METADATA result, one item, record(id: analysis id, combined: path('<analysis>.cell_metadata.txt')),
    // indexed by (PREFIX, cell_barcode): a duplicate cell fails the task (ext.args and ext.prefix in conf/modules.config).
    merged_cell_metadata = MERGE_CELL_METADATA(cell_metadata_files)

    // Input: built_sorted. Emits: one item, record(id: analysis id, prefixes: library ids, dges: paths, barcode_lists: paths), each list in manifest order.
    // dges and barcode_lists must be List<Path> fields of the input record itself: Nextflow stages the files of Path fields (and lists of them)
    // only, not paths nested in records inside a list, so one list of record(prefix, dge, barcode_list) would reach the task unstaged.
    triplet_input = built_sorted.map { items ->
        record(
            id: items[0].analysis_id,
            prefixes: items.collect { item -> item.id }.toList(),
            dges: items.collect { item -> item.dge }.toList(),
            barcode_lists: items.collect { item -> item.cell_metadata }.toList()
        )
    }

    // Input: the resolver result, one item. Emits: one item (value), path(reduced GTF), localized from its gs:// path; every library has the same one.
    reduced_gtf = resolved.map { result -> file(result.reducedGtf) }

    // Input: triplet_input and reduced_gtf, one item each.
    // Emits: MAKE_TRIPLET_DGE result, one item, record(id: analysis id, matrix, barcodes, features): genes x the cells of all libraries (barcodes are
    // <library id>_<cell barcode>), in library order.
    triplet = MAKE_TRIPLET_DGE(triplet_input, reduced_gtf)

    // The donor steps need donors, which the resolver knows from the manifest and the artifacts (all libraries have donors or none do), and the
    // cell type steps also need a cell type column (some library has MapMyCells results). A missing piece skips the steps with a warning.
    resolved.subscribe { result ->
        if (!result.hasDonors) {
            log.warn "The libraries of ${result.analysisId} have no donors (no donor in the manifest, no village in the artifacts): no donor reports or metacells"
        }
    }
    cell_type_column.subscribe { column ->
        if (!column) {
            log.warn "No library has MapMyCells results: no donor by cell type report or metacells"
        }
    }

    // Input: triplet (one item), merged_cell_metadata (one item) and the resolver result (donors yes or no).
    // Emits: one item only with donors, record(id: analysis id, matrix, features, barcodes, cell_metadata: path(merged cell metadata), has_donors).
    // A process takes a record with more fields than it declares, so these items go to the donor steps with only the fields they lack added.
    metacell_inputs = triplet
        .combine(cell_metadata: merged_cell_metadata.map { item -> item.combined })
        .combine(has_donors: resolved.map { result -> result.hasDonors })
        .flatMap { item -> item.has_donors ? [ item ] : [] }

    // Input: metacell_inputs (one item, only with donors) plus group_columns.
    // Emits: DONOR_METACELLS result, one item, record(id: analysis id, metacells: path('<analysis>.donors.metacells.txt.gz')): expression summed per donor.
    donor_metacells = DONOR_METACELLS(metacell_inputs.combine(group_columns: [ 'donor' ]))

    // Input: metacell_inputs and cell_type_column. Emits: one item only with donors and a cell type column, the metacell_inputs item plus cell_type_column.
    cell_type_inputs = metacell_inputs
        .combine(cell_type_column: cell_type_column)
        .flatMap { item -> item.cell_type_column ? [ item ] : [] }

    // Input: cell_type_inputs plus group_columns.
    // Emits: DONOR_CELL_TYPE_METACELLS result, one item, record(id: analysis id, metacells: path('<analysis>.donor_cell_type.metacells.txt.gz')): expression
    // summed per donor and cell type.
    donor_cell_type_metacells = DONOR_CELL_TYPE_METACELLS(cell_type_inputs.map { item -> item + record(group_columns: [ 'donor', item.cell_type_column ]) })

    // Input: cell_type_inputs (it has the cell_metadata and cell_type_column fields the report takes).
    // Emits: DONOR_CELL_TYPE_REPORT result, one item, record(id: analysis id, report: path('<analysis>.donor_cell_type.txt')): the cells and median UMIs
    // per donor and cell type.
    donor_cell_type_report = DONOR_CELL_TYPE_REPORT(cell_type_inputs)

    // Emits: pipeline_info/scrna-aggregation_software_versions.yml: the pipeline and Nextflow versions. The tool versions are the image tags
    // hard coded in the modules, so no process reports a version.
    versions_file = WRITE_VERSIONS(channel.value(record(name: 'scrna-aggregation_software_versions.yml', text: workflowVersionToYAML().trim() + '\n')))

    // What the pipeline publishes: the entry workflow's `publish:` section and the `output` block in main.nf say where each goes.
    // Input: the process results above. Emits: one channel of paths per published file (the merged results and pipeline_info files, one item each; the
    // artifacts directory and the tearsheets, one per library or one directory).
    emit:
    artifacts: Value<Path> = located.map { item -> item.artifacts }
    tearsheets: Channel<Path> = summaries.map { item -> item.tearsheet }
    library_metrics: Value<Path> = merged_metrics.map { item -> item.combined }
    cell_metadata: Value<Path> = merged_cell_metadata.map { item -> item.combined }
    matrix: Value<Path> = triplet.map { item -> item.matrix }
    barcodes: Value<Path> = triplet.map { item -> item.barcodes }
    features: Value<Path> = triplet.map { item -> item.features }
    donor_cell_type_report: Channel<Path> = donor_cell_type_report.map { item -> item.report }
    donor_metacells: Channel<Path> = donor_metacells.map { item -> item.metacells }
    donor_cell_type_metacells: Channel<Path> = donor_cell_type_metacells.map { item -> item.metacells }
    resolved_summary: Value<Path> = resolved_summary
    versions_file: Value<Path> = versions_file
}
