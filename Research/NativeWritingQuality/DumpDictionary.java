import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.net.*;
import morfologik.stemming.*;
public final class DumpDictionary {
 public static void main(String[] args) throws Exception {
  var url = new URL("jar:" + Path.of(args[0]).toUri().toURL() + "!/" + args[1]);
  var dictionary = morfologik.stemming.Dictionary.read(url);
  var lookup = new DictionaryLookup(dictionary);
  long count = 0;
  try (var writer = Files.newBufferedWriter(Path.of(args[2]), StandardCharsets.UTF_8, StandardOpenOption.CREATE_NEW)) {
   for (var entry : lookup) {
    writer.write(entry.getWord().toString()); writer.write('\t');
    writer.write(entry.getStem().toString()); writer.write('\t');
    if (entry.getTag() != null) writer.write(entry.getTag().toString());
    writer.write('\n'); count++;
   }
  }
  System.out.println("decoded entries=" + count);
 }
}
