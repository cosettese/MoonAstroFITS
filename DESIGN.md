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

## Integer pixels

`decode_integer_image` reads FITS big-endian integer samples without losing
their stored representation. `BITPIX=8` remains unsigned, while 16/32/64-bit
samples are decoded as signed two's-complement values. `IntegerImage` keeps the
raw values alongside `BSCALE`, `BZERO`, and `BLANK`; callers can request
physical values while blank samples remain distinguishable as `None`.

## Floating-point pixels

`decode_floating_image` handles `BITPIX=-32` and `BITPIX=-64` directly from
their network-order IEEE bit patterns. Binary32 values are widened exactly to
`Double`; binary64 values keep their original representation. Raw NaN,
infinities, and signed zero survive decoding, and `BSCALE`/`BZERO` remain an
explicit physical-value transformation.

## Deterministic headers

`encode_header` serializes the lexical `Card` model without inventing typed
metadata. It uses conventional right alignment for short non-string values,
keeps quoted strings adjacent to the value indicator, rejects lossy truncation
and non-ASCII output, requires a terminal `END`, and pads only with spaces.
Reparsing the result preserves card order, values, and comments.
