# Footnote extraction cancellation checkpoints

Source baseline d29198a, 2026-10-10. Inspection found that continuation lines and blank-line lookahead inside a single footnote bypassed the existing outer-loop cancellation checkpoint. SemanticDocument.swift now calls Task.checkCancellation in both inner loops. Footnote extraction, stored Markdown and output semantics otherwise remain unchanged.

Full SwiftPM command completed exit0: 480 Swift Testing headline, three optional skips, 58 XCTest with no failures. Existing cancellation admission/worker forwarding and literal/container footnote regressions pass. This does not establish a deterministic mid-loop cancellation timing or system parser hard-interruption bound. No new mirror test was added for the two checkpoint calls.

Xcode MCP BuildProject also succeeded with no errors. Original Carina iPhone destination restored after fresh selection check. No new unsigned Release or signed archive/upload is claimed for this checkpoint change.
