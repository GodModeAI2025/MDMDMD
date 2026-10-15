# Independent source review

Reviewer: `/root/native_grammar_gap`, 15 October 2026.

Reviewed `QualityCore.swift` with SHA256 `93976953b58a206bc34db42f93aa119fd8c14c82e74456e17c7a6a3330de6ce6`. No remaining concrete regression was found in the reviewed diff.

The entity expression starts at a literal ampersand. Adjacent Unicode letters, combining marks and numbers are extended through scalar boundaries and masked as UTF-16 ranges. Destinations, titles, code, autolinks and the existing correction admission checks remain protected.

This is a conservative source projection, not an entity decoder or complete language-specific word segmentation. The review is static; execution, performance and test results are separate evidence in REPORT.md and RESULTS.json. The reviewer made no code changes and ran no tests during this final review.
