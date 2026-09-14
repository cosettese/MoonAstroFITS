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

Run the checks and the in-memory example:

```bash
moon check --deny-warn
moon test --deny-warn
moon run cmd/main
```

The next milestones will validate HDU image geometry, decode typed big-endian
pixel arrays, and add deterministic writing and scientific table support.

## Scope and origin

This is an original MoonBit implementation based on the public
[FITS Standard 4.0](https://fits.gsfc.nasa.gov/fits_standard.html). It is not a
port and currently includes no copied third-party source or data fixtures.

See [ECOSYSTEM.md](ECOSYSTEM.md) for the dated public overlap check and
[DESIGN.md](DESIGN.md) for format invariants.

## License

Apache-2.0.
