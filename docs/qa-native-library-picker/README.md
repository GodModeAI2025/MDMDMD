# Native cloud library picker QA

Actual production commit 0bc7d50; Xcode MCP with persistent mcpbridge and private Unix-socket proxy. Arche Rules QA, iOS 27, 402 × 874. No production sources changed.

## Obtained evidence

Actual app installed and launched. Process 16841 remained Running through Scriptum captures. Spaces/library → All Pages → Files → Konto und Cloud was navigated using hierarchy hit points. Light-mode inspector has readable unconfigured-service and preservation/offline explanations, without observed overlap or truncation.

Cloud-Bibliothek auswählen, Continue with Apple and Vorhandene Sitzung prüfen all report Disabled in the actual hierarchy. A tap on the picker hit point leaves the inspector unchanged. No login/selection UI appears. No credentials, cloud configuration, synthetic binding or Keychain mutation was supplied.

## Interruption and limits

Opened Settings appearance read-only: Hell selected, Automatisch 0. No setting changed. Next empty capture encountered an automatic permission-review timeout. One permitted retry returned actual MCP “Session not found. It may have been closed, or the identifier is wrong”. EndSession confirmed “Session doesn't exist anymore”.

Dark mode, maximum accessibility text, Done/reopen, iPad, configured picker rows/pagination/confirmation and internal registration retention are NOT proven. No crash was observed; session loss is infrastructure evidence.

## Cleanup

StopProject stopped process 16841. XcodeCloseWorkspace closed workspace-4UJ0LfzAbi. Owned proxy/bridge shutdown returned {shutdown: true}. Settings unchanged. No alternate session/transport was started.

Raw receipts 01–08 and their screenshots/hierarchy/logs preserve actual evidence. Receipt 09 records session loss. End, stop, close and shutdown receipts preserve cleanup. Baseline source manifest is retained.
