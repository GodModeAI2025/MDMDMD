import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.ByteArrayOutputStream;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.util.ArrayList;
import java.util.List;
import morfologik.fsa.FSA;
import morfologik.fsa.builders.FSABuilder;
import morfologik.fsa.builders.CFSA2Serializer;

/** Same pinned builder/CFSA2 defaults as FSACompile, using externally sorted input. */
public final class RebuildSpellingFSA {
    static long build(Path input, Path output) throws Exception {
        if (Files.exists(output)) throw new IllegalArgumentException("Fresh FSA output required");
        var builder = new FSABuilder();
        byte[] previous = null;
        long count = 0;
        try (var stream = new BufferedInputStream(Files.newInputStream(input))) {
            var line = new ByteArrayOutputStream(128);
            for (int value; (value = stream.read()) != -1;) {
                if (value != '\n') {
                    line.write(value);
                    if (line.size() > 4096) throw new IllegalArgumentException("Oversized FSA record");
                    continue;
                }
                byte[] sequence = line.toByteArray(); line.reset();
                PortugueseSpellingRows.decode(ByteBuffer.wrap(sequence));
                if (previous != null && FSABuilder.LEXICAL_ORDERING.compare(previous, sequence) >= 0)
                    throw new IllegalArgumentException("FSA records must be unique and byte-sorted");
                if (++count > 25_000_000) throw new IllegalArgumentException("FSA row bound exceeded");
                builder.add(sequence, 0, sequence.length); previous = sequence;
            }
            if (line.size() != 0 || count == 0) throw new IllegalArgumentException("Incomplete FSA input");
        }
        try (var stream = new BufferedOutputStream(Files.newOutputStream(output, StandardOpenOption.CREATE_NEW))) {
            new CFSA2Serializer().serialize(builder.complete(), stream);
        }
        return count;
    }

    static void selfTest(Path root) throws Exception {
        Files.createDirectory(root);
        Path input = root.resolve("input.txt"), first = root.resolve("first.dict"), second = root.resolve("second.dict");
        List<String> expected = List.of("alpha_A", "zeta_Z", "á_A");
        Files.writeString(input, String.join("\n", expected) + "\n", StandardCharsets.UTF_8);
        if (build(input, first) != 3 || build(input, second) != 3) throw new AssertionError();
        if (!java.util.Arrays.equals(Files.readAllBytes(first), Files.readAllBytes(second))) throw new AssertionError();
        var actual = new ArrayList<String>();
        try (var stream = Files.newInputStream(first)) {
            for (ByteBuffer value : FSA.read(stream)) actual.add(StandardCharsets.UTF_8.decode(value).toString());
        }
        if (!actual.equals(expected)) throw new AssertionError(actual.toString());
        for (String bad : List.of("z_A\na_A\n", "a_A\na_A\n", "a_A", "a_@\n", "")) {
            Files.writeString(input, bad, StandardCharsets.UTF_8);
            try { build(input, root.resolve("invalid.dict")); throw new AssertionError("Invalid input accepted"); }
            catch (IllegalArgumentException expectedError) {}
        }
        try { build(input, first); throw new AssertionError("Existing output overwritten"); }
        catch (IllegalArgumentException expectedError) {}
        System.out.println("FSA builder: exact UTF-8 round trip, deterministic bytes, 5 invalid cases, overwrite refusal passed");
    }

    public static void main(String[] args) throws Exception {
        if (args.length == 2 && args[0].equals("--self-test")) { selfTest(Path.of(args[1])); return; }
        if (args.length != 2) throw new IllegalArgumentException("Sorted spelling records and fresh FSA output required");
        long count = build(Path.of(args[0]), Path.of(args[1]));
        System.out.println("rebuilt CFSA2 records=" + count + " bytes=" + Files.size(Path.of(args[1])));
    }
}
