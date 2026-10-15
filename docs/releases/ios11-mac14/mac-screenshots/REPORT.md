# Final actual native Mac Store captures

2026-10-15 · actual main native Mac Debug app **1.0.1 (14)**, confirmed from the live app bundle before launch and at packaging. The earlier Build13 attempt remains separate and is not relabeled.

Both final raw native captures are exactly **2560×1600 pixels**, matching the requested accepted 16:10 size set. Light and dark writing states were inspected visually and their live AX hierarchies retained. The actual native window was set to 1280×800 points including titlebar by the reviewed DEBUG-only own-window QA helper, guarded by valid QA root, nonprimary library UUID, and explicit screenshot flag. No manual sizing loop needed in this final run.

Files: `01-writing-light.jpg/.png/.txt`, `02-writing-dark.jpg/.png/.txt`. Original JPEG bytes are unchanged. PNG copies use native sips format conversion only: no bitmap resizing, cropping, redraw, annotation, pointer removal, or OS-sharing-indicator removal. The purple OS window-sharing indicator and visible pointer are preserved as actually captured. This demonstrates dimensions and actual UI, not Apple editorial approval or upload success. Parent retains selection/upload responsibility.

Only own synthetic Markdown page was shown in new isolated root mac-store-final-20261015, nonprimary UUID 27031554-421B-4DFD-9292-FD7C25C10C68. SCRIPTUM_FAKE_AI=1 supplied as safety; no assistant opened, no provider request, no iCloud activation. Original source after capture exactly matches the 151 UTF-8-byte fixture including final newline; comparison and native AX value retained.

System appearance and writing mode restored. Own PID 73447 ended with Cmd-Q, then no Scriptum process remained. CUA released to parent. No source edits, project changes, builds, scheme changes, Git mutations, portals, or release actions by this verifier. Artifacts remain outside Git. MANIFEST.json records actual dimensions, bundle metadata, and raw/PNG hashes; SHA256SUMS covers all files.
