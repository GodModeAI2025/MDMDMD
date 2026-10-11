# Integrity of historical version restoration

The pre-fix five-test fixture reproduced nine failed expectations: absent/corrupt historical image data did not reject restoration or preserve disk/model state; restoring the same version again created another history entry/notification; a parent restored its historic untrashed state while its descendants stayed trashed. BEFORE_TESTS.txt retains the original failure receipt.

LibraryStore.restoreRevision now validates every historical image before changing the candidate page. It restores historical writing content/metadata while retaining today's page ID, Space, parent, creation date and trash state. It also retains the current revision/modified date until edit() detects an actual storage change; equal-content retries do not publish a new version. Real changes still preserve the current page as a historical baseline in the same atomic commit.

Five permanent regressions verify missing/corrupt media rejection, unchanged model/disk and no notification on failure, unchanged trash hierarchy, no-op retries, and exact Unicode/CRLF/block/media restoration followed by return to the newer baseline and durable reopen. This preserves the existing history semantics for title/tags/favorite/goal/rules/purpose and changes only lifecycle/organizational handling and resource admission.

This is Core/model/disk evidence; native compare/restore interaction, undo/redo across all editor/AI/media operations, physical Files coordination, CloudKit collaboration and current-source TestFlight remain separate gates. No source change to the existing history UI, permission action, provisioning or upload occurred. R01-R15 remain binding and are not closed by these checks.

Final integration: 574 Swift Testing headline with three optional external/native skips; all 58 XCTest checks pass. Unsigned iOS Release and Debug Simulator builds succeed. FULL_TESTS.txt, SOURCE_HASHES.json and both compile receipts preserve the scoped evidence.
