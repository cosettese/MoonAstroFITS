///|
fn parse_card_int64(card : Card) -> Result[Int64, FitsError] {
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
  let minimum = -9223372036854775807L - 1L
  let limit = if negative { minimum } else { -9223372036854775807L }
  let multiply_limit = limit / 10L
  let mut value = 0L
  while index < chars.length() {
    let ch = chars[index]
    if ch < '0' || ch > '9' {
      return Err(InvalidInteger(card.keyword, text))
    }
    let digit = (ch.to_int() - '0'.to_int()).to_int64()
    if value < multiply_limit {
      return Err(SizeOverflow("integer keyword \{card.keyword}"))
    }
    value = value * 10L
    if value < limit + digit {
      return Err(SizeOverflow("integer keyword \{card.keyword}"))
    }
    value = value - digit
    index = index + 1
  }
  Ok(if negative { value } else { -value })
}

///|
fn parse_card_real(card : Card) -> Result[Double, FitsError] {
  let text = match card_lexical_value(card) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let chars = text.to_array()
  if chars.length() == 0 {
    return Err(InvalidReal(card.keyword, text))
  }
  let mut index = 0
  let mut negative = false
  if chars[0] == '-' || chars[0] == '+' {
    negative = chars[0] == '-'
    index = 1
  }
  let mut value = 0.0
  let mut digits = 0
  let mut fractional_digits = 0
  let mut after_point = false
  while index < chars.length() {
    let ch = chars[index]
    if ch >= '0' && ch <= '9' {
      value = value * 10.0 + (ch.to_int() - '0'.to_int()).to_double()
      digits = digits + 1
      if after_point {
        fractional_digits = fractional_digits + 1
      }
      index = index + 1
    } else if ch == '.' && !after_point {
      after_point = true
      index = index + 1
    } else {
      break
    }
  }
  if digits == 0 {
    return Err(InvalidReal(card.keyword, text))
  }
  let mut exponent = 0
  let mut exponent_negative = false
  if index < chars.length() &&
    (
      chars[index] == 'E' ||
      chars[index] == 'e' ||
      chars[index] == 'D' ||
      chars[index] == 'd'
    ) {
    index = index + 1
    if index < chars.length() && (chars[index] == '-' || chars[index] == '+') {
      exponent_negative = chars[index] == '-'
      index = index + 1
    }
    let exponent_start = index
    while index < chars.length() && chars[index] >= '0' && chars[index] <= '9' {
      let digit = chars[index].to_int() - '0'.to_int()
      if exponent > 1000 {
        return Err(InvalidReal(card.keyword, text))
      }
      exponent = exponent * 10 + digit
      index = index + 1
    }
    if index == exponent_start {
      return Err(InvalidReal(card.keyword, text))
    }
  }
  if index != chars.length() {
    return Err(InvalidReal(card.keyword, text))
  }
  if exponent_negative {
    exponent = -exponent
  }
  exponent = exponent - fractional_digits
  if exponent > 308 || exponent < -324 {
    return Err(InvalidReal(card.keyword, text))
  }
  if exponent > 0 {
    for power = 0; power < exponent; power = power + 1 {
      value = value * 10.0
    }
  } else {
    for power = 0; power > exponent; power = power - 1 {
      value = value / 10.0
    }
  }
  if value > 1.7976931348623157e308 {
    return Err(InvalidReal(card.keyword, text))
  }
  Ok(if negative { -value } else { value })
}

///|
fn scaling_value(
  header : Header,
  keyword : String,
  default : Double,
) -> Result[Double, FitsError] {
  match header.get(keyword) {
    None => Ok(default)
    Some(card) => parse_card_real(card)
  }
}

///|
fn read_int16_be(data : Bytes, offset : Int) -> Int64 {
  let unsigned = data[offset].to_int() * 256 + data[offset + 1].to_int()
  (if unsigned >= 32768 { unsigned - 65536 } else { unsigned }).to_int64()
}

///|
fn read_int32_be(data : Bytes, offset : Int) -> Int64 {
  let unsigned = data[offset].to_int64() * 16777216L +
    data[offset + 1].to_int64() * 65536L +
    data[offset + 2].to_int64() * 256L +
    data[offset + 3].to_int64()
  if unsigned >= 2147483648L {
    unsigned - 4294967296L
  } else {
    unsigned
  }
}

///|
fn read_int64_be(data : Bytes, offset : Int) -> Int64 {
  let mut value = 0L
  for index = 0; index < 8; index = index + 1 {
    value = (value << 8) | data[offset + index].to_int64()
  }
  value
}

///|
/// Decode a contiguous integer primary array or IMAGE extension.
///
/// FITS stores samples in big-endian order. `BITPIX=8` is unsigned; 16, 32,
/// and 64-bit samples use two's-complement signed integers. Linear scaling and
/// blank detection are retained explicitly rather than changing the raw data.
pub fn decode_integer_image(
  data : Bytes,
  hdu : Hdu,
) -> Result[IntegerImage, FitsError] {
  let layout = match hdu.image {
    None => return Err(NotImageHdu(hdu.index))
    Some(value) => value
  }
  let bytes_per_pixel = match layout.bitpix {
    8 => 1
    16 => 2
    32 => 4
    64 => 8
    value => return Err(UnsupportedIntegerBitpix(value))
  }
  let expected_length = match
    checked_product(layout.pixel_count, bytes_per_pixel, "integer image") {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  if expected_length != hdu.data_length {
    return Err(UnsupportedImageLayout(hdu.index))
  }
  if hdu.data_offset < 0 || expected_length > data.length() - hdu.data_offset {
    return Err(
      Truncated(
        hdu.data_offset,
        expected_length,
        data.length() - hdu.data_offset,
      ),
    )
  }
  let bscale = match scaling_value(hdu.header, "BSCALE", 1.0) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let bzero = match scaling_value(hdu.header, "BZERO", 0.0) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let blank = match hdu.header.get("BLANK") {
    None => None
    Some(card) =>
      match parse_card_int64(card) {
        Err(error) => return Err(error)
        Ok(value) => Some(value)
      }
  }
  let raw = []
  for index = 0; index < layout.pixel_count; index = index + 1 {
    let offset = hdu.data_offset + index * bytes_per_pixel
    raw.push(
      match layout.bitpix {
        8 => data[offset].to_int64()
        16 => read_int16_be(data, offset)
        32 => read_int32_be(data, offset)
        64 => read_int64_be(data, offset)
        _ => abort("validated integer BITPIX became unreachable")
      },
    )
  }
  Ok({ axes: layout.axes, raw, bscale, bzero, blank, })
}

///|
fn read_float32_be(data : Bytes, offset : Int) -> Double {
  let bits = (data[offset].to_uint() << 24) |
    (data[offset + 1].to_uint() << 16) |
    (data[offset + 2].to_uint() << 8) |
    data[offset + 3].to_uint()
  Float::reinterpret_from_uint(bits).to_double()
}

///|
fn read_float64_be(data : Bytes, offset : Int) -> Double {
  let mut bits = 0UL
  for index = 0; index < 8; index = index + 1 {
    bits = (bits << 8) | data[offset + index].to_uint64()
  }
  bits.reinterpret_as_double()
}

///|
/// Decode a contiguous IEEE floating-point primary array or IMAGE extension.
///
/// `BITPIX=-32` values are widened exactly from IEEE binary32 to `Double`;
/// `BITPIX=-64` values retain their binary64 representation. NaN, infinities,
/// and signed zero are preserved in `raw` before FITS linear scaling.
pub fn decode_floating_image(
  data : Bytes,
  hdu : Hdu,
) -> Result[FloatingImage, FitsError] {
  let layout = match hdu.image {
    None => return Err(NotImageHdu(hdu.index))
    Some(value) => value
  }
  let bytes_per_pixel = match layout.bitpix {
    -32 => 4
    -64 => 8
    value => return Err(UnsupportedFloatingBitpix(value))
  }
  let expected_length = match
    checked_product(layout.pixel_count, bytes_per_pixel, "floating image") {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  if expected_length != hdu.data_length {
    return Err(UnsupportedImageLayout(hdu.index))
  }
  if hdu.data_offset < 0 || hdu.data_offset > data.length() {
    return Err(Truncated(hdu.data_offset, expected_length, 0))
  }
  let available = data.length() - hdu.data_offset
  if expected_length > available {
    return Err(Truncated(hdu.data_offset, expected_length, available))
  }
  let bscale = match scaling_value(hdu.header, "BSCALE", 1.0) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let bzero = match scaling_value(hdu.header, "BZERO", 0.0) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let raw = []
  for index = 0; index < layout.pixel_count; index = index + 1 {
    let offset = hdu.data_offset + index * bytes_per_pixel
    raw.push(
      match layout.bitpix {
        -32 => read_float32_be(data, offset)
        -64 => read_float64_be(data, offset)
        _ => abort("validated floating BITPIX became unreachable")
      },
    )
  }
  Ok({ axes: layout.axes, raw, bscale, bzero, })
}
