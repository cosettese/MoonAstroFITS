# MoonAstroFITS

[![CI](https://github.com/cosettese/MoonAstroFITS/actions/workflows/ci.yml/badge.svg)](https://github.com/cosettese/MoonAstroFITS/actions/workflows/ci.yml)

MoonAstroFITS is a pure MoonBit toolkit for reading, validating, and eventually
writing Flexible Image Transport System (FITS) astronomy data. The reusable
core is byte-oriented and does not depend on a filesystem or foreign runtime,
so the same parser can run on MoonBit's portable targets.

## Implemented

- strict 80-byte FITS card parsing;
- `= ` value indicators, undefined values, comments, and commentary cards;
- quoted string awareness when separating values from comments;
- ordered and repeated header keywords;
- `END` detection and 2880-byte header padding validation;
- source-aware structural errors;
- parsing from byte zero or an explicit absolute offset.
- primary and extension HDU traversal with absolute byte boundaries;
- required `SIMPLE`/`XTENSION`, `BITPIX`, `NAXIS`, and `NAXISn` ordering;
- checked image geometry and 2880-byte data-unit padding;
- overflow and truncated-payload rejection before data access.
- big-endian 8/16/32/64-bit integer image decoding;
- explicit `BSCALE`, `BZERO`, and `BLANK` physical-value semantics.
- big-endian IEEE binary32/binary64 image decoding;
- preservation of floating-point NaN, infinities, and signed zero.
- deterministic 80-byte card and 2880-byte header encoding;
- lexical `parse → encode → parse` header round trips.
- range-checked big-endian integer pixel encoding;
- byte-exact integer `encode → decode` round trips.
- IEEE binary32/binary64 pixel encoding with big-endian output;
- binary32 finite-overflow rejection and floating `encode → decode` tests.
- complete primary-HDU assembly with exact payload-length validation;
- standards-aligned space header padding and zero data padding.
- IMAGE and generic extension-HDU assembly;
- required extension keyword ordering and parameter-byte sizing.

Run the checks and the in-memory example:

```bash
moon check --deny-warn
moon test --deny-warn
moon run cmd/main
```

The next milestones will add scientific binary-table schemas and row decoding.

## Scope and origin

This is an original MoonBit implementation based on the public
[FITS Standard 4.0](https://fits.gsfc.nasa.gov/fits_standard.html). It is not a
port and currently includes no copied third-party source or data fixtures.

See [ECOSYSTEM.md](ECOSYSTEM.md) for the dated public overlap check and
[DESIGN.md](DESIGN.md) for format invariants.

## License

Apache-2.0.
