# Scriptum

Native Markdown writing and knowledge workspace for iOS, iPadOS and macOS 27. The Mac target uses SwiftUI/AppKit with shared document, export, AI and CloudKit components. Internal Swift module names use `Skriptum`; the app is named **Scriptum**. Canonical repository: [GodModeAI2025/MDMDMD](https://github.com/GodModeAI2025/MDMDMD).

Licensed under [Apache 2.0](LICENSE), with third-party notices in [docs/licenses](docs/licenses/README.md).

## Product and release status

Scriptum is under active development. Its scope includes Spaces/pages, source-preserving writing, images/tables, revisions/recovery, export themes, writing assistance, iCloud collaboration and scheduled work. Feature implementation, native acceptance and delivery are tracked separately:

- [Binding requirements](docs/REQUIREMENTS.md) and [professional writing scope](docs/PROFESSIONAL_WRITING_PLAN.md)
- [Current release status](docs/RELEASE_STATUS.md) and [retained acceptance evidence](docs/ACCEPTANCE_STATUS_20261010.md)
- [Release preflight](docs/releases/build3/PREFLIGHT.md)
- [Build 9 delivery and native Mac evidence](docs/releases/build9/STATE.json), [feedback plan](docs/qa-testflight-feedback-20261014/PLAN.md) and [Mac acceptance scope](docs/qa-testflight-feedback-20261014/native-macos/verification.json)
- [Privacy policy drafts — German and English](docs/legal/README.md)
- [Apple submission and German/English App Store drafts](docs/app-store/README.md)

Library sync uses iCloud/CloudKit. There is no required custom workspace-storage service. OpenAI/Anthropic API keys, authorised ChatGPT access and Apple PCC are separate optional AI connections. Live access, regional availability, provisioning and current-source TestFlight delivery require their own evidence. PDF export uses the semantic renderer in the ordinary export flow. See the current release status for its tested scope.

## Repository layout

| Path | Purpose |
|---|---|
| `Sources/` | Native app and shared Swift components |
| `Tests/` | Root Swift package tests |
| `Modules/` | App-linked scheduling, writing-quality and workspace-client components |
| `Research/` | Isolated, non-shipping collaboration and workspace-service prototypes |
| `Config/`, `Brand/` | App configuration and brand assets |
| `project.yml` | XcodeGen source of truth |
| `Skriptum.xcodeproj/` | Generated native Xcode project |
| `scripts/` | Release verification and its Python tests |
| `docs/` | Product requirements, legal text, licensing and retained QA/release evidence |
| `Server/WritingQuality/` | Optional self-hosted LanguageTool setup |

## Build and verification

GitHub serves only as the code repository. GitHub Actions is disabled; builds, tests, release verification and delivery run locally through the development tools. Retained verification evidence lives in `docs/`.

Use Xcode 27 and XcodeGen. Regenerate the project after changing `project.yml`:

```sh
xcodegen generate
xcodebuild -project Skriptum.xcodeproj -scheme Skriptum -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Skriptum.xcodeproj -scheme SkriptumMac -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
swift test --disable-sandbox --scratch-path /private/tmp/ScriptumTests --no-parallel
python3 -m unittest discover -s scripts/tests -v
```

The Swift package builds shared components and selected model files. App UI and app resources build through Xcode. Expensive or live opt-in tests declare their environment flags in the relevant test and QA report.

Local build/dependency caches and credentials are ignored. QA captures, PDFs, images, logs and receipts under `docs/` are retained as evidence, with their documented scope and dates.

Historical reports retain their original paths and hashes. The current mapping for relocated prototypes is documented in [Research](Research/README.md); the native target and root package do not compile those prototypes.
