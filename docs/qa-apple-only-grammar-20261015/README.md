# Apple-only grammar — 15 October 2026

The owner explicitly requires “Grammatik nur mit Apple Tools”. WritingQualitySheet now calls only NativeWritingReviewer: UIKit UITextChecker on iOS/iPadOS and AppKit NSSpellChecker on native Mac. Custom server configuration, its transmission/consent flow and bundled LanguageTool selection/loading are removed from the production UI. Both Xcode targets exclude LanguageToolClient, BundledGrammarRuntime, BundledRuleReviewer and RuleResponseDecoder. The obsolete checking-server local-network usage declaration is removed. Existing research, source/license evidence and historical adapter tests remain preserved; they are not a current product requirement.

Spelling dictionary selection remains separate from system grammar availability. The dialog keeps per-finding acceptance, revision admission, cancellation, correction history and protected Markdown. Basic local style hints remain separate from grammar, as does explicitly invoked AI proofreading using the chosen access. No new public checking service or fallback is introduced. Repository privacy drafts in German, English and the prepared website copy reflect this source change; Jimdo remains separate and no privacy publication occurred.

A permanent Unicode regression also reproduces missing repeated-word style findings for decomposed accents on the old rule. The rule now includes combining marks after a leading letter, preserving exact original bytes. Tests cover decomposed Latin/Greek, Hindi/Bengali, emoji/CRLF/tab context, exact correction and protected code/URL/nonduplicate boundaries. This is a basic style rule, not language-wide grammar proof.

## Evidence

- unicode-baseline.log: old production rule fails the combining-mark finding test; protected-boundary test passes.
- quality-final.log: all 80 tests in six suites pass. This includes retained historical LanguageTool tests; it is not a claim that 80 Apple grammar cases or 20 languages were validated.
- Final official Xcode MCP iOS SDK build passes in 6.835 seconds and native Mac in 7.822 seconds, with empty error arrays. Full logs and actual workspace readback are retained. Original scheme/destination restored and temporary MCP bridge shut down.
- SOURCE_HASHES.json binds the final production source and tests. No app/device/simulator UI was launched.

## Delivery boundary

This change follows iOS27/Mac28, whose existing TestFlight packages still have the optional own-server route. It is now delivered in iOS29/Mac30, both verified Im Test in the existing internal group; it does not rewrite the older packages. [Release evidence](../releases/ios29-mac30-apple-grammar/README.md). Apple grammar coverage depends on actual system/language availability; 20+ measured grammar languages remain unproven. Existing Store submissions iOS11/Mac14 remain retained.
