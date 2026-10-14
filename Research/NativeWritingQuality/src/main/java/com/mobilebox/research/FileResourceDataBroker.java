package com.mobilebox.research;

import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.net.URL;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.util.List;
import org.languagetool.broker.DefaultResourceDataBroker;

/** Research broker for byte-verified, private-cache rule resources. */
final class FileResourceDataBroker extends DefaultResourceDataBroker {
    private final Path root;

    FileResourceDataBroker(Path directory) throws IOException {
        if (!directory.isAbsolute()) { throw new IOException("Resource root must be absolute"); }
        root = directory.toRealPath();
        if (!Files.isDirectory(root.resolve("org/languagetool/resource"), LinkOption.NOFOLLOW_LINKS)
                || !Files.isDirectory(root.resolve("org/languagetool/rules"), LinkOption.NOFOLLOW_LINKS)) {
            throw new IOException("Incomplete resource package");
        }
    }

    private Path resource(String name) throws IOException {
        String absolute = name.startsWith("/") ? name : "/" + name;
        // Preserve both original classpath variants and their enumeration order.
        if (absolute.equals("/org/languagetool/resource/ga/filter-archaic.txt")) { return null; }
        if (!absolute.startsWith("/org/languagetool/resource/")
                && !absolute.startsWith("/org/languagetool/rules/")) { return null; }
        Path relative = Path.of(absolute.substring(1));
        for (Path segment : relative) {
            if (segment.toString().equals("..")) { throw new IOException("Invalid resource traversal"); }
        }
        Path file = root.resolve(relative).normalize();
        if (!file.startsWith(root)) { throw new IOException("Resource outside root"); }
        Path cursor = root;
        for (Path segment : root.relativize(file)) {
            cursor = cursor.resolve(segment);
            if (Files.isSymbolicLink(cursor)) { throw new IOException("Resource symlink rejected"); }
        }
        return file;
    }

    @Override public InputStream getAsStream(String name) {
        try {
            Path file = resource(name);
            if (file == null) { return super.getAsStream(name); }
            if (!Files.isRegularFile(file, LinkOption.NOFOLLOW_LINKS)) { return null; }
            return Files.newInputStream(file, StandardOpenOption.READ, LinkOption.NOFOLLOW_LINKS);
        } catch (IOException error) { throw new UncheckedIOException(error); }
    }

    @Override public URL getAsURL(String name) {
        try {
            Path file = resource(name);
            if (file == null) { return super.getAsURL(name); }
            return Files.isRegularFile(file, LinkOption.NOFOLLOW_LINKS) ? file.toUri().toURL() : null;
        } catch (IOException error) { throw new UncheckedIOException(error); }
    }

    @Override public List<URL> getAsURLs(String name) {
        try {
            if (resource(name) == null) { return super.getAsURLs(name); }
            URL value = getAsURL(name);
            return value == null ? List.of() : List.of(value);
        } catch (IOException error) { throw new UncheckedIOException(error); }
    }
}
