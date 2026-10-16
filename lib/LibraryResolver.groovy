import org.yaml.snakeyaml.LoaderOptions
import org.yaml.snakeyaml.Yaml
import org.yaml.snakeyaml.constructor.SafeConstructor
import org.yaml.snakeyaml.error.YAMLException

/**
 * Resolves the libraries of an aggregation: matches each manifest entry with the artifact file of its library (written
 * by LOCATE_SCRNA_ARTIFACTS), and decides the files and arguments of each library.  Replaces dropseq's
 * resolve_aggregation_manifest.  Pure Groovy, unit tested directly (see
 * subworkflows/local/utils_nfcore_scrna-aggregation_pipeline/tests/resolver.function.nf.test).
 *
 * An artifact file is the parsed YAML of one library: [datasets: [[uei: ..., user_dge: ..., ...]]].  Missing values in
 * it are the string 'NA'.  Every error is an IllegalArgumentException with an actionable message.
 */
class LibraryResolver {

    static final String NA = 'NA'

    /** @return the text of each <uei>.yaml of an artifacts directory (LOCATE_SCRNA_ARTIFACTS), in file name order; a local or remote directory */
    static List<String> readArtifactTexts(java.nio.file.Path dir) {
        List<java.nio.file.Path> files = []
        java.nio.file.Files.newDirectoryStream(dir).withCloseable { stream -> stream.each { files << it } }
        return files.findAll { it.fileName.toString().endsWith('.yaml') }.sort { it.fileName.toString() }.collect { new String(java.nio.file.Files.readAllBytes(it), 'UTF-8') }
    }

    /** @return the artifact file of one library, parsed, after checking that it is usable (see checkArtifact) */
    static Map loadArtifact(String yamlText) {
        LoaderOptions options = new LoaderOptions()
        options.setAllowDuplicateKeys(false)
        Object root
        try {
            root = new Yaml(new SafeConstructor(options)).load(yamlText)
        } catch (YAMLException e) {
            throw new IllegalArgumentException("The artifact file is not valid YAML: ${e.message}")
        }
        checkArtifact(root)
        return (Map) root
    }

    /**
     * @param entries the manifest entries (AggregationManifest.parse), in manifest order
     * @param artifacts the artifact files (loadArtifact), in any order; those of DGEs not in the manifest are ignored
     * @param analysisId no library id may be the same
     * @param options [reference: reference name that skips the check that all libraries have the same one, mmcModel:
     *   MapMyCells model to use instead of the first model of each library]; either may be null or absent
     * @return [libraries: Map of library id to record, in manifest order; reducedGtf; reference].  A record is
     *   [libraryId, dge, cellMetadata, mmcModel, mmcAnnotations, args, files]: the donor DGE if the library has one,
     *   otherwise the selected-cells DGE; the arguments and files of JoinFilterArguments.build.  mmcAnnotations is
     *   the csv of the model, or NA, and gates the MapMyCells conversion.
     */
    static Map resolve(List<Map> entries, List<Map> artifacts, String analysisId, Map options = [:]) {
        String mmcModel = options.mmcModel
        String referenceOverride = options.reference

        Map<String, Map> datasetByDge = [:]
        artifacts.each { Map artifact ->
            Map dataset = checkArtifact(artifact)
            Map earlier = datasetByDge[dataset.user_dge]
            if (earlier != null) {
                throw new IllegalArgumentException(
                    "The DGE ${dataset.user_dge} is the user_dge of the artifacts of both ${earlier.uei} and ${dataset.uei}")
            }
            datasetByDge[dataset.user_dge] = dataset
        }

        Map<String, Map> libraries = new LinkedHashMap<>()
        Map<String, List<String>> idsByReference = [:]
        List<String> libraryIds = []
        entries.each { Map entry ->
            Map dataset = datasetByDge[entry.dge]
            if (dataset == null) {
                throw new IllegalArgumentException("No artifacts found for DGE ${entry.dge}.  Were they located by LOCATE_SCRNA_ARTIFACTS?")
            }
            String id = dataset.uei
            libraryIds << id

            String reference = value(dataset.reference)
            if (reference == NA) {
                reference = baseName(value(dataset.alignment_dir))
            }
            idsByReference.get(reference, []) << id

            String dge = value(dataset.dge_donors)
            if (dge == NA) {
                dge = value(dataset.dge_selected_cells)
            }
            if (dge == NA) {
                throw new IllegalArgumentException("${id} has no DGE (neither dge_donors nor dge_selected_cells in its artifacts)")
            }
            String cellMetadata = value(dataset.cell_metadata)
            if (cellMetadata == NA) {
                throw new IllegalArgumentException("${id} has no cell metadata in its artifacts")
            }

            Map mmc = dataset.mmc instanceof Map ? (Map) dataset.mmc : [:]
            String model = mmcModel ?: (mmc.isEmpty() ? NA : mmc.keySet().first().toString())
            String annotations = mmc[model] instanceof Map ? value(((Map) mmc[model]).mmc_annotations) : NA

            Map built = JoinFilterArguments.build(entry)
            checkStagedNames(id, cellMetadata, built.files)
            libraries[id] = [libraryId: id, dge: dge, cellMetadata: cellMetadata, mmcModel: model, mmcAnnotations: annotations,
                             args: built.args, files: built.files, reducedGtf: value(dataset.reduced_gtf)]
        }

        if (libraryIds.toSet().size() != libraryIds.size()) {
            throw new IllegalArgumentException("Library IDs must be unique, found ${libraryIds}")
        }
        if (libraryIds.contains(analysisId)) {
            throw new IllegalArgumentException("A library ID cannot be the same as the analysis identifier: ${analysisId}")
        }

        String reference = referenceOverride
        if (reference == null) {
            if (idsByReference.size() > 1) {
                throw new IllegalArgumentException(
                    "All DGEs must have the same reference.  Found ${idsByReference}.  Set the reference parameter to skip this check.")
            }
            reference = idsByReference.keySet().first()
        }

        List<String> noGtf = libraries.values().findAll { it.reducedGtf == NA }*.libraryId
        if (noGtf) {
            throw new IllegalArgumentException("No reduced GTF found in the artifacts of ${noGtf}")
        }
        List<String> gtfs = libraries.values()*.reducedGtf.unique()
        if (gtfs.size() > 1) {
            throw new IllegalArgumentException("All libraries must have the same reduced GTF.  Found ${gtfs}")
        }

        // The cell type columns of the libraries are named after the model, and are merged into one column: the libraries that have
        // MapMyCells results must have used the same model.
        Map<String, String> modelByLibrary = libraries.values().findAll { it.mmcAnnotations != NA }.collectEntries { [(it.libraryId): it.mmcModel] }
        if (modelByLibrary.values().toSet().size() > 1) {
            throw new IllegalArgumentException(
                "The libraries have MapMyCells results of different models: ${modelByLibrary}.  Set the mmc_model parameter to choose one.")
        }

        libraries.values().each { it.remove('reducedGtf') }
        return [libraries: libraries, reducedGtf: gtfs.first(), reference: reference]
    }

    /** @return the name of the arguments file of a library, which is also the name it is published under */
    static String argsFileName(String libraryId) {
        return "${libraryId}.join_and_filter_args.txt"
    }

    /**
     * @return the content of the resolved libraries summary, tab-separated with a header, one row per library; the staged
     *   files are separated by ';'
     */
    static String summaryText(Map result) {
        List<String> lines = [['library_id', 'dge', 'cell_metadata', 'mmc_model', 'mmc_annotations', 'reduced_gtf', 'args_file', 'files'].join('\t')]
        result.libraries.each { String id, Map lib ->
            lines << [id, lib.dge, lib.cellMetadata, lib.mmcModel, lib.mmcAnnotations, result.reducedGtf, argsFileName(id),
                      lib.files ? lib.files.join(';') : NA].join('\t')
        }
        return lines.collect { it + '\n' }.join('')
    }

    /** @return the one dataset of an artifact file, after checking that it has a uei and a user_dge */
    private static Map checkArtifact(Object artifact) {
        if (!(artifact instanceof Map) || !(((Map) artifact).datasets instanceof List)) {
            throw new IllegalArgumentException("An artifact file must have a top-level 'datasets' list")
        }
        List datasets = (List) ((Map) artifact).datasets
        if (datasets.size() != 1 || !(datasets[0] instanceof Map)) {
            throw new IllegalArgumentException("An artifact file must have exactly one dataset, found ${datasets.size()}")
        }
        Map dataset = (Map) datasets[0]
        if (value(dataset.uei) == NA) {
            throw new IllegalArgumentException("An artifact file has a dataset with no uei: ${dataset}")
        }
        if (value(dataset.user_dge) == NA) {
            throw new IllegalArgumentException("The artifacts of ${dataset.uei} have no user_dge.  Were they written by locate_scRNA_artifacts?")
        }
        return dataset
    }

    /** The files of the BUILD_LIBRARY_CELL_METADATA task directory of a library: a staged file must not have one of their names. */
    private static void checkStagedNames(String id, String cellMetadata, List<String> files) {
        Map<String, String> reserved = [
            (baseName(cellMetadata)): 'the cell metadata',
            ("${id}.mmc.tsv".toString()): 'the converted MapMyCells annotations',
            (argsFileName(id)): 'the arguments file',
            ("${id}.joined_filtered_cell_metadata.txt".toString()): 'the output'
        ]
        files.each { String path ->
            String name = JoinFilterArguments.stagedName(path, "library ${id}")
            if (reserved.containsKey(name)) {
                throw new IllegalArgumentException(
                    "Library ${id}: the file ${path} would be staged as '${name}', the name of ${reserved[name]} of the library.  Rename it, for example by copying it.")
            }
        }
    }

    private static String value(Object v) {
        v == null ? NA : v.toString()
    }

    private static String baseName(String path) {
        String trimmed = path.endsWith('/') ? path.substring(0, path.length() - 1) : path
        return trimmed.substring(trimmed.lastIndexOf('/') + 1)
    }
}
