///|
fn binary_table_file(cards : Array[String], payload : Bytes) -> Bytes {
  let header = @moonastrofits.parse_header(test_header(cards)).unwrap()
  empty_primary_hdu() +
  @moonastrofits.encode_extension_hdu(header, payload).unwrap()
}

///|
test "parse a binary-table schema and decode mixed rows" {
  let data = binary_table_file(
    [
      "XTENSION= 'BINTABLE'", "BITPIX  =                    8", "NAXIS   =                    2",
      "NAXIS1  =                   12", "NAXIS2  =                    2", "PCOUNT  =                    0",
      "GCOUNT  =                    1", "TFIELDS =                    3", "TTYPE1  = 'NAME'",
      "TFORM1  = '4A'", "TTYPE2  = 'COUNT'", "TFORM2  = '1J'", "TTYPE3  = 'FLUX'",
      "TFORM3  = '1E'", "END",
    ],
    b"M31 \x00\x00\x00\x2A\x3F\xC0\x00\x00M42 \xFF\xFF\xFF\xF9\xC0\x10\x00\x00",
  )
  let hdu = @moonastrofits.parse_fits(data).unwrap().hdus[1]
  let table = @moonastrofits.parse_binary_table(hdu).unwrap()
  assert_eq(table.row_length, 12)
  assert_eq(table.row_count, 2)
  assert_eq(table.data_offset, 5760)
  assert_eq(table.columns.length(), 3)
  assert_eq(table.columns[0], {
    index: 1,
    name: Some("NAME"),
    format: "4A",
    repeat: 4,
    offset: 0,
    width: 4,
    kind: @moonastrofits.Ascii,
  })
  assert_eq(table.columns[1].offset, 4)
  assert_eq(table.columns[2].offset, 8)
  assert_eq(@moonastrofits.decode_binary_row(data, table, 0).unwrap(), [
    @moonastrofits.Text("M31"),
    @moonastrofits.Integers([42L]),
    @moonastrofits.Reals([1.5]),
  ])
  assert_eq(@moonastrofits.decode_binary_row(data, table, 1).unwrap(), [
    @moonastrofits.Text("M42"),
    @moonastrofits.Integers([-7L]),
    @moonastrofits.Reals([-2.25]),
  ])
}

///|
test "decode repeated byte, integer, and binary64 columns" {
  let data = binary_table_file(
    [
      "XTENSION= 'BINTABLE'", "BITPIX  =                    8", "NAXIS   =                    2",
      "NAXIS1  =                   22", "NAXIS2  =                    1", "PCOUNT  =                    0",
      "GCOUNT  =                    1", "TFIELDS =                    4", "TFORM1  = '2B'",
      "TFORM2  = '2I'", "TFORM3  = '1K'", "TFORM4  = '1D'", "END",
    ],
    b"\x00\xFF\xFF\xFE\x01\x2C\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x40\x04\x00\x00\x00\x00\x00\x00",
  )
  let table = @moonastrofits.parse_binary_table(
    @moonastrofits.parse_fits(data).unwrap().hdus[1],
  ).unwrap()
  assert_eq(@moonastrofits.decode_binary_row(data, table, 0).unwrap(), [
    @moonastrofits.Integers([0L, 255L]),
    @moonastrofits.Integers([-2L, 300L]),
    @moonastrofits.Integers([-1L]),
    @moonastrofits.Reals([2.5]),
  ])
}

///|
test "reject unsupported formats and inconsistent row widths" {
  let unsupported = binary_table_file(
    [
      "XTENSION= 'BINTABLE'", "BITPIX  =                    8", "NAXIS   =                    2",
      "NAXIS1  =                    8", "NAXIS2  =                    1", "PCOUNT  =                    0",
      "GCOUNT  =                    1", "TFIELDS =                    1", "TFORM1  = '1P'",
      "END",
    ],
    b"\x00\x00\x00\x00\x00\x00\x00\x00",
  )
  assert_true(
    @moonastrofits.parse_binary_table(
      @moonastrofits.parse_fits(unsupported).unwrap().hdus[1],
    )
    is Err(@moonastrofits.UnsupportedTableFormat("TFORM1", "1P")),
  )
  let wrong_width = binary_table_file(
    [
      "XTENSION= 'BINTABLE'", "BITPIX  =                    8", "NAXIS   =                    2",
      "NAXIS1  =                    5", "NAXIS2  =                    1", "PCOUNT  =                    0",
      "GCOUNT  =                    1", "TFIELDS =                    1", "TFORM1  = '1J'",
      "END",
    ],
    b"\x00\x00\x00\x00\x00",
  )
  assert_true(
    @moonastrofits.parse_binary_table(
      @moonastrofits.parse_fits(wrong_width).unwrap().hdus[1],
    )
    is Err(@moonastrofits.InvalidTableRowWidth(5, 4)),
  )
}

///|
test "reject non-table HDUs and rows outside the table" {
  let primary = @moonastrofits.parse_fits(empty_primary_hdu()).unwrap().hdus[0]
  assert_true(
    @moonastrofits.parse_binary_table(primary)
    is Err(@moonastrofits.NotBinaryTable(0)),
  )
  let data = binary_table_file(
    [
      "XTENSION= 'BINTABLE'", "BITPIX  =                    8", "NAXIS   =                    2",
      "NAXIS1  =                    1", "NAXIS2  =                    1", "PCOUNT  =                    0",
      "GCOUNT  =                    1", "TFIELDS =                    1", "TFORM1  = '1B'",
      "END",
    ],
    b"\x01",
  )
  let table = @moonastrofits.parse_binary_table(
    @moonastrofits.parse_fits(data).unwrap().hdus[1],
  ).unwrap()
  assert_true(
    @moonastrofits.decode_binary_row(data, table, 1)
    is Err(@moonastrofits.TableRowOutOfRange(1, 1)),
  )
}

///|
test "encode mixed rows byte for byte and decode them again" {
  let cards = [
    "XTENSION= 'BINTABLE'", "BITPIX  =                    8", "NAXIS   =                    2",
    "NAXIS1  =                   12", "NAXIS2  =                    2", "PCOUNT  =                    0",
    "GCOUNT  =                    1", "TFIELDS =                    3", "TTYPE1  = 'NAME'",
    "TFORM1  = '4A'", "TTYPE2  = 'COUNT'", "TFORM2  = '1J'", "TTYPE3  = 'FLUX'",
    "TFORM3  = '1E'", "END",
  ]
  let template = binary_table_file(cards, Bytes::make(24, b'\x00'))
  let table = @moonastrofits.parse_binary_table(
    @moonastrofits.parse_fits(template).unwrap().hdus[1],
  ).unwrap()
  let rows = [
    [
      @moonastrofits.Text("M31"),
      @moonastrofits.Integers([42L]),
      @moonastrofits.Reals([1.5]),
    ],
    [
      @moonastrofits.Text("M42"),
      @moonastrofits.Integers([-7L]),
      @moonastrofits.Reals([-2.25]),
    ],
  ]
  let payload = @moonastrofits.encode_binary_rows(table, rows).unwrap()
  assert_eq(
    payload, b"M31 \x00\x00\x00\x2A\x3F\xC0\x00\x00M42 \xFF\xFF\xFF\xF9\xC0\x10\x00\x00",
  )
  let data = binary_table_file(cards, payload)
  let reparsed = @moonastrofits.parse_binary_table(
    @moonastrofits.parse_fits(data).unwrap().hdus[1],
  ).unwrap()
  assert_eq(
    @moonastrofits.decode_binary_row(data, reparsed, 0).unwrap(),
    rows[0],
  )
  assert_eq(
    @moonastrofits.decode_binary_row(data, reparsed, 1).unwrap(),
    rows[1],
  )
}

///|
test "encode repeated integer and binary64 cells" {
  let data = binary_table_file(
    [
      "XTENSION= 'BINTABLE'", "BITPIX  =                    8", "NAXIS   =                    2",
      "NAXIS1  =                   22", "NAXIS2  =                    1", "PCOUNT  =                    0",
      "GCOUNT  =                    1", "TFIELDS =                    4", "TFORM1  = '2B'",
      "TFORM2  = '2I'", "TFORM3  = '1K'", "TFORM4  = '1D'", "END",
    ],
    Bytes::make(22, b'\x00'),
  )
  let table = @moonastrofits.parse_binary_table(
    @moonastrofits.parse_fits(data).unwrap().hdus[1],
  ).unwrap()
  assert_eq(
    @moonastrofits.encode_binary_row(table, [
      @moonastrofits.Integers([0L, 255L]),
      @moonastrofits.Integers([-2L, 300L]),
      @moonastrofits.Integers([-1L]),
      @moonastrofits.Reals([2.5]),
    ]).unwrap(),
    b"\x00\xFF\xFF\xFE\x01\x2C\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x40\x04\x00\x00\x00\x00\x00\x00",
  )
}

///|
test "reject invalid binary-table row values" {
  let data = binary_table_file(
    [
      "XTENSION= 'BINTABLE'", "BITPIX  =                    8", "NAXIS   =                    2",
      "NAXIS1  =                    9", "NAXIS2  =                    1", "PCOUNT  =                    0",
      "GCOUNT  =                    1", "TFIELDS =                    3", "TFORM1  = '4A'",
      "TFORM2  = '1B'", "TFORM3  = '1E'", "END",
    ],
    Bytes::make(9, b'\x00'),
  )
  let table = @moonastrofits.parse_binary_table(
    @moonastrofits.parse_fits(data).unwrap().hdus[1],
  ).unwrap()
  assert_true(
    @moonastrofits.encode_binary_rows(table, [])
    is Err(@moonastrofits.InvalidTableRowCount(1, 0)),
  )
  assert_true(
    @moonastrofits.encode_binary_row(table, [@moonastrofits.Text("M31")])
    is Err(@moonastrofits.InvalidTableCellCount(3, 1)),
  )
  assert_true(
    @moonastrofits.encode_binary_row(table, [
      @moonastrofits.Text("M31"),
      @moonastrofits.Text("wrong"),
      @moonastrofits.Reals([1.0]),
    ])
    is Err(@moonastrofits.InvalidTableCell(2, _)),
  )
  assert_true(
    @moonastrofits.encode_binary_row(table, [
      @moonastrofits.Text("M31"),
      @moonastrofits.Integers([256L]),
      @moonastrofits.Reals([1.0]),
    ])
    is Err(@moonastrofits.InvalidTableCell(2, _)),
  )
  assert_true(
    @moonastrofits.encode_binary_row(table, [
      @moonastrofits.Text("TOO LONG"),
      @moonastrofits.Integers([1L]),
      @moonastrofits.Reals([1.0]),
    ])
    is Err(@moonastrofits.InvalidTableCell(1, _)),
  )
  assert_true(
    @moonastrofits.encode_binary_row(table, [
      @moonastrofits.Text("星"),
      @moonastrofits.Integers([1L]),
      @moonastrofits.Reals([1.0]),
    ])
    is Err(@moonastrofits.InvalidTableCell(1, _)),
  )
  assert_true(
    @moonastrofits.encode_binary_row(table, [
      @moonastrofits.Text("M31"),
      @moonastrofits.Integers([1L]),
      @moonastrofits.Reals([1.7976931348623157e308]),
    ])
    is Err(@moonastrofits.InvalidTableCell(3, _)),
  )
}

///|
test "reject caller-constructed table layouts before encoding" {
  let table : @moonastrofits.BinaryTable = {
    columns: [
      {
        index: 1,
        name: None,
        format: "1B",
        repeat: 1,
        offset: 1,
        width: 1,
        kind: @moonastrofits.UnsignedByte,
      },
    ],
    row_length: 1,
    row_count: 1,
    data_offset: 0,
  }
  assert_true(
    @moonastrofits.encode_binary_row(table, [@moonastrofits.Integers([1L])])
    is Err(@moonastrofits.InvalidTableCell(1, _)),
  )
}

///|
test "decode and encode tri-state logical table cells" {
  let cards = [
    "XTENSION= 'BINTABLE'", "BITPIX  =                    8", "NAXIS   =                    2",
    "NAXIS1  =                    4", "NAXIS2  =                    1", "PCOUNT  =                    0",
    "GCOUNT  =                    1", "TFIELDS =                    2", "TTYPE1  = 'FLAGS'",
    "TFORM1  = '3L'", "TTYPE2  = 'QUALITY'", "TFORM2  = '1B'", "END",
  ]
  let data = binary_table_file(cards, b"TF\x00\x07")
  let table = @moonastrofits.parse_binary_table(
    @moonastrofits.parse_fits(data).unwrap().hdus[1],
  ).unwrap()
  let row = [
    @moonastrofits.Logicals([Some(true), Some(false), None]),
    @moonastrofits.Integers([7L]),
  ]
  assert_eq(@moonastrofits.decode_binary_row(data, table, 0).unwrap(), row)
  assert_eq(
    @moonastrofits.encode_binary_row(table, row).unwrap(),
    b"TF\x00\x07",
  )
  assert_true(
    @moonastrofits.encode_binary_row(table, [
      @moonastrofits.Logicals([Some(true)]),
      @moonastrofits.Integers([7L]),
    ])
    is Err(@moonastrofits.InvalidTableCell(1, _)),
  )
}

///|
test "reject illegal logical bytes" {
  let data = binary_table_file(
    [
      "XTENSION= 'BINTABLE'", "BITPIX  =                    8", "NAXIS   =                    2",
      "NAXIS1  =                    1", "NAXIS2  =                    1", "PCOUNT  =                    0",
      "GCOUNT  =                    1", "TFIELDS =                    1", "TFORM1  = '1L'",
      "END",
    ],
    b"X",
  )
  let table = @moonastrofits.parse_binary_table(
    @moonastrofits.parse_fits(data).unwrap().hdus[1],
  ).unwrap()
  assert_true(
    @moonastrofits.decode_binary_row(data, table, 0)
    is Err(@moonastrofits.InvalidTableCell(1, _)),
  )
}

///|
test "preserve zero-repeat empty table fields" {
  let data = binary_table_file(
    [
      "XTENSION= 'BINTABLE'", "BITPIX  =                    8", "NAXIS   =                    2",
      "NAXIS1  =                    1", "NAXIS2  =                    1", "PCOUNT  =                    0",
      "GCOUNT  =                    1", "TFIELDS =                    2", "TFORM1  = '0L'",
      "TFORM2  = '1B'", "END",
    ],
    b"\x09",
  )
  let table = @moonastrofits.parse_binary_table(
    @moonastrofits.parse_fits(data).unwrap().hdus[1],
  ).unwrap()
  assert_eq(table.columns[0].repeat, 0)
  assert_eq(table.columns[0].width, 0)
  let row = [@moonastrofits.Logicals([]), @moonastrofits.Integers([9L])]
  assert_eq(@moonastrofits.decode_binary_row(data, table, 0).unwrap(), row)
  assert_eq(@moonastrofits.encode_binary_row(table, row).unwrap(), b"\x09")
}

///|
test "decode and encode packed bit-array columns" {
  let cards = [
    "XTENSION= 'BINTABLE'", "BITPIX  =                    8", "NAXIS   =                    2",
    "NAXIS1  =                    3", "NAXIS2  =                    1", "PCOUNT  =                    0",
    "GCOUNT  =                    1", "TFIELDS =                    2", "TTYPE1  = 'MASK'",
    "TFORM1  = '9X'", "TTYPE2  = 'QUALITY'", "TFORM2  = '1B'", "END",
  ]
  let data = binary_table_file(cards, b"\xB2\x80\x07")
  let table = @moonastrofits.parse_binary_table(
    @moonastrofits.parse_fits(data).unwrap().hdus[1],
  ).unwrap()
  assert_eq(table.columns[0].kind, @moonastrofits.Bit)
  assert_eq(table.columns[0].repeat, 9)
  assert_eq(table.columns[0].width, 2)
  assert_eq(table.columns[1].offset, 2)
  let row = [
    @moonastrofits.Bits([
      true, false, true, true, false, false, true, false, true,
    ]),
    @moonastrofits.Integers([7L]),
  ]
  assert_eq(@moonastrofits.decode_binary_row(data, table, 0).unwrap(), row)
  assert_eq(
    @moonastrofits.encode_binary_row(table, row).unwrap(),
    b"\xB2\x80\x07",
  )
}

///|
test "bit-array encoding clears padding and checks repeat count" {
  let data = binary_table_file(
    [
      "XTENSION= 'BINTABLE'", "BITPIX  =                    8", "NAXIS   =                    2",
      "NAXIS1  =                    1", "NAXIS2  =                    1", "PCOUNT  =                    0",
      "GCOUNT  =                    1", "TFIELDS =                    1", "TFORM1  = '3X'",
      "END",
    ],
    b"\xFF",
  )
  let table = @moonastrofits.parse_binary_table(
    @moonastrofits.parse_fits(data).unwrap().hdus[1],
  ).unwrap()
  assert_eq(@moonastrofits.decode_binary_row(data, table, 0).unwrap(), [
    @moonastrofits.Bits([true, true, true]),
  ])
  assert_eq(
    @moonastrofits.encode_binary_row(table, [
      @moonastrofits.Bits([true, false, true]),
    ]).unwrap(),
    b"\xA0",
  )
  assert_true(
    @moonastrofits.encode_binary_row(table, [@moonastrofits.Bits([true])])
    is Err(@moonastrofits.InvalidTableCell(1, _)),
  )
}

///|
test "preserve zero-repeat empty bit columns" {
  let data = binary_table_file(
    [
      "XTENSION= 'BINTABLE'", "BITPIX  =                    8", "NAXIS   =                    2",
      "NAXIS1  =                    1", "NAXIS2  =                    1", "PCOUNT  =                    0",
      "GCOUNT  =                    1", "TFIELDS =                    2", "TFORM1  = '0X'",
      "TFORM2  = '1B'", "END",
    ],
    b"\x09",
  )
  let table = @moonastrofits.parse_binary_table(
    @moonastrofits.parse_fits(data).unwrap().hdus[1],
  ).unwrap()
  assert_eq(table.columns[0].width, 0)
  let row = [@moonastrofits.Bits([]), @moonastrofits.Integers([9L])]
  assert_eq(@moonastrofits.decode_binary_row(data, table, 0).unwrap(), row)
  assert_eq(@moonastrofits.encode_binary_row(table, row).unwrap(), b"\x09")
}
