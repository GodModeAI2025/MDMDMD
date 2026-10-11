# Glyph ownership investigation: not accepted

The attempted marked-run renderer attached shaped glyph sequences and annotation OBJRs to the same logical Link. Structural tests passed and all100foxes remained extractable. Independent inspection found300marked sequences/200annotation references for the long link and1/1for the second link. This did not establish unchanged drawing.

Poppler comparisons across all five pages found differences in the color-emoji column. The first image x changed from129.4785points with CTLineDraw to130with CTRunDraw. Reproduced using the exact same immutable attributed-string/font snapshot in the same test process. Font subpixel-positioning/quantization settings did not remove it. A direct CTFontDrawGlyphs candidate incorrectly combined user-space positions with existing text state, placed images beyond the page and failed native Unicode assertions; it was not accepted.

The code changes were restored to the existing whole-line CTLineDraw implementation. EXPERIMENT.patch retains the final nonaccepted candidate for investigation only and is not applied. Existing standard labels, logical link identities, OBJRs and all committed structure code remain. Link glyph ownership is still open and no new accessibility completion is claimed. Current app export remains WebKit.

Relevant primary API contracts inspected:
- Apple CTRunDraw can leave the graphics context in any state: https://developer.apple.com/documentation/coretext/ctrundraw(_:_:_:)
- Apple CTFontDrawGlyphs positions/state contract: https://developer.apple.com/documentation/coretext/ctfontdrawglyphs(_:_:_:_:_:)
The experiment does not prove an SDK defect or a generally correct compensation formula. Next work must preserve color-font drawing and text semantics before adopting per-run ownership; arbitrary fixed shifts are not a validated fix.

After restoration, the existing focused wrapped-link regression passed. All five re-rendered restored pages are pixel-identical to the earlier accepted whole-line reference, recorded in RESTORED_RENDER.json. No production source changes are included in this investigation commit. The previous unsigned simulator build of the first structural experiment succeeded, but that does not validate the rejected drawing change; no new accepted Release/native export proof is claimed.
