# Composite Markdown writing presentation — open R02/R11 work

A valid imported manuscript can retain several Markdown sections inside one original block. BlockProjection currently detects multiple AST children and exposes a reversible raw-source projection. This prevents the old first-heading classification from styling the whole manuscript as a heading, but the writing view still renders the entire imported block in body-size monospaced source presentation. That is an incomplete professional writing experience, not final rich composite rendering.

## Implementation contract

Keep each original block UUID, Markdown byte sequence, line ending, image/reference target, comment anchor and revision unchanged merely by displaying, focusing, reflowing or changing writing preferences. Do not split or rewrite existing blocks during read. Keep the separate full Markdown source mode. Derive composite presentation from the already pinned official Swift Markdown AST, rather than an independent regex interpretation.

Create a source-backed presentation plan whose UTF-16 runs distinguish headings, prose, code and inline emphasis. Map parser UTF-8 line/column ranges to the unchanged source with checked bounds, CRLF and Unicode tests. Formatting changes attributes only; source text and selection stay authoritative. Invalid or unavailable presentation cannot erase or normalize input. Present headings at their own levels and paragraphs with the selected writing font; code remains monospace.

Use the same presentation semantics for inactive rows and active TextKit editing. Preserve marked-text composition, typing attributes, selection, native Undo/Redo and existing command/line-style admission. Dynamic Type and writing font/spacing preferences remain effective. Parsing and caching must not block every keystroke on the main actor or leave concurrent obsolete parsers running for a large imported block. Fence deferred results against exact source and view generation.

## Required evidence

Core run/range tests for multi-section single-block imports, nested prose/code, inline emphasis, non-BMP/decomposed Unicode, CRLF and malformed Markdown. Native editing checks must show distinct heading/body typography, typing and byte-exact Undo without changing the single original block UUID. Include a real large-manuscript interaction measurement, not just parser count tests. Phone/iPad and composition/keyboard checks are required; a small model test alone does not complete R02/R11.

This document records the next implementation contract. No composite-rendering implementation or completion is claimed here.
