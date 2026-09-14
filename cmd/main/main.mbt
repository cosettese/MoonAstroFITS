///|
fn append_card(output : Array[Byte], text : String) -> Unit {
  for ch in text {
    output.push(ch.to_int().to_byte())
  }
  for index = text.length(); index < 80; index = index + 1 {
    output.push(b' ')
  }
}

///|
fn main {
  let bytes = []
  append_card(bytes, "SIMPLE  =                    T")
  append_card(bytes, "BITPIX  =                   16")
  append_card(bytes, "NAXIS   =                    0")
  append_card(bytes, "END")
  while bytes.length() % 2880 != 0 {
    bytes.push(b' ')
  }
  match @fits.parse_fits(Bytes::from_array(bytes)) {
    Err(error) => println("invalid FITS: \{error.message()}")
    Ok(file) =>
      match file.primary() {
        None => println("invalid FITS: no primary HDU")
        Some(primary) =>
          println(
            "FITS file: \{file.hdus.length()} HDU, primary data at byte \{primary.data_offset}",
          )
      }
  }
}
