# Scriptum
Native Markdown writing and knowledge workspace for iOS / iPadOS 27.
Repository destination supplied by owner: GodModeAI2025/MDMDMD.

## Current state
Free and open source under Apache 2.0.

Under active development. Not yet a complete product or TestFlight delivery.
The full acceptance scope is in docs/REQUIREMENTS.md.

Implemented foundation: Spaces/pages, Markdown source editor, external DocumentGroup files, focus/outline/statistics, favorites/tags/trash, durable edit journals, conflict-checked revisions, comments, Markdown import/share, explicit provider chat and reviewable revision drafts.
OpenAI/Anthropic adapters compile; live inference is not yet verified. PCC requires Apple entitlement approval; native ChatGPT subscription sign-in is being implemented using the documented free OSS path; live mobile login is not yet verified.
Collaboration, scheduling infrastructure, full export suite, visuals/media and release acceptance remain open.

## Build
Xcode 27 and XcodeGen required.

```sh
xcodegen generate
xcodebuild -project Skriptum.xcodeproj -scheme Skriptum -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
swift test --disable-sandbox
```

project.yml is the source of truth for generated Xcode project settings.
