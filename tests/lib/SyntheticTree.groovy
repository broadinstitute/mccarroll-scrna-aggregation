/**
 * Helper for the workflow tests on the synthetic data (tests/fixtures/synthetic, see its README.md).
 * The tree holds the token @ROOT@ where an absolute path is needed (the reference in an alignment properties.yaml, the paths in the
 * manifests): materialize copies it to a directory and replaces the token with that directory's absolute path. The directory must be
 * mounted into the task containers at the same path (see tests/synthetic.config), so the paths mean the same in the containers and in the head job.
 */
class SyntheticTree {

    /** Copies the tree from source to target (made if needed) and replaces @ROOT@ in every text file. @return the absolute path of target */
    static String materialize(File source, File target) {
        target.mkdirs()
        String root = target.canonicalPath
        source.eachFileRecurse { File f ->
            if (f.isFile()) {
                File copy = new File(target, source.toPath().relativize(f.toPath()).toString())
                copy.parentFile.mkdirs()
                if (f.name.endsWith('.gz') || f.length() == 0) {
                    copy.bytes = f.bytes
                } else {
                    copy.text = f.text.replace('@ROOT@', root)
                }
            }
        }
        return root
    }
}
