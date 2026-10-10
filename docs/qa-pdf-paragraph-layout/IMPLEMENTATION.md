# Two-pass paragraph layout

The internal semantic PDF foundations now connect immutable paragraph measurement, widow/orphan planning and streaming shaped lines. Only scalar line metrics remain between passes. The second pass verifies identical metrics and complete contiguous plan coverage before emitting lines.

Validation: 58 export tests passed. The new regression mutates the original attributed string after measurement, preserves all Arabic, combining-character and emoji source text, checks every line index and rejects a truncated plan.

The first test attempt incorrectly retained a mutable NSString reference for the expected text and raised an out-of-bounds exception after deliberately changing that text. The fixture now makes an independent NSString copy; the production snapshot required no correction.

This foundation is not connected to the current app PDF route. Current WebKit PDF Unicode extraction and accessibility defects remain open. No new native app or Release build is claimed for this commit.
