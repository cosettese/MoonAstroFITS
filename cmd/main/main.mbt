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
  append_card(bytes, "NAXIS   =                    1")
  append_card(bytes, "NAXIS1  =                    3")
  append_card(bytes, "BSCALE  =                    2")
  append_card(bytes, "BZERO   =                   10")
  append_card(bytes, "END")
  while bytes.length() % 2880 != 0 {
    bytes.push(b' ')
  }
  let header = @fits.parse_header(Bytes::from_array(bytes)).unwrap()
  let image : @fits.IntegerImage = {
    axes: [3],
    raw: [-2L, 0L, 3L],
    bscale: 2.0,
    bzero: 10.0,
    blank: None,
  }
  let pixels = @fits.encode_integer_pixels(image, 16).unwrap()
  let data = @fits.encode_primary_hdu(header, pixels).unwrap()
  match @fits.parse_fits(data) {
    Err(error) => println("invalid FITS: \{error.message()}")
    Ok(file) =>
      match file.primary() {
        None => println("invalid FITS: no primary HDU")
        Some(primary) =>
          match @fits.decode_integer_image(data, primary) {
            Err(error) => println("invalid image: \{error.message()}")
            Ok(image) =>
              println(
                "FITS file: \{file.hdus.length()} HDU, decoded \{image.raw.length()} scaled integer pixels",
              )
          }
      }
  }
}
