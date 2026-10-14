package com.mobilebox.research;

import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.graalvm.nativeimage.IsolateThread;
import org.graalvm.nativeimage.c.function.CEntryPoint;
import org.graalvm.nativeimage.c.type.CCharPointer;
import org.languagetool.DetectedLanguage;
import org.languagetool.JLanguageTool;
import org.languagetool.Languages;
import org.languagetool.tools.RuleMatchesAsJsonSerializer;

/** Isolated feasibility experiment. Not linked to, or shipped in, Scriptum. */
public final class NativeWritingQuality {
    private static final int MAX_TEXT_BYTES = 100_000;
    private static final int MAX_RESPONSE_BYTES = 2_000_000;

    private NativeWritingQuality() { }

    static String review(String languageCode, String text) throws Exception {
        if (languageCode.isEmpty() || languageCode.length() > 32 || text.indexOf('\0') >= 0
                || text.getBytes(StandardCharsets.UTF_8).length > MAX_TEXT_BYTES) {
            throw new IllegalArgumentException("Invalid input");
        }
        var language = Languages.getLanguageForShortCode(languageCode);
        // No remote rules, HTTP service, or automatic language detection.
        // A check owns its engine; JLanguageTool is not shared across threads.
        var engine = new JLanguageTool(language);
        var matches = engine.check(text);
        var serializer = new RuleMatchesAsJsonSerializer(40, language);
        return serializer.ruleMatchesToJson(matches, text, 40, new DetectedLanguage(language, language));
    }

    private static String decode(CCharPointer pointer, int length) throws CharacterCodingException {
        var bytes = new byte[length];
        for (int i = 0; i < length; i++) { bytes[i] = pointer.read(i); }
        return StandardCharsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(bytes)).toString();
    }

    /**
     * Caller owns all buffers. Returns written UTF-8 length; negative values
     * mean invalid arguments (-1), invalid text/language (-2), engine failure
     * (-3), or insufficient output capacity (-4). No partial output on failure.
     */
    @CEntryPoint(name = "scriptum_quality_check")
    public static int check(IsolateThread thread, CCharPointer language, int languageLength,
                            CCharPointer text, int textLength, CCharPointer output, int capacity) {
        if (language.isNull() || text.isNull() || output.isNull()
                || languageLength < 1 || languageLength > 32
                || textLength < 0 || textLength > MAX_TEXT_BYTES
                || capacity < 0 || capacity > MAX_RESPONSE_BYTES) { return -1; }
        try {
            var result = review(decode(language, languageLength), decode(text, textLength))
                    .getBytes(StandardCharsets.UTF_8);
            if (result.length > capacity || result.length > MAX_RESPONSE_BYTES) { return -4; }
            for (int i = 0; i < result.length; i++) { output.write(i, result[i]); }
            return result.length;
        } catch (IllegalArgumentException | CharacterCodingException error) {
            return -2;
        } catch (Exception error) {
            return -3;
        }
    }

    public static void main(String[] args) throws Exception {
        if (args.length == 2 && args[0].equals("--corpus")) {
            var mapper = new ObjectMapper();
            var records = mapper.readTree(Path.of(args[1]).toFile()).get("records");
            if (records == null || !records.isArray() || records.size() > 100) {
                throw new IllegalArgumentException("Invalid synthetic corpus");
            }
            var output = mapper.createArrayNode();
            for (var record : records) {
                var language = record.get("language").asText();
                var text = record.get("source").asText();
                var started = System.nanoTime();
                var response = mapper.readTree(review(language, text));
                for (var expected : record.get("response").get("matches")) {
                    var rule = expected.get("rule").get("id").asText();
                    boolean found = false;
                    for (var match : response.get("matches")) {
                        if (match.get("rule").get("id").asText().equals(rule)) { found = true; }
                    }
                    if (!found) { throw new IllegalStateException("Missing expected synthetic rule: " + language + " / " + rule); }
                }
                var item = output.addObject();
                item.put("language", language);
                item.put("elapsedMillis", (System.nanoTime() - started) / 1_000_000);
                item.set("response", response);
            }
            System.out.println(mapper.writeValueAsString(output));
        }
        else if (args.length == 2) { System.out.println(review(args[0], args[1])); }
        else if (args.length == 0) { System.out.println("Scriptum native quality research / LT " + JLanguageTool.VERSION); }
        else { throw new IllegalArgumentException("Expected language and synthetic text"); }
    }
}
