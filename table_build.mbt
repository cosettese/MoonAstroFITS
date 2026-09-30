///|
fn push_value_card(
  cards : Array[Card],
  keyword : String,
  value : String,
) -> Unit {
  cards.push({
    keyword,
    value: Some(value),
    comment: None,
    record_index: cards.length(),
  })
}

///|
fn quoted_table_text(value : String) -> String {
  let output = StringBuilder()
  output.write_char('\'')
  for ch in value {
    output.write_char(ch)
    if ch == '\'' {
      output.write_char('\'')
    }
  }
  output.write_char('\'')
  output.to_string()
}

///|
fn push_table_fields(cards : Array[Card], fields : Array[TableField]) -> Unit {
  for index, field in fields {
    let number = index + 1
    match field.name {
      None => ()
      Some(name) =>
        push_value_card(cards, "TTYPE\{number}", quoted_table_text(name))
    }
    push_value_card(cards, "TFORM\{number}", quoted_table_text(field.format))
  }
}

///|
fn build_table_header(
  fields : Array[TableField],
  row_length : Int,
  row_count : Int,
  heap_length : Int,
) -> Header {
  let cards : Array[Card] = []
  push_value_card(cards, "XTENSION", "'BINTABLE'")
  push_value_card(cards, "BITPIX", "8")
  push_value_card(cards, "NAXIS", "2")
  push_value_card(cards, "NAXIS1", "\{row_length}")
  push_value_card(cards, "NAXIS2", "\{row_count}")
  push_value_card(cards, "PCOUNT", "\{heap_length}")
  push_value_card(cards, "GCOUNT", "1")
  push_value_card(cards, "TFIELDS", "\{fields.length()}")
  push_table_fields(cards, fields)
  cards.push({
    keyword: "END",
    value: None,
    comment: None,
    record_index: cards.length(),
  })
  { cards, data_offset: 0, }
}

///|
/// Construct a complete BINTABLE extension from column formats and typed rows.
/// Row width, row count, PCOUNT and P/Q heap offsets are derived automatically;
/// the heap is packed without a THEAP gap. The result includes a canonical
/// header and FITS block padding, ready to append after a primary HDU.
///
/// # Example
/// ```mbt check
/// test {
///   let extension = @moonastrofits.encode_binary_table_extension(
///     [{ name: Some("FLUX"), format: "1E", }],
///     [[@moonastrofits.Reals([1.5])]],
///   ).unwrap()
///   assert_eq(extension.length(), 5760)
/// }
/// ```
pub fn encode_binary_table_extension(
  fields : Array[TableField],
  rows : Array[Array[TableValue]],
) -> Result[Bytes, FitsError] {
  if fields.length() > 999 {
    return Err(InvalidParameter("TFIELDS", fields.length()))
  }
  let schema = build_table_header(fields, 0, rows.length(), 0)
  let columns : Array[TableColumn] = []
  let mut row_length = 0
  for index = 0; index < fields.length(); index = index + 1 {
    let column = match parse_table_column(schema, index + 1, row_length) {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    row_length = match
      checked_sum(row_length, column.width, "binary-table row width") {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    columns.push(column)
  }
  let row_bytes = match
    checked_product(row_length, rows.length(), "binary-table row area") {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let mut heap_length = 0
  for row_index, row in rows {
    if row.length() != columns.length() {
      return Err(InvalidTableCellCount(columns.length(), row.length()))
    }
    for index, column in columns {
      match column.kind {
        Variable32(element) | Variable64(element) => {
          let count = heap_cell_count(row[index])
          if column.repeat == 0 && count != 0 {
            return Err(
              InvalidHeapDescriptor(
                column.index,
                row_index,
                "zero-repeat descriptor requires an empty cell",
              ),
            )
          }
          match column.max_elements {
            Some(maximum) if count > maximum =>
              return Err(
                InvalidHeapDescriptor(
                  column.index,
                  row_index,
                  "element count \{count} exceeds TFORM maximum \{maximum}",
                ),
              )
            _ => ()
          }
          let width = match table_column_width(element, count) {
            Err(error) => return Err(error)
            Ok(value) => value
          }
          heap_length = match
            checked_sum(heap_length, width, "binary-table heap length") {
            Err(error) => return Err(error)
            Ok(value) => value
          }
        }
        _ => ()
      }
    }
  }
  let table : BinaryTable = {
    columns,
    row_length,
    row_count: rows.length(),
    data_offset: 0,
    heap_offset: row_bytes,
    heap_length,
  }
  let data = match encode_binary_table_data(table, rows) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let header = build_table_header(
    fields,
    row_length,
    rows.length(),
    heap_length,
  )
  encode_extension_hdu(header, data)
}
