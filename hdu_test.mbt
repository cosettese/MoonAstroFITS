///|
fn append_test_bytes(output : Array[Byte], bytes : Bytes) -> Unit {
  for byte in bytes {
    output.push(byte)
  }
}

///|
fn append_zero_padding(output : Array[Byte]) -> Unit {
  while output.length() % 2880 != 0 {
    output.push(b'\x00')
  }
}

///|
test "parse primary image geometry and padded data boundary" {
  let output = []
  append_test_bytes(
    output,
    test_header([
      "SIMPLE  =                    T", "BITPIX  =                   16", "NAXIS   =                    2",
      "NAXIS1  =                    3", "NAXIS2  =                    2", "END",
    ]),
  )
  for value = 0; value < 12; value = value + 1 {
    output.push(value.to_byte())
  }
  append_zero_padding(output)
  let file = @moonastrofits.parse_fits(Bytes::from_array(output)).unwrap()
  assert_eq(file.hdus.length(), 1)
  let hdu = file.primary().unwrap()
  assert_eq(hdu.kind, @moonastrofits.Primary)
  assert_eq(hdu.data_offset, 2880)
  assert_eq(hdu.data_length, 12)
  assert_eq(hdu.next_hdu_offset, 5760)
  let image = hdu.image.unwrap()
  assert_eq(image.bitpix, 16)
  assert_eq(image.axes, [3, 2])
  assert_eq(image.pixel_count, 6)
}

///|
test "walk a primary HDU followed by an IMAGE extension" {
  let output = []
  append_test_bytes(
    output,
    test_header([
      "SIMPLE  =                    T", "BITPIX  =                    8", "NAXIS   =                    0",
      "END",
    ]),
  )
  append_test_bytes(
    output,
    test_header([
      "XTENSION= 'IMAGE   '", "BITPIX  =                    8", "NAXIS   =                    2",
      "NAXIS1  =                    2", "NAXIS2  =                    2", "PCOUNT  =                    0",
      "GCOUNT  =                    1", "END",
    ]),
  )
  output.push(b'\x01')
  output.push(b'\x02')
  output.push(b'\x03')
  output.push(b'\x04')
  append_zero_padding(output)
  let file = @moonastrofits.parse_fits(Bytes::from_array(output)).unwrap()
  assert_eq(file.hdus.length(), 2)
  assert_eq(file.hdus[1].kind, @moonastrofits.ImageExtension)
  assert_eq(file.hdus[1].data_offset, 5760)
  assert_eq(file.hdus[1].data_length, 4)
  assert_eq(file.hdus[1].next_hdu_offset, 8640)
}

///|
test "reject required primary keywords out of order" {
  let data = test_header([
    "SIMPLE  =                    T", "NAXIS   =                    0", "BITPIX  =                    8",
    "END",
  ])
  assert_true(
    @moonastrofits.parse_fits(data)
    is Err(@moonastrofits.InvalidRequiredOrder(_, _, _)),
  )
}

///|
test "reject invalid BITPIX, axes, and overflowing geometry" {
  assert_true(
    @moonastrofits.parse_fits(
      test_header([
        "SIMPLE  =                    T", "BITPIX  =                   24", "NAXIS   =                    0",
        "END",
      ]),
    )
    is Err(@moonastrofits.UnsupportedBitpix(_)),
  )
  assert_true(
    @moonastrofits.parse_fits(
      test_header([
        "SIMPLE  =                    T", "BITPIX  =                    8", "NAXIS   =                    1",
        "NAXIS1  =                   -1", "END",
      ]),
    )
    is Err(@moonastrofits.InvalidAxis(_, _)),
  )
  assert_true(
    @moonastrofits.parse_fits(
      test_header([
        "SIMPLE  =                    T", "BITPIX  =                   64", "NAXIS   =                    2",
        "NAXIS1  =                50000", "NAXIS2  =                50000", "END",
      ]),
    )
    is Err(@moonastrofits.SizeOverflow(_)),
  )
}

///|
test "reject a truncated image data unit" {
  let header = test_header([
    "SIMPLE  =                    T", "BITPIX  =                   16", "NAXIS   =                    1",
    "NAXIS1  =                    2", "END",
  ])
  assert_true(
    @moonastrofits.parse_fits(header) is Err(@moonastrofits.Truncated(_, _, _)),
  )
}
