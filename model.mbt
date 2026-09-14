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
  }
}
