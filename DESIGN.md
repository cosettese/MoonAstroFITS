# MoonAstroFITS design

## Boundary

The core package owns bounded byte parsing, FITS structure, numeric semantics,
validation, and deterministic encoding. Filesystem access, network transport,
plotting, and application-specific astronomy analysis remain adapters.

## Initial invariants

1. Every header record is exactly 80 printable ASCII bytes.
2. A header ends at the first valid `END` card.
3. Bytes after `END` up to the 2880-byte boundary are spaces.
4. Card order and repeated commentary keywords are preserved.
5. A slash inside a quoted string does not begin a comment.
6. Public offsets are absolute byte offsets into the supplied input.

The parser returns lexical card values first. Typed HDU validation interprets
only the standard keywords it owns, leaving convention-specific metadata
available without silently rewriting it.
