# Professional export and writing-quality extension — 2026-10-09

The original R01–R12 scope remains active. Added acceptance requirements:

- R13: PDF, DOCX, HTML, unchanged Markdown and EPUB export share a validated style-theme model; font, size, leading, margins, paper size and heading treatment appear in the live preview and actual output. Blog-ready semantic HTML plus media/metadata package, no automatic publication. Themes persist per library/Space; manuscript chapters keep independent notes/images. Standalone `(toc)` exports a real contents list outside code fences.
- R14: integrated spelling, grammar and style review; 20+ distinct languages through a verified rule engine, not merely language variants or a list of spell dictionaries. Native iOS27 UITextChecker grammar/spelling plus local style checks; optional explicitly selected own LanguageTool server for comprehensive multi-language rules. Never send text to a public service by default. AI proofreading, rewriting and summary use the chosen OpenAI/Anthropic/PCC/account route and runtime regional/language availability; no silent fallback. Every correction is source/revision-bound, UTF-16 safe, undoable and manually accepted.
- R15: suitable Ulysses-inspired additions: backlinks and heading links, navigation history, project/page templates, research material excluded from manuscript exports/statistics, customizable editing controls, per-project export preferences, richer table editing and attachment dashboard. Existing multiwindow, revision, goals and source-preserving work remains required. Widgets/App Intents follow the native capability/accessibility gates. No proprietary Ulysses theme format, icons or branding is copied.

## Source selection
Inspected official https://ulysses.app/en/releases/ : export profiles/previews, table of contents, backlink/navigation, templates/material, keyboard/menu customizability and publishing-friendly copy are relevant. Older platform-specific Mac-only changes and old OS compatibility fixes are not copied as separate requirements. LanguageTool's official self-host documentation says its server includes rule-based checks rather than cloud-only AI rules; AI remains a separate Scriptum provider path.

## Implementation wave and ownership
1. Export engine agent: validated Codable theme model; compatible profile defaults; HTML/EPUB/DOCX apply theme consistently; real blog HTML/media ZIP output and TOC; permanent tests for XML/CSS/assets/unsafe styles/Unicode. Own Sources/SkriptumExport and Tests/SkriptumExportTests only.
2. Quality agent: standalone Modules/SkriptumWritingQuality package, Markdown-safe checking/projection, source-bound corrections, native iOS27 adapter, explicit LanguageTool adapter and real local server/language evidence. Own module and Server/WritingQuality only; no app/root project edits. Do not count unsupported grammar languages as supported or use a public fallback.
3. Root: integrate export theme controls/live preview/PDF paper geometry and native quality panel/AI actions; root Package.swift/project.yml changes only after module API freeze. Existing app code and uploaded artifact are separate snapshots.
4. Independent review, package tests, actual Xcode MCP phone/iPad preview/correction/output verification. No requirement closes on a picker or mocked grammar response alone.

## Important capability boundary
The actual iOS27 SDK provides UITextChecker.requestGrammarChecking(of:range:waitForAllResults:completionHandler:), but its availableLanguages property describes spellchecking languages. Native grammar coverage must be measured separately. A server catalog proves language availability, not equal quality in every language. Document supported modes and meaningful examples. 20+ coverage remains incomplete until real engine evidence and a usable selected route exist.

## Review change — code protection

Independent review reproduced corrections inside fenced and indented code nested in blockquotes. Incremental regular-expression container fixes left further gaps. Code protection therefore uses the existing pinned Swift Markdown 0.9.0 parser and original source ranges, with UTF-8 columns mapped to unchanged UTF-16 source offsets. Existing regression tests remain fixed; nested, indented, tab, Unicode and CRLF cases extend them. No professional-quality completion claim is made before parser protection, fresh review and native checks pass.

Correction eligibility is now protected by default: only source-backed AST prose text may be changed. Omitted reference definitions and unknown metadata remain protected rather than relying on an exhaustive container regular expression. Explicit footnote IDs, URI targets and export directives remain protected. TOC-role tests compare the grammar guard to the actual exporter, including paragraphs nested in quotes/lists, to prevent semantic drift between modules.
