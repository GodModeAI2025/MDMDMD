# Keep headings with adjacent paragraph starts

The semantic renderer supplies the first text fragment of an adjacent same-indent paragraph as heading lookahead. The document writer measures the entire heading, its paragraph spacing and up to three following lines, reserves them before drawing and promotes the heading if necessary. The following paragraph explicitly requires its first fragment on the same page. Impossible grouping is rejected rather than silently separating the heading. Named destinations remain tied to the first actual drawn line.

Evidence: 69 export tests pass. A real PDFKit before/after regression places a heading alone on page zero without keep, then verifies heading and body together on page one with keep, retaining all ten foxes. A semantic traversal regression verifies the integration. Planner tests verify forced first-fragment placement and failure when less than the orphan minimum fits. One initial planner test expected the ordinary optimizer to move the paragraph, but its actual policy already preferred the current page; that incorrect expectation was corrected and the explicit insufficient-room case added.

Direct unsigned Xcode simulator build passed for final production source (arm64/x86_64), terminal exit 0 and BUILD SUCCEEDED; work/pdf-heading-keep-xcode-final.log. Test-only expectations were refined afterward and the export suite rerun.

Scope: applies to an immediately adjacent same-indent paragraph whose first inline fragment is text. Heading chains, following images/tables/containers, image-only headings, unequal indentation and over-page heading groups require further policy. Active app PDF route remains WebKit. Tables and tagged accessibility remain open; no native app export or TestFlight delivery claim.
