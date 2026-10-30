# Mac 1.0.2 (38) — layout correction

Submitted again on 30 October 2026 at 12:21 Europe/Berlin. App Store Connect confirms **Warten auf Prüfung** for build 38, replacing rejected build 36 in the same submission. Automatic release after approval remains selected. This is a verified submission, not Apple approval or publication.

Internal TestFlight: **Mark – Intern**, one existing tester, build 38 **Im Test**. No new testers or invitations were created. Export compliance answered consistently with the unchanged OS-provided encryption; no crypto implementation changed.

The one-line product correction makes the Mac writing surface accept available height (`minHeight: 0`). See APPLE_REVIEW.md and qa/VERIFICATION.md for the reproduced clipping, debugger geometry and passing native visual checks. Review Notes and the sent Apple response are retained as exact text files. Portal proof: mac38-waiting-for-review.png and testflight-im-test.png.

Archive/export/upload succeeded. The actual exported package passed all 28 distribution checks; hashes, SDK and source hashes are in provenance.json. Source commit 8d15ed1 contains the archived product change; subsequent commits only retain documentation/evidence. Temporary DEBUG QA launch override was removed before Release. No iOS source/version, cloud, AI, grammar, dependency or privacy behavior changed.

Unchanged broad tests were not rerun. No new physical-device or live cloud/model claim is made. Final public release depends on Apple review.
