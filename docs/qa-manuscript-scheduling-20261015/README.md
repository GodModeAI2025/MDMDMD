# Manuscript export and scheduling — 15 October 2026

This checkpoint corrects two reproduced defects. Per the owner’s instruction, verification is limited to changed paths and required packaging; previously confirmed unchanged features are not re-tested.

## DOCX images

Images previously used full page width inside tables, lists and quotes. The preserved baseline loses the right-hand table column and exceeds the right margin. The renderer now uses actual container width, explicit fixed table columns/cell margins, nested indentation and zero image distances. Natural sizes and aspect ratios remain intact. Two focused A4/Letter cases pass; both fail on the baseline. The generated DOCX was rendered through LibreOffice and visually inspected: the Notes column is visible and quoted/listed images end at 523.300 pt against a 523.304 pt content boundary. Microsoft Word itself was not run. See docx/ for before/after documents, images, XML assertions and measurements.

## Scheduled transmission admission

The baseline sends the captured private source after pause, cancellation, source deletion, quote expiry or a UTC budget month rollover during the final asynchronous provider access check. Transmission admission now occurs after that check, immediately before provider streaming. Durable dispatch/start, quote/month, source and lifecycle checks remain required. Pre-dispatch cancellation releases reserved account budget, including cancellation while the account reservation is being persisted before the local reservation exists. Already uncertain transmissions retain conservative accounting and are not blindly retried.

The final focused run passes eight parameter cases plus both existing reservation persistence failure tests (three test definitions, 0.099 s). Invalid cases record zero provider calls and preserve manuscript UTF-8 bytes. The preceding coupled run passed 75 workspace-model definitions and 39 scheduling tests with two optional price/network skips. The two new refund-race cases were added afterward and verified in the final focused run. Scheduling tests use an in-process provider and temporary durable stores; no real provider request or credential is involved. See scheduling/ for baseline, corrected harness and logs.

## Delivery boundary

SOURCE_HASHES.json binds the exact changed source, tests and build versions. Official Xcode MCP build receipts and signed distribution results are recorded in the associated release report. No app/device/simulator launch, broad unchanged-feature audit or new dependency was added in this checkpoint. Existing Apple-only grammar and privacy configuration are preserved.

Delivered as iOS33 / native Mac34, both in TestFlight and submitted to App Store review. [Exact delivery receipts and current states](../releases/ios33-mac34-manuscript-scheduling/README.md).
