# Native grammar witnesses and explicit spelling language choice

2026-10-10. R14 remains incomplete. This work measures the integrated native route and removes an unrelated-dictionary fallback; it does not claim comprehensive grammar/style support in 20 languages.

## Native measurements

The DEBUG-only host reuses 29 distinct primary-language synthetic rule examples from the existing pinned LanguageTool6.6 engine evidence. These examples establish upstream rule execution and include spelling/style/typography cases, not exclusively syntactic grammar errors. Each eligible sample calls the actual integrated NativeWritingReviewer. Only `APPLE_GRAMMAR` findings count as grammar witnesses; spelling, local style and `APPLE_CORRECTION` do not.

Actual iOS27 simulator results:29 attempts,18 native reviews completed,11 skipped because the integrated route had no matching spelling dictionary. German and Chinese each produced one native grammar finding; correction findings were zero. The Chinese route selected `zh_Hant` from the actual available dictionary list; it is not proof of Simplified Chinese support. No timeout or restart occurred during this measurement. See native-results.json and native-corpus/REPORT.md.

Zero findings do not prove unsupported grammar or error-free text. A missing spelling dictionary does not prove that Apple's grammar service cannot analyze that language. The corpus is too weak to establish a complete native language support matrix. Native20-language grammar coverage is unproven, and the own-server29-rule-language evidence is not evidence of an embedded iOS engine.

## Product correction

Previously a missing detected-language match silently selected the first native dictionary. SpellingLanguageChoice now matches the detected primary language, preserves an explicitly detected script, prefers a matching system locale within that language and returns no selection when no candidate exists. Only a missing detection can use a matching system language. Source-language detection uses a bounded, syntax-masked prose excerpt instead of raw code/Markdown. The selected native language is labeled Rechtschreibung rather than a general language claim.

An empty choice has a valid Bitte wählen picker tag and a clear selection action. Own-server language selection likewise avoids blindly taking the first catalog entry and preserves an existing still-valid choice when a catalog loads. No public server, new credential or fallback AI route is added.

Tests prove unsupported detected Persian cannot become Arabic/German/English merely because those dictionaries exist, Chinese Hans cannot become Hant, and same-language system variants are preferred. Full suite:434 Swift Testing functions +58 XCTest cases pass; three optional skips.

## Native language-choice observations

The first new DEBUG fixture displayed a blank sheet. Its presentation was corrected to a single immutable sheet item carrying the actual library and page; the historical failure remains recorded.

After that correction, the real WritingQualitySheet appears. The Persian fixture initially displayed Arabic automatically, so the unsupported-Persian/no-selection UI branch was NOT verified. This observation does not establish the recognizer's raw output or root cause. Automatic language suggestion remains imperfect; its result is visible and can be overridden. The pure chooser's unsupported-language behavior is covered by tests.

Actual picker selection of Deutsch(Deutschland), Fertig, the resulting Rechtschreibung header and enabled check button are verified, followed by closing back to the host. No text check, AI action, server request or document mutation was performed. Production controls were readable; the long unsorted dictionary menu required scrolling. See explicit-language-choice/REPORT.md.

## Build and release boundary

Xcode MCP Build778 passes. Optimized unsigned Release1.0.0(3) passes, executable SHA256 `2578d7beb87b41b7e666ad38c79dc5bd83b531c857f29c873d66aa25133d9b60`. The new diagnostic flag and temporary grammar-result identifier are absent from the executable. Native probe and choice manifests match before each session ends. This compile is not a signed TestFlight upload.

Remaining requirements include meaningful grammar/style evidence for20+ languages on a usable supported route, imperfect automatic detection, the unobserved no-dictionary UI branch, physical-device/PCC inference, real iCloud sharing and newly signed TestFlight distribution. No requirement is closed by a spell dictionary list or these limited witnesses alone.


Final locale refinement: when detection gives only a primary language and the catalog contains both a generic entry and the system variant, the system variant wins. An explicitly detected regional variant remains authoritative. The two final choice test functions pass with additional generic/region assertions; their log is locale-refinement-tests.log. The final optimized Release build includes this refinement. Native Arabic/German UI observations above precede this English-locale-only refinement and do not claim a repeated UI run for it.
