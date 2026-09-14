///|
fn required_card(
  header : Header,
  index : Int,
  keyword : String,
) -> Result[Card, FitsError] {
  if index >= header.cards.length() {
    return Err(MissingKeyword(keyword))
  }
  let card = header.cards[index]
  if card.keyword != keyword {
    return Err(InvalidRequiredOrder(index, keyword, card.keyword))
  }
  Ok(card)
}

///|
fn card_lexical_value(card : Card) -> Result[String, FitsError] {
  match card.value {
    Some(value) if value != "" => Ok(value)
    _ => Err(InvalidCard(card.record_index, "\{card.keyword} requires a value"))
  }
}

///|
fn parse_card_integer(card : Card) -> Result[Int, FitsError] {
  let text = match card_lexical_value(card) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let chars = text.to_array()
  if chars.length() == 0 {
    return Err(InvalidInteger(card.keyword, text))
  }
  let mut index = 0
  let mut negative = false
  if chars[0] == '-' || chars[0] == '+' {
    negative = chars[0] == '-'
    index = 1
  }
  if index == chars.length() {
    return Err(InvalidInteger(card.keyword, text))
  }
  let mut value = 0
  while index < chars.length() {
    let ch = chars[index]
    if ch < '0' || ch > '9' {
      return Err(InvalidInteger(card.keyword, text))
    }
    let digit = ch.to_int() - '0'.to_int()
    if value > (2147483647 - digit) / 10 {
      return Err(SizeOverflow("integer keyword \{card.keyword}"))
    }
    value = value * 10 + digit
    index = index + 1
  }
  Ok(if negative { -value } else { value })
}

///|
fn parse_card_logical(card : Card) -> Result[Bool, FitsError] {
  let text = match card_lexical_value(card) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  match text {
    "T" => Ok(true)
    "F" => Ok(false)
    _ => Err(InvalidLogical(card.keyword, text))
  }
}

///|
fn parse_card_string(card : Card) -> Result[String, FitsError] {
  let text = match card_lexical_value(card) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let chars = text.to_array()
  if chars.length() < 2 || chars[0] != '\'' {
    return Err(InvalidString(card.keyword, text))
  }
  let out = StringBuilder()
  let mut index = 1
  while index < chars.length() {
    if chars[index] == '\'' {
      if index + 1 < chars.length() && chars[index + 1] == '\'' {
        out.write_char('\'')
        index = index + 2
        continue
      }
      for trailing = index + 1
          trailing < chars.length()
          trailing = trailing + 1 {
        if chars[trailing] != ' ' {
          return Err(InvalidString(card.keyword, text))
        }
      }
      return Ok(out.to_string().trim_end(chars=" ").to_owned())
    }
    out.write_char(chars[index])
    index = index + 1
  }
  Err(InvalidString(card.keyword, text))
}

///|
fn checked_product(
  left : Int,
  right : Int,
  context : String,
) -> Result[Int, FitsError] {
  if left < 0 || right < 0 {
    return Err(SizeOverflow(context))
  }
  if left != 0 && right > 2147483647 / left {
    return Err(SizeOverflow(context))
  }
  Ok(left * right)
}

///|
fn checked_sum(
  left : Int,
  right : Int,
  context : String,
) -> Result[Int, FitsError] {
  if left < 0 || right < 0 || left > 2147483647 - right {
    return Err(SizeOverflow(context))
  }
  Ok(left + right)
}

///|
fn checked_padded_block_length(length : Int) -> Result[Int, FitsError] {
  if length > 2147483647 - (fits_block_size - 1) {
    return Err(SizeOverflow("padded data unit"))
  }
  Ok(padded_block_length(length))
}

///|
fn bitpix_bytes(bitpix : Int) -> Result[Int, FitsError] {
  match bitpix {
    8 => Ok(1)
    16 => Ok(2)
    32 | -32 => Ok(4)
    64 | -64 => Ok(8)
    _ => Err(UnsupportedBitpix(bitpix))
  }
}

///|
fn parse_hdu_layout(
  data : Bytes,
  header : Header,
  hdu_index : Int,
) -> Result[Hdu, FitsError] {
  let kind = if hdu_index == 0 {
    let simple = match required_card(header, 0, "SIMPLE") {
      Err(error) => return Err(error)
      Ok(card) => card
    }
    match parse_card_logical(simple) {
      Ok(true) => ()
      Ok(false) =>
        return Err(InvalidCard(simple.record_index, "SIMPLE must be T"))
      Err(error) => return Err(error)
    }
    Primary
  } else {
    let xtension = match required_card(header, 0, "XTENSION") {
      Err(error) => return Err(error)
      Ok(card) =>
        match parse_card_string(card) {
          Err(error) => return Err(error)
          Ok(value) => value
        }
    }
    if xtension == "IMAGE" {
      ImageExtension
    } else {
      OtherExtension(xtension)
    }
  }
  let bitpix_card = match required_card(header, 1, "BITPIX") {
    Err(error) => return Err(error)
    Ok(card) => card
  }
  let bitpix = match parse_card_integer(bitpix_card) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let bytes_per_value = match bitpix_bytes(bitpix) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let naxis_card = match required_card(header, 2, "NAXIS") {
    Err(error) => return Err(error)
    Ok(card) => card
  }
  let naxis = match parse_card_integer(naxis_card) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  if naxis < 0 || naxis > 999 {
    return Err(InvalidParameter("NAXIS", naxis))
  }
  let axes = []
  let mut pixel_count = if naxis == 0 { 0 } else { 1 }
  for axis = 1; axis <= naxis; axis = axis + 1 {
    let keyword = "NAXIS\{axis}"
    let card = match required_card(header, 2 + axis, keyword) {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    let length = match parse_card_integer(card) {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    if length < 0 {
      return Err(InvalidAxis(axis, length))
    }
    axes.push(length)
    pixel_count = match checked_product(pixel_count, length, "pixel count") {
      Err(error) => return Err(error)
      Ok(value) => value
    }
  }
  let pcount_card = if hdu_index == 0 {
    header.get("PCOUNT")
  } else {
    match required_card(header, 3 + naxis, "PCOUNT") {
      Err(error) => return Err(error)
      Ok(card) => Some(card)
    }
  }
  let gcount_card = if hdu_index == 0 {
    header.get("GCOUNT")
  } else {
    match required_card(header, 4 + naxis, "GCOUNT") {
      Err(error) => return Err(error)
      Ok(card) => Some(card)
    }
  }
  let pcount = match pcount_card {
    None => 0
    Some(card) =>
      match parse_card_integer(card) {
        Err(error) => return Err(error)
        Ok(value) => value
      }
  }
  let gcount = match gcount_card {
    None => 1
    Some(card) =>
      match parse_card_integer(card) {
        Err(error) => return Err(error)
        Ok(value) => value
      }
  }
  if pcount < 0 {
    return Err(InvalidParameter("PCOUNT", pcount))
  }
  if gcount < 1 {
    return Err(InvalidParameter("GCOUNT", gcount))
  }
  let values_per_group = match
    checked_sum(pixel_count, pcount, "values per group") {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let grouped_values = match
    checked_product(values_per_group, gcount, "grouped value count") {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let data_length = match
    checked_product(grouped_values, bytes_per_value, "data unit") {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let padded_data_length = match checked_padded_block_length(data_length) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  if padded_data_length > data.length() - header.data_offset {
    return Err(
      Truncated(
        header.data_offset,
        padded_data_length,
        data.length() - header.data_offset,
      ),
    )
  }
  let image = match kind {
    Primary | ImageExtension =>
      Some({ bitpix, axes, pixel_count, byte_length: data_length, })
    OtherExtension(_) => None
  }
  Ok({
    index: hdu_index,
    kind,
    header,
    image,
    data_offset: header.data_offset,
    data_length,
    next_hdu_offset: header.data_offset + padded_data_length,
  })
}

///|
/// Parse and structurally validate every HDU in a complete FITS byte stream.
pub fn parse_fits(data : Bytes) -> Result[FitsFile, FitsError] {
  if data.length() == 0 {
    return Err(Truncated(0, fits_block_size, 0))
  }
  if data.length() % fits_block_size != 0 {
    return Err(
      Truncated(
        data.length(),
        fits_block_size - data.length() % fits_block_size,
        0,
      ),
    )
  }
  let hdus = []
  let mut offset = 0
  while offset < data.length() {
    let header = match parse_header_at(data, offset) {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    let hdu = match parse_hdu_layout(data, header, hdus.length()) {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    if hdu.next_hdu_offset <= offset {
      return Err(SizeOverflow("HDU traversal"))
    }
    offset = hdu.next_hdu_offset
    hdus.push(hdu)
  }
  Ok({ hdus, })
}

///|
pub fn FitsFile::primary(self : FitsFile) -> Hdu? {
  if self.hdus.length() == 0 {
    None
  } else {
    Some(self.hdus[0])
  }
}
