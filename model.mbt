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
  }
}
