import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;

class InspectSpellingRecord {
    public static void main(String[] args) throws Exception {
        var url = new java.net.URL("jar:" + Path.of(args[0]).toUri().toURL()
            + "!/org/languagetool/resource/pt/spelling/pt-BR.dict");
        var dictionary = morfologik.stemming.Dictionary.read(url);
        long count = 0;
        for (ByteBuffer entry : dictionary.fsa) {
            if (++count > 25_000_000) throw new IllegalArgumentException();
            try { UkrainianSpellingRows.decode(entry, dictionary.metadata.getSeparator()); }
            catch (IllegalArgumentException invalid) {
                byte[] bytes = new byte[entry.remaining()]; entry.duplicate().get(bytes);
                if (bytes.length > 4096) throw new IllegalArgumentException();
                System.out.println("entry=" + count + " raw=" + new String(bytes, StandardCharsets.UTF_8));
                System.out.println("bytes=" + java.util.HexFormat.of().formatHex(bytes));
                return;
            }
        }
    }
}
