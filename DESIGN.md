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
7. HDU size arithmetic is checked before any data-unit access.
8. The parser consumes the entire block-aligned input as an ordered HDU list.

The parser returns lexical card values first. Typed HDU validation interprets
only the standard keywords it owns, leaving convention-specific metadata
available without silently rewriting it.

## HDU geometry

The first HDU must begin with `SIMPLE`; later HDUs begin with `XTENSION`.
`BITPIX`, `NAXIS`, and each `NAXISn` card are position-sensitive because their
ordering is part of the FITS standard. Data length uses the general
`abs(BITPIX) / 8 * GCOUNT * (PCOUNT + product(NAXISn))` rule with checked
integer arithmetic. Primary arrays and `IMAGE` extensions expose an
`ImageLayout`; other extension types remain traversable without pretending
their cells are image pixels.
