///|
/// One 80-byte FITS header card.
///
/// `value` is the trimmed lexical value after the `= ` indicator. An empty
/// string represents the standard's undefined value. Cards without a value
/// indicator use `None` and can retain commentary in `comment`.
pub(all) struct Card {
  keyword : String
  value : String?
  comment : String?
  record_index : Int
} derive(Eq, Debug)

///|
/// A parsed FITS header and the absolute offset of its following data unit.
pub(all) struct Header {
  cards : Array[Card]
  data_offset : Int
} derive(Eq, Debug)

///|
/// The structural role of one FITS header/data unit.
pub(all) enum HduKind {
  Primary
  ImageExtension
  OtherExtension(String)
} derive(Eq, Debug)

///|
/// Checked geometry for a primary array or IMAGE extension.
pub(all) struct ImageLayout {
  bitpix : Int
  axes : Array[Int]
  pixel_count : Int
  byte_length : Int
} derive(Eq, Debug)

///|
/// One parsed FITS header/data unit with absolute byte boundaries.
pub(all) struct Hdu {
  index : Int
  kind : HduKind
  header : Header
  image : ImageLayout?
  data_offset : Int
  data_length : Int
  next_hdu_offset : Int
} derive(Eq, Debug)

///|
/// A structurally validated sequence of FITS HDUs.
pub(all) struct FitsFile {
  hdus : Array[Hdu]
} derive(Eq, Debug)

///|
/// Decoded integer image samples and their FITS linear-scaling metadata.
pub(all) struct IntegerImage {
  axes : Array[Int]
  raw : Array[Int64]
  bscale : Double
  bzero : Double
  blank : Int64?
} derive(Eq, Debug)

///|
/// Convert every non-blank raw sample to its physical FITS value.
pub fn IntegerImage::physical_values(self : IntegerImage) -> Array[Double?] {
  self.raw.map(fn(value) {
    match self.blank {
      Some(blank) if value == blank => None
      _ => Some(value.to_double() * self.bscale + self.bzero)
    }
  })
}

///|
/// Decoded IEEE floating-point image samples and FITS linear scaling.
pub(all) struct FloatingImage {
  axes : Array[Int]
  raw : Array[Double]
  bscale : Double
  bzero : Double
} derive(Eq, Debug)

///|
/// Apply FITS linear scaling while preserving IEEE special values.
pub fn FloatingImage::physical_values(self : FloatingImage) -> Array[Double] {
  self.raw.map(fn(value) { value * self.bscale + self.bzero })
}

///|
/// The fixed-width storage representation of one FITS binary-table column.
pub(all) enum TableColumnKind {
  Ascii
  Logical
  UnsignedByte
  Int16
  Int32
  Int64
  Float32
  Float64
} derive(Eq, Debug)

///|
/// A validated fixed-width FITS binary-table column.
pub(all) struct TableColumn {
  index : Int
  name : String?
  format : String
  repeat : Int
  offset : Int
  width : Int
  kind : TableColumnKind
} derive(Eq, Debug)

///|
/// Row geometry and column schema for a fixed-width BINTABLE extension.
pub(all) struct BinaryTable {
  columns : Array[TableColumn]
  row_length : Int
  row_count : Int
  data_offset : Int
} derive(Eq, Debug)

///|
/// One decoded fixed-width binary-table cell.
pub(all) enum TableValue {
  Text(String)
  Logicals(Array[Bool?])
  Integers(Array[Int64])
  Reals(Array[Double])
} derive(Eq, Debug)

///|
/// Source-aware failures from FITS structural parsing.
pub(all) enum FitsError {
  Truncated(Int, Int, Int)
  NonAscii(Int, Byte)
  InvalidKeyword(Int, String)
  InvalidCard(Int, String)
  MissingEnd(Int)
  InvalidPadding(Int, Byte)
  MissingKeyword(String)
  InvalidInteger(String, String)
  InvalidLogical(String, String)
  InvalidString(String, String)
  InvalidRequiredOrder(Int, String, String)
  UnsupportedBitpix(Int)
  InvalidAxis(Int, Int)
  InvalidParameter(String, Int)
  SizeOverflow(String)
  NotImageHdu(Int)
  UnsupportedIntegerBitpix(Int)
  UnsupportedFloatingBitpix(Int)
  UnsupportedImageLayout(Int)
  InvalidReal(String, String)
  CardTooLong(Int, Int)
  InvalidSampleCount(Int, Int)
  PixelOutOfRange(Int, Int64, Int)
  BlankOutOfRange(Int64, Int)
  FloatingPixelOverflow(Int, Int)
  InvalidDataLength(Int, Int)
  NotBinaryTable(Int)
  UnsupportedTableFormat(String, String)
  InvalidTableRowWidth(Int, Int)
  TableRowOutOfRange(Int, Int)
  InvalidTableRowCount(Int, Int)
  InvalidTableCellCount(Int, Int)
  InvalidTableCell(Int, String)
} derive(Eq, Debug)

///|
pub fn FitsError::message(self : FitsError) -> String {
  match self {
    Truncated(offset, needed, available) =>
      "truncated FITS data at byte \{offset}: need \{needed} bytes, have \{available}"
    NonAscii(offset, byte) =>
      "non-ASCII byte \{byte.to_int()} in FITS header at byte \{offset}"
    InvalidKeyword(record, keyword) =>
      "invalid FITS keyword '\{keyword}' in header record \{record + 1}"
    InvalidCard(record, reason) =>
      "invalid FITS card in header record \{record + 1}: \{reason}"
    MissingEnd(offset) =>
      "FITS header starting at byte \{offset} has no END card"
    InvalidPadding(offset, byte) =>
      "invalid FITS header padding byte \{byte.to_int()} at byte \{offset}"
    MissingKeyword(keyword) => "required FITS keyword '\{keyword}' is missing"
    InvalidInteger(keyword, value) =>
      "FITS keyword '\{keyword}' does not contain an integer: '\{value}'"
    InvalidLogical(keyword, value) =>
      "FITS keyword '\{keyword}' does not contain a logical value: '\{value}'"
    InvalidString(keyword, value) =>
      "FITS keyword '\{keyword}' does not contain a valid quoted string: '\{value}'"
    InvalidRequiredOrder(record, expected, found) =>
      "FITS header record \{record + 1} must be '\{expected}', found '\{found}'"
    UnsupportedBitpix(value) => "unsupported FITS BITPIX value \{value}"
    InvalidAxis(axis, value) =>
      "FITS NAXIS\{axis} must be non-negative, got \{value}"
    InvalidParameter(keyword, value) =>
      "FITS keyword '\{keyword}' has invalid value \{value}"
    SizeOverflow(context) => "FITS \{context} exceeds addressable input size"
    NotImageHdu(index) => "FITS HDU \{index} is not an image"
    UnsupportedIntegerBitpix(value) =>
      "FITS BITPIX \{value} is not an integer pixel representation"
    UnsupportedFloatingBitpix(value) =>
      "FITS BITPIX \{value} is not an IEEE floating-point representation"
    UnsupportedImageLayout(index) =>
      "FITS HDU \{index} uses random groups or parameters and cannot be decoded as a contiguous image"
    InvalidReal(keyword, value) =>
      "FITS keyword '\{keyword}' does not contain a finite real value: '\{value}'"
    CardTooLong(record, length) =>
      "encoded FITS header record \{record + 1} is \{length} bytes; maximum is 80"
    InvalidSampleCount(expected, actual) =>
      "FITS image shape requires \{expected} samples, got \{actual}"
    PixelOutOfRange(index, value, bitpix) =>
      "pixel \{index} value \{value} is outside the BITPIX=\{bitpix} range"
    BlankOutOfRange(value, bitpix) =>
      "BLANK value \{value} is outside the BITPIX=\{bitpix} range"
    FloatingPixelOverflow(index, bitpix) =>
      "pixel \{index} is finite but overflows BITPIX=\{bitpix}"
    InvalidDataLength(expected, actual) =>
      "FITS header requires \{expected} data bytes, got \{actual}"
    NotBinaryTable(index) => "FITS HDU \{index} is not a binary table"
    UnsupportedTableFormat(keyword, format) =>
      "FITS keyword '\{keyword}' uses unsupported binary-table format '\{format}'"
    InvalidTableRowWidth(expected, actual) =>
      "FITS binary-table row declares \{expected} bytes but its columns occupy \{actual}"
    TableRowOutOfRange(index, count) =>
      "FITS binary-table row \{index} is outside the \{count}-row table"
    InvalidTableRowCount(expected, actual) =>
      "FITS binary table requires \{expected} rows, got \{actual}"
    InvalidTableCellCount(expected, actual) =>
      "FITS binary-table row requires \{expected} cells, got \{actual}"
    InvalidTableCell(column, reason) =>
      "invalid FITS binary-table column \{column}: \{reason}"
  }
}
