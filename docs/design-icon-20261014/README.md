# Scriptum icon refinement

Built-in imagegen edited the existing handwritten S and ink spots. The requested change was an app-appropriate background: a restrained warm stone-paper surface for the light icon and warm charcoal/ivory for dark appearance. The former source is retained as previous-icon.png. Full generated originals are retained here; sips produces only the platform-required raster sizes in the asset catalog. No hand-edited or simulated replacement artwork is used.

Light prompt: preserve the existing S silhouette, central placement, deep ink navy and two ink spots; change the bright yellowish textured paper to uniform warm stone-paper around #E6E0D6 with almost imperceptible fine texture. No yellow cast, glow, strong shadows, vignette, border, rounded frame, extra text or objects. Fully opaque square.

Dark prompt: preserve the light icon's silhouette, spots, size and placement; use warm charcoal around #1B1A18 and warm ivory around #F2EADC with high small-size contrast. No glow, halo, vignette, border, exterior shadow or extra objects. Fully opaque square.

Generated images were visually inspected before sizing. iOS uses 1024-point light and dark asset variants; the native macOS target has dedicated macOS icon sizes. Final compiled-asset and release validation belong in the build-specific QA report.
