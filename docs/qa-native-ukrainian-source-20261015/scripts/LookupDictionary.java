import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.net.URL;
import morfologik.stemming.DictionaryLookup;

/** Bounded read-only lookup against the pinned artifact, not a dictionary rebuild. */
public final class LookupDictionary {
    public static void main(String[] args) throws Exception {
        var queries = Files.readAllLines(Path.of(args[1]), StandardCharsets.UTF_8);
        if (queries.size() > 100 || queries.stream().anyMatch(w -> w.isBlank() || w.contains("\t") || w.length() > 100)) {
            throw new IllegalArgumentException("Invalid bounded query list");
        }
        var url = new URL("jar:" + Path.of(args[0]).toUri().toURL()
            + "!/org/languagetool/resource/uk/ukrainian.dict");
        var dictionary = morfologik.stemming.Dictionary.read(url);
        var lookup = new DictionaryLookup(dictionary);
        for (String query : queries) {
            var results = lookup.lookup(query);
            if (results.isEmpty()) System.out.println(query + "\t\t");
            for (var entry : results) {
                System.out.println(query + "\t" + entry.getStem() + "\t" + entry.getTag());
            }
        }
    }
}
