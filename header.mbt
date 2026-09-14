///|
let fits_card_size : Int = 80

///|
let fits_block_size : Int = 2880

///|
fn is_fits_keyword_char(ch : Char) -> Bool {
  (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch == '-' || ch == '_'
}

///|
fn ascii_slice(
  data : Bytes,
  start : Int,
  end : Int,
) -> Result[String, FitsError] {
  let out = StringBuilder()
  for index = start; index < end; index = index + 1 {
    let byte = data[index]
    let value = byte.to_int()
    if value < 0x20 || value > 0x7e {
      return Err(NonAscii(index, byte))
    }
    out.write_char(value.to_char().unwrap())
  }
  Ok(out.to_string())
}

///|
fn fits_trim(input : String) -> String {
  input.trim(chars=" ").to_owned()
}

///|
fn fits_trim_end(input : String) -> String {
  input.trim_end(chars=" ").to_owned()
}

///|
fn split_value_comment(input : String) -> (String, String?) {
  let chars = input.to_array()
  let mut quoted = false
  let mut index = 0
  while index < chars.length() {
    if chars[index] == '\'' {
      if quoted && index + 1 < chars.length() && chars[index + 1] == '\'' {
        index = index + 2
        continue
      }
      quoted = !quoted
    } else if chars[index] == '/' && !quoted {
      let value = StringBuilder()
      for position = 0; position < index; position = position + 1 {
        value.write_char(chars[position])
      }
      let comment = StringBuilder()
      for position = index + 1
          position < chars.length()
          position = position + 1 {
        comment.write_char(chars[position])
      }
      let comment_text = fits_trim(comment.to_string())
      return (
        fits_trim(value.to_string()),
        if comment_text == "" {
          None
        } else {
          Some(comment_text)
        },
      )
    }
    index = index + 1
  }
  (fits_trim(input), None)
}

///|
fn validate_keyword(
  keyword : String,
  record_index : Int,
) -> Result[Unit, FitsError] {
  if keyword == "" {
    return Ok(())
  }
  for ch in keyword {
    if !is_fits_keyword_char(ch) {
      return Err(InvalidKeyword(record_index, keyword))
    }
  }
  Ok(())
}

///|
fn parse_card(
  data : Bytes,
  offset : Int,
  record_index : Int,
) -> Result[Card, FitsError] {
  let keyword = match ascii_slice(data, offset, offset + 8) {
    Err(error) => return Err(error)
    Ok(text) => fits_trim_end(text)
  }
  match validate_keyword(keyword, record_index) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let has_value = data[offset + 8] == b'=' && data[offset + 9] == b' '
  if keyword == "END" {
    if has_value {
      return Err(
        InvalidCard(record_index, "END must not have a value indicator"),
      )
    }
    let trailing = match
      ascii_slice(data, offset + 8, offset + fits_card_size) {
      Err(error) => return Err(error)
      Ok(value) => fits_trim(value)
    }
    if trailing != "" {
      return Err(InvalidCard(record_index, "END must not have a comment"))
    }
  }
  if has_value {
    let field = match ascii_slice(data, offset + 10, offset + fits_card_size) {
      Err(error) => return Err(error)
      Ok(text) => text
    }
    let (value, comment) = split_value_comment(field)
    Ok({ keyword, value: Some(value), comment, record_index, })
  } else {
    let text = match ascii_slice(data, offset + 8, offset + fits_card_size) {
      Err(error) => return Err(error)
      Ok(value) => fits_trim(value)
    }
    Ok({
      keyword,
      value: None,
      comment: if text == "" {
        None
      } else {
        Some(text)
      },
      record_index,
    })
  }
}

///|
fn padded_block_length(length : Int) -> Int {
  (length + fits_block_size - 1) / fits_block_size * fits_block_size
}

///|
/// Parse a FITS header at byte zero.
pub fn parse_header(data : Bytes) -> Result[Header, FitsError] {
  parse_header_at(data, 0)
}

///|
/// Parse a FITS header at an absolute byte offset.
pub fn parse_header_at(data : Bytes, start : Int) -> Result[Header, FitsError] {
  if start < 0 || start > data.length() {
    return Err(Truncated(start, fits_card_size, 0))
  }
  let cards = []
  let mut record_index = 0
  while true {
    let offset = start + record_index * fits_card_size
    if offset + fits_card_size > data.length() {
      return Err(MissingEnd(start))
    }
    let card = match parse_card(data, offset, record_index) {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    cards.push(card)
    record_index = record_index + 1
    if card.keyword == "END" {
      let header_length = padded_block_length(record_index * fits_card_size)
      let data_offset = start + header_length
      if data_offset > data.length() {
        return Err(Truncated(start, header_length, data.length() - start))
      }
      let content_end = start + record_index * fits_card_size
      for index = content_end; index < data_offset; index = index + 1 {
        if data[index] != b' ' {
          return Err(InvalidPadding(index, data[index]))
        }
      }
      return Ok({ cards, data_offset, })
    }
  } nobreak {
    Err(MissingEnd(start))
  }
}

///|
/// Return the first card with the requested keyword.
pub fn Header::get(self : Header, keyword : String) -> Card? {
  for card in self.cards {
    if card.keyword == keyword {
      return Some(card)
    }
  }
  None
}

///|
/// Return every card with the requested keyword in source order.
pub fn Header::get_all(self : Header, keyword : String) -> Array[Card] {
  let found = []
  for card in self.cards {
    if card.keyword == keyword {
      found.push(card)
    }
  }
  found
}
