///|
fn ascii_text(text : String, record_index : Int) -> Result[Unit, FitsError] {
  for ch in text {
    let value = ch.to_int()
    if value < 0x20 || value > 0x7e {
      return Err(
        InvalidCard(record_index, "encoded text must be printable ASCII"),
      )
    }
  }
  Ok(())
}

///|
fn spaces(count : Int) -> String {
  let output = StringBuilder()
  for index = 0; index < count; index = index + 1 {
    output.write_char(' ')
  }
  output.to_string()
}

///|
fn keyword_field(keyword : String) -> String {
  keyword + spaces(8 - keyword.length())
}

///|
fn canonical_value(value : String) -> String {
  if value == "" || value[0] == '\'' || value.length() >= 20 {
    value
  } else {
    spaces(20 - value.length()) + value
  }
}

///|
fn encode_card_text(
  card : Card,
  record_index : Int,
) -> Result[String, FitsError] {
  if card.keyword.length() > 8 {
    return Err(InvalidKeyword(record_index, card.keyword))
  }
  match validate_keyword(card.keyword, record_index) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if card.keyword == "" && card.value is Some(_) {
    return Err(InvalidCard(record_index, "a blank keyword cannot have a value"))
  }
  let text = match card.value {
    Some(value) => {
      let mut output = keyword_field(card.keyword) +
        "= " +
        canonical_value(value)
      match card.comment {
        None => ()
        Some(comment) => output = output + " / " + comment
      }
      output
    }
    None => {
      let comment = match card.comment {
        None => ""
        Some(value) => value
      }
      keyword_field(card.keyword) + comment
    }
  }
  match ascii_text(text, record_index) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if text.length() > fits_card_size {
    return Err(CardTooLong(record_index, text.length()))
  }
  Ok(text)
}

///|
fn append_ascii(output : Array[Byte], text : String) -> Unit {
  for ch in text {
    output.push(ch.to_int().to_byte())
  }
}

///|
/// Deterministically encode a parsed FITS header.
///
/// Values retain their lexical representation. Non-string values shorter than
/// 20 bytes are right-aligned in the conventional FITS value field; quoted
/// strings begin immediately after `= `. Every card is padded to 80 bytes and
/// the completed header is padded with spaces to a 2880-byte boundary.
pub fn encode_header(header : Header) -> Result[Bytes, FitsError] {
  if header.cards.length() >
    (2147483647 - (fits_block_size - 1)) / fits_card_size {
    return Err(SizeOverflow("encoded header"))
  }
  let output = []
  let mut found_end = false
  for index, card in header.cards {
    if found_end {
      return Err(InvalidCard(index, "cards cannot follow END"))
    }
    if card.keyword == "END" {
      if card.value is Some(_) || card.comment is Some(_) {
        return Err(InvalidCard(index, "END must not have a value or comment"))
      }
      found_end = true
    }
    let text = match encode_card_text(card, index) {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    append_ascii(output, text)
    for position = text.length()
        position < fits_card_size
        position = position + 1 {
      output.push(b' ')
    }
  }
  if !found_end {
    return Err(MissingEnd(0))
  }
  while output.length() % fits_block_size != 0 {
    output.push(b' ')
  }
  Ok(Bytes::from_array(output))
}

///|
fn append_bytes(output : Array[Byte], bytes : Bytes) -> Unit {
  for byte in bytes {
    output.push(byte)
  }
}

///|
/// Assemble one complete primary HDU from a header and encoded data unit.
///
/// Structural cards and the exact unpadded data length are validated with the
/// same rules used by `parse_fits`. Header padding is ASCII space; data padding
/// is zero. The supplied header's stored `data_offset` is ignored because the
/// canonical encoded header determines the output offset.
pub fn encode_primary_hdu(
  header : Header,
  data : Bytes,
) -> Result[Bytes, FitsError] {
  let layout = match analyze_hdu_header(header, 0) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  if layout.data_length != data.length() {
    return Err(InvalidDataLength(layout.data_length, data.length()))
  }
  let header_bytes = match encode_header(header) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let padded_data_length = match checked_padded_block_length(data.length()) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let output_length = match
    checked_sum(
      header_bytes.length(),
      padded_data_length,
      "encoded primary HDU",
    ) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let output = Array(capacity=output_length)
  append_bytes(output, header_bytes)
  append_bytes(output, data)
  while output.length() < output_length {
    output.push(b'\x00')
  }
  Ok(Bytes::from_array(output))
}
