import java.io.BufferedWriter;
import java.net.URL;
import java.nio.ByteBuffer;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.util.Arrays;

/** Preserve word and encoded A..Z frequency bin separately; no source-frequency claim. */
public final class UkrainianSpellingRows {
    record Row(String word, int frequencyBin) {}

    static Row decode(ByteBuffer entry, byte separator) throws Exception {
        byte[] bytes = new byte[entry.remaining()];
        entry.duplicate().get(bytes);
        if (bytes.length < 3 || bytes.length > 4096 || bytes[bytes.length - 2] != separator)
            throw new IllegalArgumentException("Unexpected spelling record shape");
        int frequency = Byte.toUnsignedInt(bytes[bytes.length - 1]) - 'A';
        if (frequency < 0 || frequency > 25) throw new IllegalArgumentException("Unexpected frequency bin");
        for (int i = 0; i < bytes.length - 2; i++) {
            if (bytes[i] == separator || bytes[i] == 0 || bytes[i] == '\t' || bytes[i] == '\n' || bytes[i] == '\r')
                throw new IllegalArgumentException("Unexpected word delimiter");
        }
        var decoder = StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT);
        return new Row(decoder.decode(ByteBuffer.wrap(bytes, 0, bytes.length - 2)).toString(), frequency);
    }

    static void selfTest() throws Exception {
        Row first = decode(ByteBuffer.wrap("слово+A".getBytes(StandardCharsets.UTF_8)), (byte) '+');
        Row last = decode(ByteBuffer.wrap("слово+Z".getBytes(StandardCharsets.UTF_8)), (byte) '+');
        if (!first.word().equals("слово") || first.frequencyBin() != 0 || last.frequencyBin() != 25)
            throw new AssertionError("Unicode or frequency boundary lost");
        for (byte[] bad : new byte[][] {"word".getBytes(), "word+A+A".getBytes(), "word+@".getBytes(),
                "word+[".getBytes(), "wo\trd+A".getBytes(), new byte[] {(byte) 0xff, '+', 'A'}}) {
            boolean rejected = false;
            try { decode(ByteBuffer.wrap(bad), (byte) '+'); }
            catch (Exception expected) { rejected = true; }
            if (!rejected) throw new AssertionError("Malformed spelling record accepted: " + Arrays.toString(bad));
        }
        System.out.println("spelling decoder: 2 valid boundary cases, 6 malformed cases passed");
    }

    public static void main(String[] args) throws Exception {
        if (args.length == 1 && args[0].equals("--self-test")) { selfTest(); return; }
        if (args.length != 3) throw new IllegalArgumentException("JAR, fresh word output, fresh word/frequency output required");
        URL url = new URL("jar:" + Path.of(args[0]).toUri().toURL()
            + "!/org/languagetool/resource/uk/hunspell/uk_UA.dict");
        var dictionary = morfologik.stemming.Dictionary.read(url);
        if (!dictionary.metadata.isFrequencyIncluded() || dictionary.metadata.getSeparator() != (byte) '+')
            throw new IllegalArgumentException("Unexpected spelling metadata");
        long count = 0;
        long[] histogram = new long[26];
        try (BufferedWriter words = Files.newBufferedWriter(Path.of(args[1]), StandardCharsets.UTF_8, StandardOpenOption.CREATE_NEW);
             BufferedWriter records = Files.newBufferedWriter(Path.of(args[2]), StandardCharsets.UTF_8, StandardOpenOption.CREATE_NEW)) {
            for (ByteBuffer entry : dictionary.fsa) {
                if (++count > 10_000_000) throw new IllegalArgumentException("Spelling count bound exceeded");
                Row row = decode(entry, dictionary.metadata.getSeparator());
                words.write(row.word()); words.write('\n');
                records.write(row.word()); records.write('\t'); records.write(Integer.toString(row.frequencyBin())); records.write('\n');
                histogram[row.frequencyBin()]++;
            }
        }
        System.out.println("decoded spelling entries=" + count);
        System.out.println("frequencyBinHistogram=" + Arrays.toString(histogram));
    }
}
