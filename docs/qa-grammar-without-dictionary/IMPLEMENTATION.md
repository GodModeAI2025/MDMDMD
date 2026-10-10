# Native grammar review without spelling dictionary

NativeWritingReviewer.check previously rejected any language absent from UITextChecker.availableLanguages before issuing the separate system grammar request. The UI disabled Text prüfen when its spelling-language selection was empty. That conflated spell dictionary availability with system grammar availability and prevented eleven prior corpus attempts.

The spellingLanguage argument is now optional, default nil. Nil skips only spelling scanning; each eligible chunk still issues the existing requestGrammarChecking and applies basic local style rules. A supplied unsupported dictionary still fails explicitly, and no arbitrary dictionary/provider is substituted. The existing Markdown-safe ranges, revision-bound manual correction, cancellation continuation gate and source-size guard remain intact. API callers passing an existing valid String remain compatible.

WritingQualitySheet exposes Ohne Rechtschreibprüfung in native settings, enables native Text prüfen with empty spelling selection, and explains that spelling is omitted while grammar depends on Apple system availability. Server mode still requires an explicit selected language/catalog and user-configured endpoint. Initial automatic language suggestion runs only once per sheet, so returning from settings does not replace an intentional empty selection. No AI/server fallback is introduced.

The DEBUG native corpus now calls the real reviewer for every sample, passing nil when its primary language has no available spelling dictionary. Results still separate APPLE_GRAMMAR witnesses from APPLE_CORRECTION and record dictionary nil. Native results are evidence of the measured examples only: zero findings do not prove error-free text or unsupported language, and neither completed calls nor spell dictionaries establish twenty supported grammar languages.

Full package suite 471 Swift Testing headline (three optional skips), 58 XCTest pass; UIKit implementation is excluded from macOS package runtime. Xcode MCP Build966 proves actual SDK compilation. The native/ report and JSON are authoritative for actual UIKit runtime/UI checks. No replacement unit test merely mirrors the conditional. No capability/profile/provider/grant/upload change is performed.

## Native finding and correction

First native run completed all29 corpus examples, including eleven nil-dictionary reviews; only de and zh supplied APPLE_GRAMMAR witnesses. The actual settings/no-spelling selection and enabled button passed, but a zero-finding user review still displayed the initial start text, so UI completion could not be independently distinguished. Prior native evidence is retained, not rewritten as success.

WritingQualitySheet now sets a completion state only after the real result returns, cancellation/generation checks pass and the current page revision/source still matches. Zero findings then show an explicit completed/no-guarantee message; a new check or changed spelling language/engine resets the state. Xcode MCP Build983 compiles the corrected presentation. Native-completion evidence verifies that actual completion message; no corpus rerun is needed because reviewer logic is unchanged.
