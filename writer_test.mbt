///|
test "encode a canonical header byte for byte" {
  let source = test_header([
    "SIMPLE  =                    T / conforms to FITS", "BITPIX  =                   16",
    "NAXIS   =                    0", "OBJECT  = 'M31' / target", "HISTORY calibrated",
    "END",
  ])
  let header = @moonastrofits.parse_header(source).unwrap()
  let encoded = @moonastrofits.encode_header(header).unwrap()
  assert_eq(encoded, source)
}

///|
test "header encoding round trips lexical cards" {
  let source = test_header([
    "SIMPLE  =                    T", "UNDEF   =", "OBJECT  = 'M31 / core' / target field",
    "COMMENT first pass", "HISTORY calibrated", "END",
  ])
  let first = @moonastrofits.parse_header(source).unwrap()
  let encoded = @moonastrofits.encode_header(first).unwrap()
  let second = @moonastrofits.parse_header(encoded).unwrap()
  assert_eq(second.cards, first.cards)
  assert_eq(second.data_offset, 2880)
}

///|
test "header encoding pads multiple blocks deterministically" {
  let cards : Array[@moonastrofits.Card] = []
  for index = 0; index < 36; index = index + 1 {
    cards.push({
      keyword: "HISTORY",
      value: None,
      comment: Some("step \{index}"),
      record_index: index,
    })
  }
  cards.push({ keyword: "END", value: None, comment: None, record_index: 36, })
  let encoded = @moonastrofits.encode_header({ cards, data_offset: 0, }).unwrap()
  assert_eq(encoded.length(), 5760)
  assert_eq(@moonastrofits.parse_header(encoded).unwrap().cards.length(), 37)
}

///|
test "reject missing or non-terminal END and oversized cards" {
  let simple : @moonastrofits.Card = {
    keyword: "SIMPLE",
    value: Some("T"),
    comment: None,
    record_index: 0,
  }
  assert_true(
    @moonastrofits.encode_header({ cards: [simple], data_offset: 0, })
    is Err(@moonastrofits.MissingEnd(_)),
  )
  let end : @moonastrofits.Card = {
    keyword: "END",
    value: None,
    comment: None,
    record_index: 0,
  }
  assert_true(
    @moonastrofits.encode_header({ cards: [end, simple], data_offset: 0, })
    is Err(@moonastrofits.InvalidCard(_, _)),
  )
  let long : @moonastrofits.Card = {
    keyword: "COMMENT",
    value: None,
    comment: Some(
      "123456789012345678901234567890123456789012345678901234567890123456789012345",
    ),
    record_index: 0,
  }
  assert_true(
    @moonastrofits.encode_header({ cards: [long, end], data_offset: 0, })
    is Err(@moonastrofits.CardTooLong(_, _)),
  )
}

///|
test "reject non-ASCII encoded text" {
  let card : @moonastrofits.Card = {
    keyword: "COMMENT",
    value: None,
    comment: Some("星"),
    record_index: 0,
  }
  let end : @moonastrofits.Card = {
    keyword: "END",
    value: None,
    comment: None,
    record_index: 1,
  }
  assert_true(
    @moonastrofits.encode_header({ cards: [card, end], data_offset: 0, })
    is Err(@moonastrofits.InvalidCard(_, _)),
  )
}

///|
test "assemble and round trip an integer primary HDU" {
  let header = @moonastrofits.parse_header(
    test_header([
      "SIMPLE  =                    T", "BITPIX  =                   16", "NAXIS   =                    1",
      "NAXIS1  =                    3", "BLANK   =                    0", "END",
    ]),
  ).unwrap()
  let image : @moonastrofits.IntegerImage = {
    axes: [3],
    raw: [-2L, 0L, 3L],
    bscale: 1.0,
    bzero: 0.0,
    blank: Some(0L),
  }
  let pixels = @moonastrofits.encode_integer_pixels(image, 16).unwrap()
  let encoded = @moonastrofits.encode_primary_hdu(header, pixels).unwrap()
  assert_eq(encoded.length(), 5760)
  assert_eq(encoded[2880:2886], b"\xFF\xFE\x00\x00\x00\x03")
  assert_eq(encoded[5759], b'\x00')
  let file = @moonastrofits.parse_fits(encoded).unwrap()
  let primary = file.primary().unwrap()
  assert_eq(
    @moonastrofits.decode_integer_image(encoded, primary).unwrap(),
    image,
  )
}

///|
test "assemble and round trip a floating primary HDU" {
  let header = @moonastrofits.parse_header(
    test_header([
      "SIMPLE  =                    T", "BITPIX  =                  -32", "NAXIS   =                    1",
      "NAXIS1  =                    2", "END",
    ]),
  ).unwrap()
  let image : @moonastrofits.FloatingImage = {
    axes: [2],
    raw: [1.5, -2.25],
    bscale: 1.0,
    bzero: 0.0,
  }
  let pixels = @moonastrofits.encode_floating_pixels(image, -32).unwrap()
  let encoded = @moonastrofits.encode_primary_hdu(header, pixels).unwrap()
  let primary = @moonastrofits.parse_fits(encoded).unwrap().primary().unwrap()
  assert_eq(
    @moonastrofits.decode_floating_image(encoded, primary).unwrap(),
    image,
  )
}

///|
test "primary HDU assembly validates exact payload length" {
  let header = @moonastrofits.parse_header(
    test_header([
      "SIMPLE  =                    T", "BITPIX  =                    8", "NAXIS   =                    1",
      "NAXIS1  =                    2", "END",
    ]),
  ).unwrap()
  assert_true(
    @moonastrofits.encode_primary_hdu(header, b"\x01")
    is Err(@moonastrofits.InvalidDataLength(2, 1)),
  )
  assert_true(
    @moonastrofits.encode_primary_hdu(header, b"\x01\x02\x03")
    is Err(@moonastrofits.InvalidDataLength(2, 3)),
  )
}

///|
test "primary HDU assembly pads data spanning multiple blocks" {
  let header = @moonastrofits.parse_header(
    test_header([
      "SIMPLE  =                    T", "BITPIX  =                    8", "NAXIS   =                    1",
      "NAXIS1  =                 2881", "END",
    ]),
  ).unwrap()
  let pixels = Bytes::make(2881, b'\x7F')
  let encoded = @moonastrofits.encode_primary_hdu(header, pixels).unwrap()
  assert_eq(encoded.length(), 8640)
  assert_eq(encoded[5760], b'\x7F')
  assert_eq(encoded[5761], b'\x00')
  assert_eq(encoded[8639], b'\x00')
  assert_eq(@moonastrofits.parse_fits(encoded).unwrap().hdus.length(), 1)
}

///|
fn empty_primary_hdu() -> Bytes {
  let header = @moonastrofits.parse_header(
    test_header([
      "SIMPLE  =                    T", "BITPIX  =                    8", "NAXIS   =                    0",
      "END",
    ]),
  ).unwrap()
  @moonastrofits.encode_primary_hdu(header, b"").unwrap()
}

///|
test "assemble an IMAGE extension into a multi-HDU FITS file" {
  let header = @moonastrofits.parse_header(
    test_header([
      "XTENSION= 'IMAGE   '", "BITPIX  =                    8", "NAXIS   =                    2",
      "NAXIS1  =                    2", "NAXIS2  =                    2", "PCOUNT  =                    0",
      "GCOUNT  =                    1", "END",
    ]),
  ).unwrap()
  let image : @moonastrofits.IntegerImage = {
    axes: [2, 2],
    raw: [1L, 2L, 3L, 4L],
    bscale: 1.0,
    bzero: 0.0,
    blank: None,
  }
  let pixels = @moonastrofits.encode_integer_pixels(image, 8).unwrap()
  let extension = @moonastrofits.encode_extension_hdu(header, pixels).unwrap()
  let data = empty_primary_hdu() + extension
  let file = @moonastrofits.parse_fits(data).unwrap()
  assert_eq(file.hdus.length(), 2)
  assert_eq(file.hdus[1].kind, @moonastrofits.ImageExtension)
  assert_eq(file.hdus[1].data_offset, 5760)
  assert_eq(
    @moonastrofits.decode_integer_image(data, file.hdus[1]).unwrap(),
    image,
  )
}

///|
test "assemble a generic extension with parameter bytes" {
  let header = @moonastrofits.parse_header(
    test_header([
      "XTENSION= 'BINTABLE'", "BITPIX  =                    8", "NAXIS   =                    2",
      "NAXIS1  =                    4", "NAXIS2  =                    2", "PCOUNT  =                    2",
      "GCOUNT  =                    1", "END",
    ]),
  ).unwrap()
  let payload = b"\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0A"
  let extension = @moonastrofits.encode_extension_hdu(header, payload).unwrap()
  assert_eq(extension.length(), 5760)
  assert_eq(extension[2880:2890], payload)
  let data = empty_primary_hdu() + extension
  let file = @moonastrofits.parse_fits(data).unwrap()
  assert_eq(file.hdus.length(), 2)
  assert_eq(file.hdus[1].kind, @moonastrofits.OtherExtension("BINTABLE"))
  assert_eq(file.hdus[1].data_length, 10)
  assert_eq(file.hdus[1].image, None)
}

///|
test "extension assembly rejects primary and incomplete extension headers" {
  let primary_header = @moonastrofits.parse_header(
    test_header([
      "SIMPLE  =                    T", "BITPIX  =                    8", "NAXIS   =                    0",
      "END",
    ]),
  ).unwrap()
  assert_true(
    @moonastrofits.encode_extension_hdu(primary_header, b"")
    is Err(@moonastrofits.InvalidRequiredOrder(_, _, _)),
  )
  let missing_gcount = @moonastrofits.parse_header(
    test_header([
      "XTENSION= 'IMAGE   '", "BITPIX  =                    8", "NAXIS   =                    1",
      "NAXIS1  =                    1", "PCOUNT  =                    0", "END",
    ]),
  ).unwrap()
  assert_true(
    @moonastrofits.encode_extension_hdu(missing_gcount, b"\x00")
    is Err(@moonastrofits.InvalidRequiredOrder(_, _, _)),
  )
}
