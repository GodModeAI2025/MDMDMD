# Visible link and image prose in proofreading

15 October 2026. Source baseline: `b45ef95db1515956448545be8b223ae2daf7d2b1`.

## Defect and correction

The Markdown projection first admitted parsed text leaves, but a later expression masked complete inline links and images, including visible labels and image descriptions. As a result, ordinary label prose could not be checked or corrected. The local duplicate-word reviewer missed `the the` inside a link. Fixed regression tests reproduced these failures before the implementation changed.

The supplementary whole-link mask is removed. Parsed destinations, titles, reference definitions, code and other syntax retain their existing protection. The correction path still checks the original revision, exact original bytes, UTF-16 boundaries and the reparsed structural signature. Changes that would break implicit reference links or introduce Markdown syntax are rejected.

Source spellings of character references do not have the same offsets as decoded visible text. The projection conservatively protects entity-like spellings and adjacent Unicode letter, mark and number fragments, preventing false spelling findings on fragments such as `caf` from `caf&eacute;`. Matching starts at a literal ampersand; the adjacent fragments are traversed by Unicode scalar. This also protects unknown entity-like names. It does not decode entities or provide a universal linguistic word-boundary model.

The source-offset reasoning was checked against the primary [CommonMark character-reference specification](https://spec.commonmark.org/0.31.2/#entity-and-numeric-character-references). The application behavior is established by the retained tests, not by that specification alone.

## Verification

- `red-with-entities.log`: five fixed regression definitions, 24 parameterized cases, 38 recorded issues, terminal exit 1. `before-hashes.json` binds the old implementation and the exact final `LinkProseReviewTests.swift`; the regression file is byte-identical between this RED run and the final checked source.
- `quality-full.log`: the final ampersand/scalar implementation passes all 73 quality test definitions, 113 executed cases, no skips; terminal exit 0. This includes 16 valid link/image forms, protected destinations/titles/code/autolinks, implicit references, Unicode/CRLF, exact byte preservation, stale revisions and five encoded-character forms.
- `encoded-boundaries.log`: two additional definitions, five executed cases, no skips; terminal exit 0. These cover adjacent references, combining marks, non-BMP letters, a 100,000-character plain word and 4,000 encoded tokens, followed by an exact-offset correction. The recorded host test duration was 0.408 seconds, not an iPhone performance measurement.
- The first focused GREEN run used an intermediate expression and is retained only in `work/quality-link-prose-20261015/green.log`. It is not the final implementation evidence. Earlier partial RED attempts and the compiler-cache sandbox failure remain in the same work directory; the cache failure was not a test failure.
- Independent source review informed the entity protection. `git diff --check` passed. Final source hashes, test counts and terminal identifiers are recorded in `RESULTS.json`.

The final source therefore has 75 quality test definitions covered by the two successful runs above. The extra boundary test file was added after the full 73-definition run; a single combined 75-definition execution is not claimed. Tests use the local macOS Swift package and Testing Library 2084.

## Reproduction and limits

From the repository root, `swift test --filter SkriptumWritingQualityTests` runs the current quality suite. The focused filters are `LinkProseReviewTests` and `EncodedProseBoundaryTests`. The normal compiler-cache permissions are required in this host environment.

No Xcode project approval, fresh iOS SDK build, app/simulator execution, signed archive or TestFlight delivery occurred for this change. The previously archived iOS 1.0.1 (15) remains bound to commit `f2ee2b0e97ef138bf10313480fd128e7bdc053a2` and does not contain this correction. This work does not prove the launch-button flow or live iCloud synchronization.
