# Independent attachment unavailable-file classification review

**PASS for correctness and scoped security**, reviewed frozen diff after370587b.

The audit preserves the typed thrown error long enough to distinguish actual MediaValidation invalidAttachment rejection from filesystem failures. Confirmed Cocoa/POSIX missing codes remain missingFile; remaining permission/I/O errors now become unavailableFile rather than asserting corruption. The new status appears as 'Datei nicht prüfbar' and remains an issue because existing filtering treats any nonverified state as an issue. Existing warning icon/text styling applies automatically. Unsafe/symlink/corrupt validator failures remain invalid, so this is not a trust or validation relaxation.

Regression test uses actual valid PNG bytes, chmod000, real audit and unavailable assertion, then restores permissions and verifies unchanged bytes. Deferred cleanup restores permission even on failure. Root reports eight targeted Core tests green. POSIX behavior is runtime-dependent (a privileged process can read mode000), but the supplied ordinary macOS execution demonstrates the actual prior permission mechanism rather than a fake error.

No path, ownership, cancellation, snapshot guard, navigation or mutation behavior changed. Existing native16checks apply to370587b, not this new permission state. Final SDK/aggregate tests and native permission-label coverage remain separate evidence; no claim that this scenario was tested on iOS/iPadOS. No source/device mutations during review.
