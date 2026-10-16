/**
 * Builds the arguments of join_and_filter_tsv (the donor, joins and filters of one manifest entry) and the list of
 * files they refer to.  The arguments go in a per-library arguments file, one argument per line, that the tool reads
 * with --args-file, so no shell quoting is needed.  Pure Groovy, unit tested directly (see
 * subworkflows/local/utils_nfcore_scrna-aggregation_pipeline/tests/arguments.function.nf.test).
 *
 * The arguments, their order and their text are those of dropseq's resolve_aggregation_manifest (join_and_filter_args,
 * plus --set donor first), except that the paths of files are the names the files have once Nextflow has staged them
 * in the task directory.  Values are written with toString, as the original Zamboni workflow does.
 */
class JoinFilterArguments {

    /**
     * @param entry one entry of AggregationManifest.parse
     * @return [args: List of String, files: List of the original paths to stage, each once, in order of use].
     *   args order: --set donor, the joins in manifest order, then for each filter column in manifest order:
     *   includeFile, excludeFile, include, exclude, min, max.  The order of the filters does not change the result
     *   (they are all applied), but the order of the joins does.
     * @throws IllegalArgumentException if two different paths would be staged under the same name
     */
    static Map build(Map entry) {
        List<String> args = []
        List<String> files = []
        Map<String, String> pathByStagedName = [:]
        String where = "dge ${entry.dge}"

        // stages a path (once) and returns the name of the staged file
        Closure stage = { String path ->
            String name = stagedName(path, where)
            String other = pathByStagedName[name]
            if (other == null) {
                pathByStagedName[name] = path
                files << path
            } else if (other != path) {
                throw new IllegalArgumentException(
                    "${where}: the files ${other} and ${path} would both be staged as '${name}'.  Rename one of them, for example by copying it.")
            }
            return name
        }

        if (entry.donor != null) {
            args += ['--set', 'donor', entry.donor.toString()]
        }
        entry.joins.each { Map join ->
            args += ['--join', stage(join.joinFile), join.leftColumn, join.joinColumn]
        }
        entry.filters.each { String column, Map spec ->
            if (spec.containsKey('includeFile')) {
                args += ['--include-file', column, stage(spec.includeFile)]
            }
            if (spec.containsKey('excludeFile')) {
                args += ['--exclude-file', column, stage(spec.excludeFile)]
            }
            // an empty list filters nothing, and the tool needs at least one value
            if (spec.include) {
                args += ['--include', column] + spec.include.collect { it.toString() }
            }
            if (spec.exclude) {
                args += ['--exclude', column] + spec.exclude.collect { it.toString() }
            }
            if (spec.containsKey('min')) {
                args += ['--min', column, spec.min.toString()]
            }
            if (spec.containsKey('max')) {
                args += ['--max', column, spec.max.toString()]
            }
        }
        return [args: args, files: files]
    }

    /** @return the content of the arguments file: one argument per line; an empty file for no arguments */
    static String toArgsFileText(List<String> args) {
        return args.collect { it + '\n' }.join('')
    }

    /** @return the name of the file once staged: the part of the path after the last slash (local path or URL) */
    static String stagedName(String path, String where) {
        String name = path.substring(path.lastIndexOf('/') + 1)
        if (name.isEmpty()) {
            throw new IllegalArgumentException("${where}: '${path}' has no file name, so it cannot be staged")
        }
        return name
    }
}
