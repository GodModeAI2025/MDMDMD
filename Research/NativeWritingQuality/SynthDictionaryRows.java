import java.io.*;
import java.net.*;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import morfologik.stemming.*;

/** Offline source-verification tooling. No app dependency or source normalization. */
public final class SynthDictionaryRows {
  static String canonicalRow(String key, String form, String extraTag) {
    int separator = key.indexOf('|');
    if (separator <= 0 || separator != key.lastIndexOf('|') || separator == key.length()-1
        || form.isEmpty() || (extraTag != null && !extraTag.isEmpty())) {
      throw new IllegalArgumentException("Unexpected synthesis record; no field is discarded");
    }
    for (String field : new String[] {key, form}) {
      if (field.length() > 4096 || field.indexOf('\t') >= 0 || field.indexOf('\n') >= 0
          || field.indexOf('\r') >= 0 || field.indexOf('\0') >= 0) {
        throw new IllegalArgumentException("Unsafe synthesis field");
      }
    }
    return form + "\t" + key.substring(0, separator) + "\t" + key.substring(separator+1);
  }
  public static void main(String[] args) throws Exception {
    if (args.length != 3) throw new IllegalArgumentException("JAR, resource path and fresh output required");
    URL url = new URL("jar:" + Path.of(args[0]).toUri().toURL() + "!/" + args[1]);
    var dictionary = morfologik.stemming.Dictionary.read(url);
    var encoder = StandardCharsets.UTF_8.newEncoder()
        .onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT);
    long count = 0;
    try (var writer = new BufferedWriter(new OutputStreamWriter(
        Files.newOutputStream(Path.of(args[2]), StandardOpenOption.CREATE_NEW), encoder))) {
      for (var entry : new DictionaryLookup(dictionary)) {
        if (++count > 25_000_000) throw new IllegalArgumentException("Record count bound exceeded");
        writer.write(canonicalRow(entry.getWord().toString(), entry.getStem().toString(),
            entry.getTag() == null ? null : entry.getTag().toString()));
        writer.write('\n');
      }
    }
    System.out.println("decoded synthesis records=" + count);
  }
}
