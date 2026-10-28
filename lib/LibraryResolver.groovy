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
     * @param options [mmcModel:
     *   MapMyCells model to use instead of the first model of each library]; either may be null or absent
     * @return [analysisId; hasDonors (all libraries have donors; a mix is an error); donorFiles (the distinct donor_file paths of the artifacts in manifest order, so libraries of one village give one entry; empty if any library has none; compared by content later, by the QC tool); libraries: Map of library id to record, in manifest order; reducedGtf; reference].  A record is
     *   [libraryId, position (0-based, in manifest order), hasDonor, dge, cellMetadata, mmcModel, mmcAnnotations, args, files]: the DGE is the one the manifest names; the arguments
     *   and files are those of JoinFilterArguments.build.  mmcAnnotations is the csv of the model, or NA, and gates the MapMyCells conversion.
     */
    static Map resolve(Iterable<Map> entries, Iterable<Map> artifacts, String analysisId, Map options = [:]) {
        String mmcModel = options.mmcModel

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
        List<String> donorOnVillage = []
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

            // The DGE of the library is the one the manifest names (of any type: donors, selected cells ...), which is the artifact's user_dge.
            // The other DGEs the artifacts list are not used: the cell metadata selects the cells of the DGE later.
            String dge = entry.dge
            String cellMetadata = value(dataset.cell_metadata)
            if (cellMetadata == NA) {
                throw new IllegalArgumentException("${id} has no cell metadata in its artifacts")
            }

            Map mmc = dataset.mmc instanceof Map ? (Map) dataset.mmc : [:]
            String model = mmcModel ?: (mmc.isEmpty() ? NA : mmc.keySet().first().toString())
            String annotations = mmc[model] instanceof Map ? value(((Map) mmc[model]).mmc_annotations) : NA

            // A library has donors if the manifest names its donor (a library that is not a village) or its artifacts have a village stage
            // (donor assignment, whose cell metadata holds the donor of each cell). Known here, so nothing needs to look in the files later.
            boolean hasDonor = entry.donor != null || value(dataset.village_properties) != NA
            // The cell metadata of a village has the donor of each cell. That is trusted data: a donor in the manifest must not replace it
            // (join_and_filter_tsv refuses to --set a column that its input has), so it is rejected here, before any process runs.
            if (entry.donor != null && value(dataset.village_properties) != NA) {
                donorOnVillage << "${id} (DGE ${entry.dge})".toString()
            }

            Map built = JoinFilterArguments.build(entry)
            checkStagedNames(id, cellMetadata, built.files)
            libraries[id] = [libraryId: id, position: libraries.size(), hasDonor: hasDonor, dge: dge, cellMetadata: cellMetadata, mmcModel: model, mmcAnnotations: annotations,
                             args: built.args, files: built.files, reducedGtf: value(dataset.reduced_gtf), donorFile: value(dataset.donor_file)]
        }

        if (donorOnVillage) {
            throw new IllegalArgumentException(
                "A donor in the manifest cannot be given to a library that is a village: its cell metadata already has the donor of each cell, " +
                "and the manifest does not replace it.  Remove donor from the manifest entries of: ${donorOnVillage.join(', ')}.")
        }
        if (libraryIds.toSet().size() != libraryIds.size()) {
            throw new IllegalArgumentException("Library IDs must be unique, found ${libraryIds}")
        }
        if (libraryIds.contains(analysisId)) {
            throw new IllegalArgumentException("A library ID cannot be the same as the analysis identifier: ${analysisId}")
        }

        if (idsByReference.size() > 1) {
            throw new IllegalArgumentException("All DGEs must have the same reference.  Found ${idsByReference}.")
        }
        String reference = idsByReference.keySet().first()

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

        // The libraries are merged into one cell metadata table and one matrix, so they must all have donors or none of them.
        List<String> withDonors = libraries.values().findAll { it.hasDonor }*.libraryId
        List<String> withoutDonors = libraries.values().findAll { !it.hasDonor }*.libraryId
        if (withDonors && withoutDonors) {
            throw new IllegalArgumentException(
                "Either all libraries have donors or none do.  With donors (a donor in the manifest or a village in the artifacts): ${withDonors}.  " +
                "Without: ${withoutDonors}.")
        }

        // The expected donors of the QC: the donor files of the libraries, none at all if any library has none (a partial list would give a wrong set of donors).
        // Different paths may have one base name: the QC process stages each file under a unique name and the tool compares the contents.
        List<String> donorFiles = libraries.values()*.donorFile.every { it != NA } ? libraries.values()*.donorFile.unique() : []

        libraries.values().each { it.remove('reducedGtf'); it.remove('donorFile') }
        return [analysisId: analysisId, hasDonors: !withDonors.isEmpty(), donorFiles: donorFiles, libraries: libraries, reducedGtf: gtfs.first(), reference: reference]
    }

    /**
     * Resolves the donor files of the libraries (resolve's donorFiles) to the one file the QC needs: the first, if every file has the same set of
     * donors (compared by content: one donor per line, order, blank lines, a final newline and CRLF line endings do not matter), else null (no donor QC).
     * Reads the files, so call it only when the QC runs.
     * @param paths the donor file paths, in manifest order
     * @param read a closure returning the text of a path (a local or gs:// file)
     * @return the first path, or null if there are none or the sets of donors differ
     */
    static String commonDonorFile(List<String> paths, Closure<String> read) {
        if (paths.isEmpty()) {
            return null
        }
        List<Set<String>> sets = paths.collect { String path ->
            read(path).readLines().collect { it.trim() }.findAll { !it.isEmpty() }.toSet()
        }
        return sets.every { it == sets.first() } ? paths.first() : null
    }

    /** @return the name of the arguments file of a library */
    static String argsFileName(String libraryId) {
        return "${libraryId}.join_and_filter_args.txt"
    }

    /**
     * @return the resolved libraries as plain text for a person to read (it is never parsed back): the run's reference and reduced GTF, then
     *   for each library, in manifest order, the files it will be processed from and the arguments it is filtered with
     */
    static String summaryText(Map result) {
        String indent = ' ' * 17
        List<String> lines = [
            "Aggregation ${result.analysisId}",
            "Reference:   ${result.reference}",
            "Reduced GTF: ${result.reducedGtf}",
            "Donors:      ${result.hasDonors ? 'yes' : 'no'}"
        ]
        result.libraries.each { String id, Map lib ->
            lines << ''
            lines << "Library ${id}"
            lines << "  DGE:           ${lib.dge}"
            lines << "  Cell metadata: ${lib.cellMetadata}"
            lines << (lib.mmcAnnotations == NA ?
                "  MapMyCells:    none" : "  MapMyCells:    model ${lib.mmcModel}, annotations ${lib.mmcAnnotations}")
            lines << "  Extra files:   ${lib.files ? lib.files.join('\n' + indent) : 'none'}"
            lines << "  join_and_filter_tsv arguments (one per line, as in ${argsFileName(id)}):"
            lines << (lib.args ? lib.args.collect { indent + it }.join('\n') : indent + 'none')
        }
        return lines.collect { it + '\n' }.join('')
    }

    /**
     * @param columnByLibrary the cell type column name returned by FORMAT_MAPMYCELLS_ANNOTATIONS for each library that has MapMyCells results
     * @return the one column name they all share, or null if there are no such libraries
     * @throws IllegalArgumentException if the libraries have different columns (they are merged into one column)
     */
    static String checkCellTypeColumn(Map<String, String> columnByLibrary) {
        Set<String> columns = columnByLibrary.values().toSet()
        if (columns.size() > 1) {
            throw new IllegalArgumentException(
                "The libraries have different cell type columns: ${columnByLibrary}.  Set the mmc_level and mmc_model parameters so they agree.")
        }
        return columns ? columns.first() : null
    }

    /**
     * The same check for two parallel lists (typed workflows have no collectEntries on a list).
     * @param libraryIds the library ids that have MapMyCells results
     * @param columns the cell type column of each of those libraries, in the same order
     */
    static String checkCellTypeColumn(List<String> libraryIds, List<String> columns) {
        if (libraryIds.size() != columns.size()) {
            throw new IllegalArgumentException("Got ${libraryIds.size()} library ids and ${columns.size()} cell type columns: they must pair up")
        }
        return checkCellTypeColumn([libraryIds, columns].transpose().collectEntries { pair -> [(pair[0]): pair[1]] } as Map<String, String>)
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
