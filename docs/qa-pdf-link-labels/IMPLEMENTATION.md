# Logical wrapped links and readable labels

Inline adaptation assigns each Markdown link an identity and original plain label. Both attributes survive font/style runs and paragraph wrapping. Each text-element structure owner reuses one Link element for that identity across pages; separate inlines sharing a target remain distinct. The Link's standard Alt stores its readable label; URL remains title/context. Figure links use the supplied image description. The SDK AltText key correction now also covers Link dictionaries. Footnote targets clear surrounding link identity and use their reference number to avoid aliasing a different target.

Label extraction is iterative with cancellation checks. It does not use ActualText or replace glyph text. Manual attributed callers without inline identities retain per-rectangle structure and URL fallback labels; they are not silently merged by target.

Evidence:84export tests pass. A real five-page100-line bold/emoji link creates one logical Link with200annotation object references; a separate same-URL inline creates a second Link with one reference. Exact original full label and Another source are present under standard Alt. All201annotations match those references, all100foxes remain and independent strict pypdf emits zero warnings. An initial nested require macro in the test was split before the successful rerun.

Direct unsigned Xcode simulator compilation passed, arm64/x86_64, terminal exit0/BUILD SUCCEEDED (work/pdf-link-label-xcode.log).

Remaining: glyph marked-content ownership inside Link, reading-order/ParentTree/assistive navigation acceptance, links spanning separate text/image fragments, table Scope/Headers, list Lbl and full resource/native/PDF-UA acceptance. Tagged output still defaults off; active app export remains WebKit. No Release archive or TestFlight delivery claim.
