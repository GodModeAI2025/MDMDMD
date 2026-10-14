package com.mobilebox.research;

import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Comparator;

/** JVM checks for the new broker's path policy and duplicate-resource semantics. */
public final class BrokerBoundaryProbe {
    private static int checks;
    private static void require(boolean value, String label) {
        if (!value) { throw new IllegalStateException(label); }
        checks++;
    }
    private static void rejected(Runnable operation, String label) {
        try { operation.run(); }
        catch (UncheckedIOException expected) { checks++; return; }
        throw new IllegalStateException(label);
    }
    public static void main(String[] args) throws Exception {
        var packaged = new FileResourceDataBroker(Path.of(args[0]));
        var variants = packaged.getAsURLs("org/languagetool/resource/ga/filter-archaic.txt");
        require(variants.size() == 2, "Keep both pinned Irish classpath resources");
        try (var first = variants.get(0).openStream(); var second = variants.get(1).openStream()) {
            require(!java.util.Arrays.equals(first.readAllBytes(), second.readAllBytes()), "Keep distinct Irish bytes");
        }
        Path root = Files.createTempDirectory("scriptum-resource-boundaries-");
        try {
            Path resources = root.resolve("org/languagetool/resource");
            Files.createDirectories(resources);
            Files.createDirectories(root.resolve("org/languagetool/rules"));
            Files.writeString(resources.resolve("safe.txt"), "ÄÖÜ 🦊");
            Files.writeString(root.resolve("outside.txt"), "must not be read through the broker");
            Files.createSymbolicLink(resources.resolve("alias.txt"), root.resolve("outside.txt"));
            var broker = new FileResourceDataBroker(root);
            try (var stream = broker.getAsStream("/org/languagetool/resource/safe.txt")) {
                require(new String(stream.readAllBytes(), java.nio.charset.StandardCharsets.UTF_8).equals("ÄÖÜ 🦊"), "Exact UTF-8 bytes");
            }
            require(broker.getAsURL("/org/languagetool/resource/safe.txt").getProtocol().equals("file"), "Local file URL");
            require(broker.getAsStream("/org/languagetool/resource/missing.txt") == null, "Missing packed resource has no classpath fallback");
            require(broker.getAsURL("/org/languagetool/resource/missing.txt") == null, "Missing file URL is absent");
            rejected(() -> broker.getAsStream("/org/languagetool/resource/../../../outside.txt"), "Reject traversal stream");
            rejected(() -> broker.getAsURL("/org/languagetool/resource/../../../outside.txt"), "Reject traversal URL");
            rejected(() -> broker.getAsStream("/org/languagetool/resource/alias.txt"), "Reject symlink stream");
            rejected(() -> broker.getAsURL("/org/languagetool/resource/alias.txt"), "Reject symlink URL");
        } finally {
            try (var paths = Files.walk(root)) {
                for (var path : paths.sorted(Comparator.reverseOrder()).toList()) { Files.delete(path); }
            }
        }
        System.out.println("{\"passed\":true,\"checks\":" + checks + ",\"scope\":\"JVM broker boundaries; not iOS execution\"}");
    }
}
