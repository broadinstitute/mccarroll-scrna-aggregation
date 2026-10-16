import org.yaml.snakeyaml.LoaderOptions
import org.yaml.snakeyaml.Yaml
import org.yaml.snakeyaml.constructor.SafeConstructor
import org.yaml.snakeyaml.error.YAMLException

/**
 * Parses and validates the aggregation manifest (YAML), the same schema as the manifest of the original Zamboni
 * scRNA aggregation workflow (ScRnaAggregationManifestKey), except that libraryId is not supported (the library ID is
 * the UEI of the library's artifacts) and the list form of filters is not accepted:
 *
 *   dgeDefaults:             # optional; only filters and joins; projected onto each dge (see projectDefaults)
 *     filters: ...
 *   dges:                    # a list, or a single dictionary
 *     - dge: gs://.../<uei>.donors.digital_expression.txt.gz    # required
 *       donor: N1                                               # optional
 *       filters:                                                # optional, keyed by cell metadata column
 *         doublet: {exclude: doublet}
 *         pct_mt: {max: 0.1}    # includeFile, excludeFile, include, exclude, min and max are allowed
 *       joins:                                                  # optional, a list or a single dictionary
 *         - {joinFile: extra.tsv, leftColumn: cell_barcode, joinColumn: cell}
 *
 * Pure Groovy with no Nextflow dependency, so that it can be unit tested directly (see
 * subworkflows/local/utils_nfcore_scrna-aggregation_pipeline/tests/manifest.function.nf.test).
 * Every error is an IllegalArgumentException with an actionable message.
 */
class AggregationManifest {

    static final List<String> ROOT_KEYS = ['dges', 'dgeDefaults']
    static final List<String> DGE_KEYS = ['dge', 'donor', 'filters', 'joins']
    static final List<String> DEFAULT_KEYS = ['filters', 'joins']
    static final List<String> FILTER_KEYS = ['includeFile', 'excludeFile', 'include', 'exclude', 'min', 'max']
    static final List<String> JOIN_KEYS = ['joinFile', 'leftColumn', 'joinColumn']

    /**
     * @param yamlText the manifest
     * @return one map per dge, in manifest order, with dgeDefaults projected onto it:
     *   [dge: String, donor: scalar or null, filters: Map of column to spec, joins: List of [joinFile, leftColumn, joinColumn]].
     *   A spec has only the keys that are set: includeFile and excludeFile (String), include and exclude (List of
     *   scalars, the YAML types are kept), min and max (Number).
     */
    static List<Map> parse(String yamlText) {
        Object root = load(yamlText)
        if (!(root instanceof Map)) {
            throw bad("The manifest must be a YAML dictionary with a 'dges' key")
        }
        checkKeys((Map) root, ROOT_KEYS, 'the manifest')
        if (!root.containsKey('dges')) {
            throw bad("The manifest has no 'dges' key")
        }

        Map defaults = [:]
        if (root.dgeDefaults != null) {
            if (!(root.dgeDefaults instanceof Map)) {
                throw bad('dgeDefaults must be a dictionary')
            }
            defaults = (Map) root.dgeDefaults
            checkKeys(defaults, DEFAULT_KEYS, 'dgeDefaults')
            // only to report an error in the defaults as one in dgeDefaults, not in the first dge that uses them
            normalizeFilters(defaults.filters, 'dgeDefaults')
            normalizeJoins(defaults.joins, 'dgeDefaults')
        }

        List rawEntries = root.dges instanceof Map ? [root.dges] : (root.dges instanceof List ? (List) root.dges : null)
        if (rawEntries == null || rawEntries.isEmpty()) {
            throw bad("At least one DGE must be specified in 'dges'")
        }

        List<Map> entries = []
        rawEntries.eachWithIndex { Object raw, int i ->
            String where = "dge entry ${i + 1}"
            if (!(raw instanceof Map)) {
                throw bad("${where} must be a dictionary, not ${raw}")
            }
            Map rawEntry = (Map) raw
            if (rawEntry.containsKey('dge') && isScalar(rawEntry.dge)) {
                where = "${where} (${rawEntry.dge})"
            }
            if (rawEntry.containsKey('libraryId')) {
                throw bad("${where}: 'libraryId' is not supported; the library ID is taken from the artifacts of the DGE")
            }
            checkKeys(rawEntry, DGE_KEYS, where)
            if (!rawEntry.containsKey('dge')) {
                throw bad("${where} has no 'dge' key")
            }
            Map projected = (Map) project(rawEntry, defaults)
            entries << normalizeEntry(projected, where)
        }

        // the same DGE twice would be the same library twice
        entries.eachWithIndex { Map entry, int i ->
            int first = entries.findIndexOf { it.dge == entry.dge }
            if (first != i) {
                throw bad("DGE ${entry.dge} is listed more than once (dge entries ${first + 1} and ${i + 1})")
            }
        }
        return entries
    }

    private static Object load(String yamlText) {
        LoaderOptions options = new LoaderOptions()
        // a repeated key would silently drop the earlier value, for example a whole list of filters
        options.setAllowDuplicateKeys(false)
        try {
            return new Yaml(new SafeConstructor(options)).load(yamlText)
        } catch (YAMLException e) {
            throw bad("The manifest is not valid YAML: ${e.message}")
        }
    }

    /**
     * Applies the defaults to target as the original workflow does (YamlManifestUtil.projectDefaults): a key of the
     * defaults that the target does not have is copied; where both are dictionaries they are merged recursively (so
     * the filters of one column merge key by key, and the target's value wins); where the default is a dictionary and
     * the target a list, each dictionary of the list gets the defaults.  A default list (joins) is used only when the
     * target has no value for the key; it is never appended to the target's.
     */
    private static Object project(Object target, Map defaults) {
        if (target instanceof List) {
            return ((List) target).collect { project(it, defaults) }
        }
        if (!(target instanceof Map)) {
            return target
        }
        Map result = new LinkedHashMap((Map) target)
        defaults.each { key, value ->
            if (!result.containsKey(key)) {
                result[key] = deepCopy(value)
            } else if (value instanceof Map) {
                Object current = result[key]
                if (current instanceof List) {
                    result[key] = ((List) current).collect { it instanceof Map ? project(it, (Map) value) : it }
                } else if (current instanceof Map) {
                    result[key] = project(current, (Map) value)
                }
            }
        }
        return result
    }

    private static Object deepCopy(Object value) {
        if (value instanceof Map) {
            Map copy = new LinkedHashMap()
            ((Map) value).each { k, v -> copy[k] = deepCopy(v) }
            return copy
        }
        if (value instanceof List) {
            return ((List) value).collect { deepCopy(it) }
        }
        return value
    }

    private static Map normalizeEntry(Map entry, String where) {
        checkText('dge', entry.dge, where)
        if (!isScalar(entry.dge) || entry.dge.toString().trim().isEmpty()) {
            throw bad("${where}: 'dge' must be a path or URL")
        }
        Object donor = entry.donor
        if (donor != null && !isScalar(donor)) {
            throw bad("${where}: 'donor' must be a single value, not ${donor}")
        }
        checkText('donor', donor, where)
        return [dge: entry.dge.toString(), donor: donor, filters: normalizeFilters(entry.filters, where),
                joins: normalizeJoins(entry.joins, where)]
    }

    private static Map<String, Map> normalizeFilters(Object filters, String where) {
        Map<String, Map> result = new LinkedHashMap<>()
        if (filters == null) {
            return result
        }
        if (!(filters instanceof Map)) {
            throw bad("${where}: 'filters' must be a dictionary keyed by column, not ${filters}")
        }
        ((Map) filters).each { column, spec ->
            String name = column.toString()
            String filterWhere = "${where}: filter on ${name}"
            checkText('column', name, filterWhere)
            if (!(spec instanceof Map)) {
                throw bad("${filterWhere} must be a dictionary, not ${spec}")
            }
            checkKeys((Map) spec, FILTER_KEYS, filterWhere)
            Map normalized = new LinkedHashMap()
            ['includeFile', 'excludeFile'].each { String key ->
                if (spec.containsKey(key)) {
                    if (!isScalar(spec[key])) {
                        throw bad("${filterWhere}: '${key}' must be a single path, not ${spec[key]}")
                    }
                    checkText(key, spec[key], filterWhere)
                    normalized[key] = spec[key].toString()
                }
            }
            ['include', 'exclude'].each { String key ->
                if (spec.containsKey(key)) {
                    Object raw = spec[key]
                    List values = raw instanceof List ? (List) raw : [raw]
                    if (!values.every { isScalar(it) }) {
                        throw bad("${filterWhere}: '${key}' must be a value or a list of values, not ${raw}")
                    }
                    values.each { checkText(key, it, filterWhere) }
                    normalized[key] = new ArrayList(values)
                }
            }
            ['min', 'max'].each { String key ->
                if (spec.containsKey(key)) {
                    if (!(spec[key] instanceof Number)) {
                        throw bad("${filterWhere}: '${key}' must be a number, not ${spec[key]}")
                    }
                    normalized[key] = spec[key]
                }
            }
            result[name] = normalized
        }
        return result
    }

    private static List<Map> normalizeJoins(Object joins, String where) {
        if (joins == null) {
            return []
        }
        List rawJoins = joins instanceof List ? (List) joins : [joins]
        List<Map> result = []
        rawJoins.eachWithIndex { Object raw, int i ->
            String joinWhere = "${where}: join ${i + 1}"
            if (!(raw instanceof Map)) {
                throw bad("${joinWhere} must be a dictionary, not ${raw}")
            }
            checkKeys((Map) raw, JOIN_KEYS, joinWhere)
            Map join = new LinkedHashMap()
            JOIN_KEYS.each { String key ->
                if (!raw.containsKey(key) || !isScalar(raw[key]) || raw[key].toString().isEmpty()) {
                    throw bad("${joinWhere} needs a value for ${key} (all of ${JOIN_KEYS} are required)")
                }
                checkText(key, raw[key], joinWhere)
                join[key] = raw[key].toString()
            }
            result << join
        }
        return result
    }

    private static boolean isScalar(Object value) {
        value != null && !(value instanceof Map) && !(value instanceof Collection)
    }

    private static void checkKeys(Map map, List<String> allowed, String where) {
        map.keySet().each { key ->
            if (!allowed.contains(key.toString())) {
                throw bad("Unexpected key '${key}' in ${where}.  Allowed: ${allowed}")
            }
        }
    }

    /** Each value becomes one line of the arguments file of the tool, so it cannot contain a line break. */
    private static void checkText(String what, Object value, String where) {
        if (value != null && value.toString().contains('\n')) {
            throw bad("${where}: ${what} contains a line break, which cannot be written to the one-argument-per-line arguments file")
        }
    }

    private static IllegalArgumentException bad(String message) {
        new IllegalArgumentException(message)
    }
}
