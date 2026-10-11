# Explicit manual assistant content permission

2026-10-11. Source base036bc71 plus this patch; verification.json binds final source/test/build hashes.

The existing manual assistant had a contextual transmission hint and a Send/Start button but no separate disclosure/admission for the concrete request. The updated dialog names the recipient (including OpenAI for ChatGPT), links its privacy information and identifies target character count, reference page titles, exact included-history count, writing rules and the user's task. Cancel or sheet dismissal discards the pending permission. The API key/account configuration is not itself treated as permission to transmit a manuscript.

PageAssistant.prepare captures immutable model, prompt, context, references, same-provider history (at most eight messages) and instructions without persisting a user entry or calling a provider. AssistantSubmission has a fileprivate initializer and immutable fields. Run requires the matching current submission ID and provider. Admission consumes the one-use pending ID; cancellation, supersession or stop invalidates it. The native view stores the original text target only after successful admission, preserving the existing revision-bound proposal acceptance. A later change to history cannot silently alter the approved request. There is no persistent blanket permission or provider fallback.

Three new regression cases cover four controlled provider identities without approval, unchanged exact disk history, cancellation/discard, wrong provider, wrong/stale confirmation, immutable original history/context/model/rules/references and replay rejection. Existing history, stop/replacement, corrupt/unavailable store, original-source and provider cases now explicitly simulate approval through a test-only helper. No live provider or human UI approval is inferred from those simulations.

Full suite:621 Swift Testing headline tests, four opt-in skips,58XCTest passing. Unsigned Debug Simulator and iOS Release compile. Native sheet interaction/VoiceOver/keyboard and actual network readback remain unverified; Xcode/device connection is still needed.

Scope is **manual AssistantPanel/PageAssistant**. ScheduledAIExecutor has a separate durable authorization model and is not modified or newly certified here. Custom text-check servers, OAuth authorization and the final in-app privacy-policy link need their own acceptance. This is not a complete App Review/privacy compliance claim, live PCC/ChatGPT/API-key proof, signing/provisioning or current-source TestFlight delivery. All R01-R15 requirements remain binding.

Current reference: [Apple App Review Guideline5.1.2](https://developer.apple.com/app-store/review/guidelines/) requires disclosure and explicit permission before sharing personal data with third-party AI. Its text was checked this turn. HIG privacy and sheet guidance informed the contextual cancel/send flow.
