# Professional writing controls — follow-up after internal build 1

The original R01–R12 acceptance scope remains unchanged. Build 1 is an internal milestone, not completion of the product.

## Problem and resulting behavior
The default block editor currently ignores the keyboard formatting command and the outline jump used by the source editor. A visible control must act on the focused block, retain its identity and source boundaries, and use the native undo path. Outline navigation must scroll to and select the corresponding block/caret on both writing and source views.

## Tasks and ownership
- Blocks: public command value plus once-only handling; native TextKit replacement; pure UTF-16/Unicode/CRLF tests; global source-offset to block/caret mapping and scroll activation. Existing image, transaction and lossless tests remain unchanged.
- App: bridge the existing toolbar command into Blocks, clear consumed commands, show a meaningful message if no editable block is focused, and forward outline jumps. No change to the uploaded build's archive or declared provenance.
- Verification: targeted package tests, real iOS27 SDK build, independent review of the new source commit, delegated Xcode MCP device interaction for default-mode formatting/undo and outline navigation.

## Release gates already advanced
1139ce8: 79 aggregate tests, independent integration review pass, real signed archive and App Store export with PCC in both profile and signature. Internal-only upload of 1.0.0 (1) succeeded; portal reports processed build with missing compliance. Automatic approval review refused the build-specific export declaration. The exact declaration is prepared and pending explicit user approval; do not set a plist exemption or use another interface to bypass that refusal.

## Full-scope work still required
Shared roles/collaboration, authorized persistent server scheduling/budgets, complete provider authentication/inference and physical-device PCC proof, accessibility/performance acceptance, complete media/visual workflows and the remaining release evidence remain open. Shipping an internal build does not close those requirements.
