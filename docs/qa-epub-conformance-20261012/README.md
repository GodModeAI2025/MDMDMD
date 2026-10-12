# EPUB conformance and optional author metadata

The normal authorless EPUB path emitted an empty `dc:creator`. EPUBCheck rejects the retained native historical export with RSC-005. A current-source regression independently parses both page and manuscript ZIP/XML and reproduces three failures for empty/whitespace-only names. Its two nonempty names pass before the fix.

The renderer now omits optional creator metadata when the supplied name contains only whitespace. Actual entered names retain their exact original UTF-8 content after XML decoding, including decomposed accents, emoji, ampersands, angle brackets and outer spaces. No author is invented.

## Current-source evidence

- All 124 export-test headlines pass (one existing opt-in long-corpus skip). The new parameterized regression covers five names for both page and manuscript export.
- Unsigned iPhoneOS Release compilation succeeds. This is not signing or TestFlight evidence.
- Six fresh artifacts from the actual current ExportEngine pass official W3C EPUBCheck 5.4.0 with zero messages. The local validator is a development tool, not an app dependency.
- Each of three 24-chapter manuscript profiles retains 1,440 prose paragraphs, 1,440 fox emoji, 1,440 decomposed Unicode witnesses, 24 tables, 24 footnotes and 48 TOC links, independently checked with ZIP/XML parsing. These fixtures do not contain images and do not establish every theme or reader behavior.
- Apple Books was opened for the real reader check. The attempted path entry/import was rejected by automatic approval because it could modify the user's library and synchronize. Neither the file path nor import was performed. The owned path/import dialogs were canceled; reader fidelity remains unverified.

## Provenance corrections retained

The first standalone fixture attempts linked an obsolete `arm64-apple-macosx/debug` cache, even though current SwiftPM writes `out/Products/Debug`. They are excluded from current-source acceptance; their summary files remain under excluded-cache-attempts and their complete artifacts remain in the original work directory. The final generator resolves the active `debug` link and uses current whole-module objects. verification.json binds those products, source bytes and exact final EPUB files.

The first regression used process arguments for its Unicode expectation; Foundation normalized a nonempty name in that transport. The corrected regression writes the expected raw UTF-8 to a file. Its failure-before result isolates the three real authorless-metadata failures. Both logs are retained; no Unicode defect is claimed from the discarded transport expectation.

The fix is on a separate branch so PR #2 remains exactly at the `2c2fcf5` source already awaiting confirmation. Full R01–R15, actual reader/device/iCloud/provider acceptance and current-source signed TestFlight gates remain open.
