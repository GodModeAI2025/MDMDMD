# Creation save status

2026-10-11, base e9ae20e. A real missing-Space creation failure leaves saveError set. A later valid createPage/createSpace succeeds on disk, but previously left that old error visible and never published lastSaved. The controlled regression failed with four issues across two cases before the correction.

Successful creation now reloads the stored result, publishes the last save time and clears the obsolete error. These assignments occur only after the store call succeeds; failed writes retain their error. The test uses a real temporary LibraryStore and reopens it to verify each created UUID rather than treating an in-memory success as proof of persistence.

AtomicWritingPageTests passes with six test headlines, including the new two-case regression. The full WorkspaceModel suite passes with 200 headlines, including three explicitly skipped optional checks. The unsigned iOS Release build completed with exit 0. verification.json binds source and logs. No changes were made to text, block identity, revision conflict checks or navigation.

The parallel native writing pass installed e9ae20e before this two-line model change. Its regular writing observations must be attributed to that installed source; they do not independently verify the new error/status publication. No extra app installation is inferred.

Fresh local profile metadata still contains only the original Scriptum development and Store profiles with PCC and no iCloud/CloudKit/Push grants. local-profiles.json records the exact hashes and extraction scope; CMS signature/trust was not verified by that metadata read. No portal capability, provisioning, signed archive, upload, TestFlight group or Apple submission was changed. The complete R01-R15 and release goal remains active.
