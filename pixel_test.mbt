///|
fn image_file(cards : Array[String], pixels : Array[Byte]) -> Bytes {
  let output = []
  append_test_bytes(output, test_header(cards))
  for byte in pixels {
    output.push(byte)
  }
  append_zero_padding(output)
  Bytes::from_array(output)
}

///|
test "decode signed 16-bit pixels with scaling and BLANK" {
  let data = image_file(
    [
      "SIMPLE  =                    T", "BITPIX  =                   16", "NAXIS   =                    1",
      "NAXIS1  =                    3", "BSCALE  =                  2.5", "BZERO   =                1.0D1",
      "BLANK   =                    0", "END",
    ],
    [b'\xFF', b'\xFE', b'\x00', b'\x00', b'\x00', b'\x03'],
  )
  let hdu = @moonastrofits.parse_fits(data).unwrap().primary().unwrap()
  let image = @moonastrofits.decode_integer_image(data, hdu).unwrap()
  assert_eq(image.axes, [3])
  assert_eq(image.raw, [-2L, 0L, 3L])
  assert_eq(image.bscale, 2.5)
  assert_eq(image.bzero, 10.0)
  assert_eq(image.blank, Some(0L))
  assert_eq(image.physical_values(), [Some(5.0), None, Some(17.5)])
}

///|
test "decode unsigned 8-bit and signed 32-bit limits" {
  let bytes8 = image_file(
    [
      "SIMPLE  =                    T", "BITPIX  =                    8", "NAXIS   =                    1",
      "NAXIS1  =                    2", "END",
    ],
    [b'\x00', b'\xFF'],
  )
  let hdu8 = @moonastrofits.parse_fits(bytes8).unwrap().primary().unwrap()
  assert_eq(@moonastrofits.decode_integer_image(bytes8, hdu8).unwrap().raw, [
    0L, 255L,
  ])
  let bytes32 = image_file(
    [
      "SIMPLE  =                    T", "BITPIX  =                   32", "NAXIS   =                    1",
      "NAXIS1  =                    2", "END",
    ],
    [b'\x80', b'\x00', b'\x00', b'\x00', b'\x7F', b'\xFF', b'\xFF', b'\xFF'],
  )
  let hdu32 = @moonastrofits.parse_fits(bytes32).unwrap().primary().unwrap()
  assert_eq(@moonastrofits.decode_integer_image(bytes32, hdu32).unwrap().raw, [
    -2147483648L, 2147483647L,
  ])
}

///|
test "decode signed 64-bit samples" {
  let data = image_file(
    [
      "SIMPLE  =                    T", "BITPIX  =                   64", "NAXIS   =                    1",
      "NAXIS1  =                    2", "END",
    ],
    [
      b'\xFF', b'\xFF', b'\xFF', b'\xFF', b'\xFF', b'\xFF', b'\xFF', b'\xFF', b'\x00',
      b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x01', b'\x00',
    ],
  )
  let hdu = @moonastrofits.parse_fits(data).unwrap().primary().unwrap()
  assert_eq(@moonastrofits.decode_integer_image(data, hdu).unwrap().raw, [
    -1L, 256L,
  ])
}

///|
test "reject floating-point BITPIX and invalid scaling" {
  let floating = image_file(
    [
      "SIMPLE  =                    T", "BITPIX  =                  -32", "NAXIS   =                    1",
      "NAXIS1  =                    1", "END",
    ],
    [b'\x00', b'\x00', b'\x00', b'\x00'],
  )
  let floating_hdu = @moonastrofits.parse_fits(floating)
    .unwrap()
    .primary()
    .unwrap()
  assert_true(
    @moonastrofits.decode_integer_image(floating, floating_hdu)
    is Err(@moonastrofits.UnsupportedIntegerBitpix(_)),
  )
  let invalid_scale = image_file(
    [
      "SIMPLE  =                    T", "BITPIX  =                    8", "NAXIS   =                    1",
      "NAXIS1  =                    1", "BSCALE  =               1.2.3", "END",
    ],
    [b'\x01'],
  )
  let invalid_hdu = @moonastrofits.parse_fits(invalid_scale)
    .unwrap()
    .primary()
    .unwrap()
  assert_true(
    @moonastrofits.decode_integer_image(invalid_scale, invalid_hdu)
    is Err(@moonastrofits.InvalidReal(_, _)),
  )
}

///|
test "decode big-endian binary32 pixels and apply scaling" {
  let data = image_file(
    [
      "SIMPLE  =                    T", "BITPIX  =                  -32", "NAXIS   =                    1",
      "NAXIS1  =                    2", "BSCALE  =                    2", "BZERO   =                    1",
      "END",
    ],
    [b'\x3F', b'\xC0', b'\x00', b'\x00', b'\xC0', b'\x10', b'\x00', b'\x00'],
  )
  let hdu = @moonastrofits.parse_fits(data).unwrap().primary().unwrap()
  let image = @moonastrofits.decode_floating_image(data, hdu).unwrap()
  assert_eq(image.axes, [2])
  assert_eq(image.raw, [1.5, -2.25])
  assert_eq(image.physical_values(), [4.0, -3.5])
}

///|
test "preserve binary64 NaN, infinity, and negative zero" {
  let data = image_file(
    [
      "SIMPLE  =                    T", "BITPIX  =                  -64", "NAXIS   =                    1",
      "NAXIS1  =                    3", "END",
    ],
    [
      b'\x7F', b'\xF8', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x01', b'\x7F',
      b'\xF0', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x80', b'\x00',
      b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00',
    ],
  )
  let hdu = @moonastrofits.parse_fits(data).unwrap().primary().unwrap()
  let image = @moonastrofits.decode_floating_image(data, hdu).unwrap()
  assert_true(image.raw[0].is_nan())
  assert_true(image.raw[1].is_pos_inf())
  assert_eq(image.raw[2].reinterpret_as_uint64(), 0x8000000000000000UL)
}

///|
test "floating decoder rejects integer BITPIX" {
  let data = image_file(
    [
      "SIMPLE  =                    T", "BITPIX  =                   16", "NAXIS   =                    1",
      "NAXIS1  =                    1", "END",
    ],
    [b'\x00', b'\x01'],
  )
  let hdu = @moonastrofits.parse_fits(data).unwrap().primary().unwrap()
  assert_true(
    @moonastrofits.decode_floating_image(data, hdu)
    is Err(@moonastrofits.UnsupportedFloatingBitpix(_)),
  )
}
