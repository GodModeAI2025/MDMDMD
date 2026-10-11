# Regular workspace and metadata conflict verification

2026-10-11. Follow-up to [WWDC writing improvements](../WWDC_WRITING_IMPROVEMENTS_20261011.md), implementation base af6ddfd. Native observations use the ordinary app in Debug, without QA launch arguments, on a newly created empty iPhone 17 Pro Max simulator. No private files, accounts, inference or portal changes were involved.

The cold start, paper background, actual library/sidebar, welcome-page detail, back navigation and stable page-list toolbar were captured. An initial Space creation failed with persistent `LibraryError 21` (`revisionConflict`); its screenshot and hierarchy are preserved. A diagnostic cold restart subsequently allowed Space creation. The original failing stat delta was not captured: this is not proof that its cause was metadata alone.

A separate controlled regression establishes a real metadata false conflict: chmod changes ctime while inode, file size, mtime and exact bytes stay unchanged. The previous implementation rejected the next mutation. The store now remembers a SHA256 digest of its loaded/committed bytes. Only a ctime-only change on the same inode/size/mtime can trigger a bounded, descriptor-based hash comparison. The ordinary unchanged-stat path does not reread the library. File replacement, content changes and changes during the comparison remain conflicts. The temporary diagnostic print is removed.

Three new tests cover admitted metadata changes, same-size external content with exactly restored mtime, and an atomic replacement containing identical bytes. Six existing concurrent-writer/journal/lock tests remain green. A failed write leaves the in-memory snapshot, external bytes and observer notifications untouched. These checks do not promise safety against a noncooperative writer modifying the file after validation; library mutations retain their cooperative cross-process lock.

The targeted nine tests and full suite completed with exit 0: 649 Swift Testing headline tests including four optional skips, plus 58 XCTest. The unsigned iOS Release build also completed with exit 0. verification.json binds the source files and logs. Native observations before this storage correction are not a runtime verification of its new hash fallback.

Regular text editing/reopen, VoiceOver, Dynamic Type, resize/multiwindow, supported Image Playground generation, live provider quality, iCloud two-device collaboration, signed release and current-source TestFlight delivery remain separate acceptance gates.
