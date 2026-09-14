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
