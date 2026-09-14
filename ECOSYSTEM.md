# Ecosystem position

Checked on 2026-09-14 before implementation.

Searches on mooncakes.io for `fits`, `cfitsio`, `astropy fits`, `BITPIX`,
`NAXIS`, `HDU astronomy`, `bintable`, `FITS parser`, and `FITS validator` found
no published MoonBit FITS parser, writer, or validator. GitHub repository and
MoonBit source searches for the same domain terms likewise found no public
implementation.

The closest general-purpose packages provide numeric arrays, filesystem I/O,
or unrelated image handling. MoonAstroFITS adds the missing format boundary:
FITS cards, HDUs, astronomy image values, tables, validation, and interchange.

Because public ecosystems change, this document records a dated check rather
than claiming permanent uniqueness. New overlap should be evaluated by public
API and workflow coverage before expanding the roadmap.
