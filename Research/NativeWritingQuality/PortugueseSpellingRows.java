import java.io.BufferedWriter;
import java.net.URL;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.nio.charset.CodingErrorAction;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.util.Arrays;
import java.util.Set;

/** Decode only the three pinned Portuguese spelling resources; preserve frequency bins. */
public final class PortugueseSpellingRows {
    record Row(String word, int frequencyBin) {}

    static Row decode(ByteBuffer entry) throws Exception {
        byte[] bytes = new byte[entry.remaining()]; entry.duplicate().get(bytes);
        if (bytes.length < 3 || bytes.length > 4096 || bytes[bytes.length - 2] != '_')
            throw new IllegalArgumentException("Unexpected Portuguese spelling record");
        int frequency = Byte.toUnsignedInt(bytes[bytes.length - 1]) - 'A';
        if (frequency < 0 || frequency > 25) throw new IllegalArgumentException("Invalid frequency bin");
        for (int i = 0; i < bytes.length - 2; i++)
            if (bytes[i] == 0 || bytes[i] == '\n' || bytes[i] == '\r')
                throw new IllegalArgumentException("Unrepresentable spelling word");
        String word = StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes, 0, bytes.length - 2)).toString();
        return new Row(word, frequency);
    }

    static String resource(String variant) {
        if (!Set.of("pt-BR", "pt-PT-45", "pt-PT-90").contains(variant))
            throw new IllegalArgumentException("Unknown Portuguese spelling variant");
        return "org/languagetool/resource/pt/spelling/" + variant + ".dict";
    }

    static void selfTest() throws Exception {
        for (String variant : Set.of("pt-BR", "pt-PT-45", "pt-PT-90")) {
            if (!resource(variant).endsWith("/" + variant + ".dict")) throw new AssertionError();
        }
        for (String variant : new String[] {"pt", "../pt-BR", "pt-BR.dict", "https://example.invalid"}) {
            try { resource(variant); throw new AssertionError("Unsafe variant accepted"); }
            catch (IllegalArgumentException expected) {}
        }
        var row = decode(ByteBuffer.wrap("ação_Z".getBytes(StandardCharsets.UTF_8)));
        if (!row.word().equals("ação") || row.frequencyBin() != 25) throw new AssertionError();
        var tabs = decode(ByteBuffer.wrap("pré-antessoubé-la\t\t_A".getBytes(StandardCharsets.UTF_8)));
        if (!tabs.word().equals("pré-antessoubé-la\t\t") || tabs.frequencyBin() != 0) throw new AssertionError();
        if (!decode(ByteBuffer.wrap("a_b_A".getBytes(StandardCharsets.UTF_8))).word().equals("a_b")) throw new AssertionError();
        for (byte[] bad : new byte[][] {"word".getBytes(), "word_@".getBytes(), "word_[".getBytes(),
                "wo\nrd_A".getBytes(), "wo\rrd_A".getBytes(), "wo\0rd_A".getBytes(),
                "_A".getBytes(), new byte[] {(byte) 0xff, '_', 'A'}, new byte[4097]}) {
            boolean rejected = false;
            try { decode(ByteBuffer.wrap(bad)); } catch (Exception expected) { rejected = true; }
            if (!rejected) throw new AssertionError("Invalid record accepted");
        }
        System.out.println("Portuguese adapter: 3 variants, 4 invalid variants, 3 exact words and 9 invalid records passed");
    }

    public static void main(String[] args) throws Exception {
        if (args.length == 1 && args[0].equals("--self-test")) { selfTest(); return; }
        if (args.length != 4) throw new IllegalArgumentException("JAR, variant, fresh words, fresh frequencies required");
        URL url = new URL("jar:" + Path.of(args[0]).toUri().toURL() + "!/" + resource(args[1]));
        var dictionary = morfologik.stemming.Dictionary.read(url);
        if (!dictionary.metadata.isFrequencyIncluded() || dictionary.metadata.getSeparator() != (byte) '_')
            throw new IllegalArgumentException("Unexpected Portuguese spelling metadata");
        long count = 0;
        long tabWords = 0, underscoreWords = 0;
        long[] histogram = new long[26];
        try (BufferedWriter words = Files.newBufferedWriter(Path.of(args[2]), StandardCharsets.UTF_8, StandardOpenOption.CREATE_NEW);
             BufferedWriter frequencies = Files.newBufferedWriter(Path.of(args[3]), StandardCharsets.UTF_8, StandardOpenOption.CREATE_NEW)) {
            for (ByteBuffer entry : dictionary.fsa) {
                if (++count > 25_000_000) throw new IllegalArgumentException("Spelling count bound exceeded");
                var row = decode(entry);
                if (row.word().contains("\t")) tabWords++;
                if (row.word().contains("_")) underscoreWords++;
                words.write(row.word()); words.write('\n');
                frequencies.write(row.word()); frequencies.write('\t');
                frequencies.write(Integer.toString(row.frequencyBin())); frequencies.write('\n');
                histogram[row.frequencyBin()]++;
            }
        }
        System.out.println("decoded spelling entries=" + count);
        System.out.println("frequencyBinHistogram=" + Arrays.toString(histogram));
        System.out.println("wordDataPreserved: tabs=" + tabWords + " underscores=" + underscoreWords);
    }
}
