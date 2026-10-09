# Apple Foundation Models Utilities

Upstream: https://github.com/apple/foundation-models-utilities
Pinned revision: `cc3820def1fe016bc6cd49d958cd2f2a29be76a8`.

The package is linked in SwiftPM and the native iOS target. ApplePCCProvider now creates its model session from AppleWritingProfile, using the package's Skills and droppingCompletedToolCalls modifier. Request-local activations expose three static, read-only writing guides: Markdown integrity, conservative proofreading and faithful summarization. Application instructions stay in the base profile; document data never creates skills or filesystem tools. The helpers do not grant PCC access or change entitlement/availability gates.

Completed internal guide/tool-call exchanges can be removed from the model transcript. The private stored chat history and the original manuscript remain unchanged. No rolling-window trimming or model-driven history summarization is enabled: the current provider creates a fresh session per request and packs application history explicitly. These modifiers would not solve a large initial manuscript prompt. Long-document segmentation remains separate work.

Existing OpenAI Responses/ChatGPT and Anthropic transports remain in use. The package's generic chat-completions client is not connected to new endpoints. No extra hosted service, provider fallback or automatic additional inference request is introduced.

The cumulative PCC stream now verifies exact UTF-8 prefixes rather than Character offsets; a combining accent emitted after its base glyph is retained. Focused tests verify exact Unicode reconstruction, rejection of altered prefixes and activation isolation between requests.

Validation: 352 executed local tests passed (58 XCTest + 294 Swift Testing); one historical own-server integration test skipped. Final native iOS Simulator SDK build succeeded and includes the license resource. Actual PCC model inference and guide activation on a provisioned physical device remain unverified. No new TestFlight upload is implied.

Apache-2.0 license copy: Sources/SkriptumAI/Resources/FoundationModelsUtilitiesLicense.txt, included in the app resources and SwiftPM resource bundle. Upstream describes these patterns as emerging/experimental; revision changes require review and fresh checks.
