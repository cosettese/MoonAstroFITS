///|
fn q_table_file(format : String, pcount : Int, payload : Bytes) -> Bytes {
  binary_table_file(
    [
      "XTENSION= 'BINTABLE'",
      "BITPIX  =                    8",
      "NAXIS   =                    2",
      "NAXIS1  =                   16",
      "NAXIS2  =                    1",
      "PCOUNT  = \{pcount}",
      "GCOUNT  =                    1",
      "TFIELDS =                    1",
      "TFORM1  = '\{format}'",
      "END",
    ],
    payload,
  )
}

///|
test "decode a Q descriptor and 64-bit heap values" {
  let data = q_table_file(
    "1QK(2)",
    16,
    b"\x00\x00\x00\x00\x00\x00\x00\x02\x00\x00\x00\x00\x00\x00\x00\x00" +
    b"\x80\x00\x00\x00\x00\x00\x00\x00\x7F\xFF\xFF\xFF\xFF\xFF\xFF\xFF",
  )
  let table = @moonastrofits.parse_binary_table(
    @moonastrofits.parse_fits(data).unwrap().hdus[1],
  ).unwrap()
  assert_eq(table.heap_length, 16)
  assert_eq(table.heap_offset, table.data_offset + 16)
  assert_eq(table.columns[0].max_elements, Some(2))
  assert_eq(
    table.columns[0].kind,
    @moonastrofits.Variable64(@moonastrofits.Int64),
  )
  assert_eq(@moonastrofits.decode_binary_row(data, table, 0).unwrap(), [
    @moonastrofits.Integers([-9223372036854775807L - 1L, 9223372036854775807L]),
  ])
  assert_true(
    @moonastrofits.encode_binary_row(table, [@moonastrofits.Integers([1L])])
    is Err(@moonastrofits.UnsupportedTableFormat("TFORM1", "1QK(2)")),
  )
}

///|
test "decode P descriptor with a THEAP gap" {
  let data = binary_table_file(
    [
      "XTENSION= 'BINTABLE'", "BITPIX  =                    8", "NAXIS   =                    2",
      "NAXIS1  =                    8", "NAXIS2  =                    1", "PCOUNT  =                   12",
      "GCOUNT  =                    1", "TFIELDS =                    1", "TFORM1  = '1PJ(2)'",
      "THEAP   =                   12", "END",
    ],
    b"\x00\x00\x00\x02\x00\x00\x00\x00" +
    b"\xAA\xAA\xAA\xAA" +
    b"\x00\x00\x00\x01\xFF\xFF\xFF\xFE",
  )
  let table = @moonastrofits.parse_binary_table(
    @moonastrofits.parse_fits(data).unwrap().hdus[1],
  ).unwrap()
  assert_eq(table.heap_offset, table.data_offset + 12)
  assert_eq(table.heap_length, 8)
  assert_eq(@moonastrofits.decode_binary_row(data, table, 0).unwrap(), [
    @moonastrofits.Integers([1L, -2L]),
  ])
}

///|
test "zero-length Q array ignores undefined descriptor offset" {
  let data = q_table_file(
    "1QK(0)", 0, b"\x00\x00\x00\x00\x00\x00\x00\x00\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF",
  )
  let table = @moonastrofits.parse_binary_table(
    @moonastrofits.parse_fits(data).unwrap().hdus[1],
  ).unwrap()
  assert_eq(@moonastrofits.decode_binary_row(data, table, 0).unwrap(), [
    @moonastrofits.Integers([]),
  ])
}

///|
test "reject descriptors outside the heap and above the declared maximum" {
  let outside = q_table_file(
    "1QK(2)",
    16,
    b"\x00\x00\x00\x00\x00\x00\x00\x02\x00\x00\x00\x00\x00\x00\x00\x08" +
    Bytes::make(16, b'\x00'),
  )
  let outside_table = @moonastrofits.parse_binary_table(
    @moonastrofits.parse_fits(outside).unwrap().hdus[1],
  ).unwrap()
  assert_true(
    @moonastrofits.decode_binary_row(outside, outside_table, 0)
    is Err(@moonastrofits.InvalidHeapDescriptor(1, 0, _)),
  )
  let exceeds_max = q_table_file(
    "1QK(1)",
    16,
    b"\x00\x00\x00\x00\x00\x00\x00\x02\x00\x00\x00\x00\x00\x00\x00\x00" +
    Bytes::make(16, b'\x00'),
  )
  let max_table = @moonastrofits.parse_binary_table(
    @moonastrofits.parse_fits(exceeds_max).unwrap().hdus[1],
  ).unwrap()
  assert_true(
    @moonastrofits.decode_binary_row(exceeds_max, max_table, 0)
    is Err(@moonastrofits.InvalidHeapDescriptor(1, 0, _)),
  )
  let negative = q_table_file(
    "1QK(2)", 0, b"\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x00\x00\x00\x00\x00\x00\x00\x00",
  )
  let negative_table = @moonastrofits.parse_binary_table(
    @moonastrofits.parse_fits(negative).unwrap().hdus[1],
  ).unwrap()
  assert_true(
    @moonastrofits.decode_binary_row(negative, negative_table, 0)
    is Err(@moonastrofits.InvalidHeapDescriptor(1, 0, _)),
  )
}

///|
test "reject malformed heap formats and THEAP overlaps" {
  for format in ["2PJ", "1PZ", "1QK(x)", "1QK()"] {
    let data = q_table_file(format, 0, Bytes::make(16, b'\x00'))
    assert_true(
      @moonastrofits.parse_binary_table(
        @moonastrofits.parse_fits(data).unwrap().hdus[1],
      )
      is Err(@moonastrofits.UnsupportedTableFormat("TFORM1", _)),
    )
  }
  let overlap = binary_table_file(
    [
      "XTENSION= 'BINTABLE'", "BITPIX  =                    8", "NAXIS   =                    2",
      "NAXIS1  =                    8", "NAXIS2  =                    1", "PCOUNT  =                    8",
      "GCOUNT  =                    1", "TFIELDS =                    1", "TFORM1  = '1PJ'",
      "THEAP   =                    7", "END",
    ],
    Bytes::make(16, b'\x00'),
  )
  assert_true(
    @moonastrofits.parse_binary_table(
      @moonastrofits.parse_fits(overlap).unwrap().hdus[1],
    )
    is Err(@moonastrofits.InvalidParameter("THEAP", 7)),
  )
}

///|
test "decode heap-backed bit and floating arrays" {
  let packed_bits = binary_table_file(
    [
      "XTENSION= 'BINTABLE'", "BITPIX  =                    8", "NAXIS   =                    2",
      "NAXIS1  =                    8", "NAXIS2  =                    1", "PCOUNT  =                    2",
      "GCOUNT  =                    1", "TFIELDS =                    1", "TFORM1  = '1PX(9)'",
      "END",
    ],
    b"\x00\x00\x00\x09\x00\x00\x00\x00\xAA\x80",
  )
  let bit_table = @moonastrofits.parse_binary_table(
    @moonastrofits.parse_fits(packed_bits).unwrap().hdus[1],
  ).unwrap()
  assert_eq(
    @moonastrofits.decode_binary_row(packed_bits, bit_table, 0).unwrap(),
    [
      @moonastrofits.Bits([
        true, false, true, false, true, false, true, false, true,
      ]),
    ],
  )
  let floats = q_table_file(
    "1QE(2)",
    8,
    b"\x00\x00\x00\x00\x00\x00\x00\x02\x00\x00\x00\x00\x00\x00\x00\x00" +
    b"\x3F\xC0\x00\x00\xC0\x10\x00\x00",
  )
  let float_table = @moonastrofits.parse_binary_table(
    @moonastrofits.parse_fits(floats).unwrap().hdus[1],
  ).unwrap()
  assert_eq(@moonastrofits.decode_binary_row(floats, float_table, 0).unwrap(), [
    @moonastrofits.Reals([1.5, -2.25]),
  ])
}

///|
test "reject THEAP beyond the data unit" {
  let beyond = binary_table_file(
    [
      "XTENSION= 'BINTABLE'", "BITPIX  =                    8", "NAXIS   =                    2",
      "NAXIS1  =                    8", "NAXIS2  =                    1", "PCOUNT  =                    8",
      "GCOUNT  =                    1", "TFIELDS =                    1", "TFORM1  = '1PJ'",
      "THEAP   =                   17", "END",
    ],
    Bytes::make(16, b'\x00'),
  )
  assert_true(
    @moonastrofits.parse_binary_table(
      @moonastrofits.parse_fits(beyond).unwrap().hdus[1],
    )
    is Err(@moonastrofits.InvalidParameter("THEAP", 17)),
  )
}

///|
test "zero-repeat descriptor occupies no row bytes" {
  let data = binary_table_file(
    [
      "XTENSION= 'BINTABLE'", "BITPIX  =                    8", "NAXIS   =                    2",
      "NAXIS1  =                    1", "NAXIS2  =                    1", "PCOUNT  =                    0",
      "GCOUNT  =                    1", "TFIELDS =                    2", "TFORM1  = '0PK(0)'",
      "TFORM2  = '1B'", "END",
    ],
    b"\x2A",
  )
  let table = @moonastrofits.parse_binary_table(
    @moonastrofits.parse_fits(data).unwrap().hdus[1],
  ).unwrap()
  assert_eq(table.columns[0].width, 0)
  assert_eq(@moonastrofits.decode_binary_row(data, table, 0).unwrap(), [
    @moonastrofits.Integers([]),
    @moonastrofits.Integers([42L]),
  ])
}

///|
test "negative nonempty P heap offset is rejected" {
  let data = binary_table_file(
    [
      "XTENSION= 'BINTABLE'", "BITPIX  =                    8", "NAXIS   =                    2",
      "NAXIS1  =                    8", "NAXIS2  =                    1", "PCOUNT  =                    4",
      "GCOUNT  =                    1", "TFIELDS =                    1", "TFORM1  = '1PJ(1)'",
      "END",
    ],
    b"\x00\x00\x00\x01\xFF\xFF\xFF\xFF\x00\x00\x00\x01",
  )
  let table = @moonastrofits.parse_binary_table(
    @moonastrofits.parse_fits(data).unwrap().hdus[1],
  ).unwrap()
  assert_true(
    @moonastrofits.decode_binary_row(data, table, 0)
    is Err(@moonastrofits.InvalidHeapDescriptor(1, 0, _)),
  )
}
