# Scriptum native Mac 1.0.1 (10)

UI source: `429cb11`. [Visual audit](../../qa-mac-ui-20261014/REPORT.md). This release updates the native Mac workspace, navigation, writing presentation and inspector. iOS build 9 is not replaced by this Mac-only release.

The exported Mac package passed all 28 distribution checks. Upload and Apple processing/compliance are confirmed. Build 10 shows **Im Test** in **Mark – Intern** (one tester), and was submitted on 15 October at 00:01 CEST: **Waiting for Review**, automatic release after Apple approval. [Submission receipt](mac-app-review-submitted.jpg), [internal testing receipt](testflight-im-test.jpg), structured details in `STATE.json`. It is not approved or published. Mac build 9's old review submission was withdrawn; iOS build 9 remains in its original Waiting for Review submission.

Store screenshots are real captures of the running Mac app with an isolated demonstration library. The original 2360×1600 captures are retained in the visual audit directory. To meet Apple’s 2560×1600 size, only bottom whitespace was cropped (top offset 1, crop 2360×1475), followed by uniform resizing to 2560×1600. No interface content was generated or composited.

The signed archive and local PKG remain under `work/release-build10/`. Prior archives, review evidence and source captures are preserved. Live multi-device iCloud and live PCC are not proven by signing checks.
