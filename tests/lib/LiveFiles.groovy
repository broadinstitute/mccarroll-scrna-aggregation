import java.security.MessageDigest
import java.util.zip.GZIPInputStream

/** Helpers for the live tests, which compare generated files with the baseline (see docs/testing.md, "Live tests"). */
class LiveFiles {

    /**
     * md5 of the content of a file, streamed (the files can be large). A .gz file is decompressed first, because the gzip
     * header can differ between runs while the content is identical.
     */
    static String contentMd5(f) {
        def digest = MessageDigest.getInstance('MD5')
        def raw = new FileInputStream(f.toString())
        def stream = f.toString().endsWith('.gz') ? new GZIPInputStream(raw) : raw
        stream.withCloseable { s ->
            byte[] buffer = new byte[65536]
            int n
            while ((n = s.read(buffer)) != -1) {
                digest.update(buffer, 0, n)
            }
        }
        return digest.digest().encodeHex().toString()
    }

    /** True if both files have the same content (see contentMd5). The cheap check to make first; look at the lines only if it fails. */
    static boolean sameContent(a, b) {
        return contentMd5(a) == contentMd5(b)
    }

    /** Indexes (0-based) of the lines that differ, up to the longer of the two lists. */
    static List<Integer> differingLines(List generated, List baseline) {
        return (0..<Math.max(generated.size(), baseline.size())).findAll { i ->
            (i < generated.size() ? generated[i] : null) != (i < baseline.size() ? baseline[i] : null)
        }
    }

    /** Reads the lines of a text file, or of a .gz file. */
    static List<String> lines(f) {
        def raw = new FileInputStream(f.toString())
        def stream = f.toString().endsWith('.gz') ? new GZIPInputStream(raw) : raw
        return stream.withCloseable { s -> s.newReader().readLines() }
    }
}
