///|
test "build a complete binary-table extension with a packed Q heap" {
  let fields : Array[@moonastrofits.TableField] = [
    { name: Some("INDEX"), format: "1J", },
    { name: Some("SPECTRUM"), format: "1QK(3)", },
  ]
  let rows = [
    [@moonastrofits.Integers([1L]), @moonastrofits.Integers([5L, -7L])],
    [@moonastrofits.Integers([2L]), @moonastrofits.Integers([8L])],
  ]
  let extension = @moonastrofits.encode_binary_table_extension(fields, rows).unwrap()
  assert_eq(extension.length(), 5760)
  let file = empty_primary_hdu() + extension
  let parsed = @moonastrofits.parse_fits(file).unwrap()
  assert_eq(parsed.hdus.length(), 2)
  let hdu = parsed.hdus[1]
  assert_eq(hdu.header.get("NAXIS1").unwrap().value, Some("20"))
  assert_eq(hdu.header.get("NAXIS2").unwrap().value, Some("2"))
  assert_eq(hdu.header.get("PCOUNT").unwrap().value, Some("24"))
  assert_eq(hdu.header.get("TFIELDS").unwrap().value, Some("2"))
  let table = @moonastrofits.parse_binary_table(hdu).unwrap()
  assert_eq(table.heap_length, 24)
  assert_eq(table.columns[1].name, Some("SPECTRUM"))
  assert_eq(@moonastrofits.decode_binary_row(file, table, 0).unwrap(), rows[0])
  assert_eq(@moonastrofits.decode_binary_row(file, table, 1).unwrap(), rows[1])
}

///|
test "table builder escapes quoted names and supports empty arrays" {
  let fields : Array[@moonastrofits.TableField] = [
    { name: Some("OBSERVER'S DATA"), format: "1PJ(2)", },
  ]
  let rows = [[@moonastrofits.Integers([])]]
  let extension = @moonastrofits.encode_binary_table_extension(fields, rows).unwrap()
  let file = empty_primary_hdu() + extension
  let table = @moonastrofits.parse_binary_table(
    @moonastrofits.parse_fits(file).unwrap().hdus[1],
  ).unwrap()
  assert_eq(table.columns[0].name, Some("OBSERVER'S DATA"))
  assert_eq(table.heap_length, 0)
  assert_eq(@moonastrofits.decode_binary_row(file, table, 0).unwrap(), rows[0])
}

///|
test "table builder rejects malformed schema and row data" {
  assert_true(
    @moonastrofits.encode_binary_table_extension(
      [{ name: None, format: "1P", }],
      [[@moonastrofits.Integers([])]],
    )
    is Err(@moonastrofits.UnsupportedTableFormat("TFORM1", "1P")),
  )
  assert_true(
    @moonastrofits.encode_binary_table_extension(
      [{ name: None, format: "1J", }],
      [[]],
    )
    is Err(@moonastrofits.InvalidTableCellCount(1, 0)),
  )
  assert_true(
    @moonastrofits.encode_binary_table_extension(
      [{ name: None, format: "1PJ(1)", }],
      [[@moonastrofits.Integers([1L, 2L])]],
    )
    is Err(@moonastrofits.InvalidHeapDescriptor(1, 0, _)),
  )
  assert_true(
    @moonastrofits.encode_binary_table_extension(
      [{ name: None, format: "1J", }],
      [[@moonastrofits.Reals([1.0])]],
    )
    is Err(@moonastrofits.InvalidTableCell(1, _)),
  )
}
