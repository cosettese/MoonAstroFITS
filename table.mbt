///|
fn required_table_integer(
  header : Header,
  keyword : String,
) -> Result[Int, FitsError] {
  match header.get(keyword) {
    None => Err(MissingKeyword(keyword))
    Some(card) => parse_card_integer(card)
  }
}

///|
fn parse_table_column(
  header : Header,
  index : Int,
  offset : Int,
) -> Result[TableColumn, FitsError] {
  let format_keyword = "TFORM\{index}"
  let format = match header.get(format_keyword) {
    None => return Err(MissingKeyword(format_keyword))
    Some(card) =>
      match parse_card_string(card) {
        Err(error) => return Err(error)
        Ok(value) => value
      }
  }
  let chars = format.to_array()
  if chars.length() == 0 {
    return Err(UnsupportedTableFormat(format_keyword, format))
  }
  let mut position = 0
  let mut repeat = 0
  while position < chars.length() &&
        chars[position] >= '0' &&
        chars[position] <= '9' {
    let digit = chars[position].to_int() - '0'.to_int()
    if repeat > (2147483647 - digit) / 10 {
      return Err(SizeOverflow("binary-table repeat count"))
    }
    repeat = repeat * 10 + digit
    position = position + 1
  }
  if position == 0 {
    repeat = 1
  }
  if repeat < 1 || position + 1 != chars.length() {
    return Err(UnsupportedTableFormat(format_keyword, format))
  }
  let code = chars[position]
  let kind = match code {
    'A' => Ascii
    'B' => UnsignedByte
    'I' => Int16
    'J' => Int32
    'K' => Int64
    'E' => Float32
    'D' => Float64
    _ => return Err(UnsupportedTableFormat(format_keyword, format))
  }
  let unit_width = match code {
    'A' | 'B' => 1
    'I' => 2
    'J' | 'E' => 4
    'K' | 'D' => 8
    _ => return Err(UnsupportedTableFormat(format_keyword, format))
  }
  let width = match
    checked_product(repeat, unit_width, "binary-table column width") {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let name_keyword = "TTYPE\{index}"
  let name = match header.get(name_keyword) {
    None => None
    Some(card) =>
      match parse_card_string(card) {
        Err(error) => return Err(error)
        Ok(value) => Some(value)
      }
  }
  Ok({ index, name, format, repeat, offset, width, kind, })
}

///|
/// Parse the fixed-width schema of a `BINTABLE` extension.
///
/// The initial slice supports scalar and repeated `A`, `B`, `I`, `J`, `K`,
/// `E`, and `D` fields. Bit arrays, logical values, complex values, and heap
/// descriptors are rejected explicitly rather than decoded ambiguously.
pub fn parse_binary_table(hdu : Hdu) -> Result[BinaryTable, FitsError] {
  match hdu.kind {
    OtherExtension("BINTABLE") => ()
    _ => return Err(NotBinaryTable(hdu.index))
  }
  let row_length = match required_table_integer(hdu.header, "NAXIS1") {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let row_count = match required_table_integer(hdu.header, "NAXIS2") {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let field_count = match required_table_integer(hdu.header, "TFIELDS") {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  if row_length < 0 {
    return Err(InvalidParameter("NAXIS1", row_length))
  }
  if row_count < 0 {
    return Err(InvalidParameter("NAXIS2", row_count))
  }
  if field_count < 0 || field_count > 999 {
    return Err(InvalidParameter("TFIELDS", field_count))
  }
  let columns = []
  let mut offset = 0
  for index = 1; index <= field_count; index = index + 1 {
    let column = match parse_table_column(hdu.header, index, offset) {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    offset = match checked_sum(offset, column.width, "binary-table row width") {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    columns.push(column)
  }
  if offset != row_length {
    return Err(InvalidTableRowWidth(row_length, offset))
  }
  let row_bytes = match
    checked_product(row_length, row_count, "binary-table row area") {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  if row_bytes > hdu.data_length {
    return Err(InvalidDataLength(row_bytes, hdu.data_length))
  }
  Ok({ columns, row_length, row_count, data_offset: hdu.data_offset, })
}

///|
fn decode_ascii_cell(
  data : Bytes,
  offset : Int,
  width : Int,
) -> Result[String, FitsError] {
  let output = StringBuilder()
  for index = 0; index < width; index = index + 1 {
    let byte = data[offset + index]
    if byte < b'\x20' || byte > b'\x7E' {
      return Err(NonAscii(offset + index, byte))
    }
    output.write_char(byte.to_int().to_char().unwrap())
  }
  Ok(output.to_string().trim_end(chars=" ").to_owned())
}

///|
/// Decode one zero-based fixed-width binary-table row into typed cells.
pub fn decode_binary_row(
  data : Bytes,
  table : BinaryTable,
  row_index : Int,
) -> Result[Array[TableValue], FitsError] {
  if row_index < 0 || row_index >= table.row_count {
    return Err(TableRowOutOfRange(row_index, table.row_count))
  }
  let relative = match
    checked_product(row_index, table.row_length, "binary-table row offset") {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let row_offset = match
    checked_sum(table.data_offset, relative, "binary-table absolute row offset") {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  if row_offset < 0 || row_offset > data.length() {
    return Err(Truncated(row_offset, table.row_length, 0))
  }
  let available = data.length() - row_offset
  if table.row_length < 0 || table.row_length > available {
    return Err(Truncated(row_offset, table.row_length, available))
  }
  let cells = []
  for column in table.columns {
    let field_end = match
      checked_sum(column.offset, column.width, "binary-table field boundary") {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    if column.offset < 0 || column.width < 0 || field_end > table.row_length {
      return Err(InvalidTableRowWidth(table.row_length, field_end))
    }
    let start = row_offset + column.offset
    match column.kind {
      Ascii =>
        match decode_ascii_cell(data, start, column.width) {
          Err(error) => return Err(error)
          Ok(value) => cells.push(Text(value))
        }
      UnsignedByte => {
        let values = []
        for index = 0; index < column.repeat; index = index + 1 {
          values.push(data[start + index].to_int64())
        }
        cells.push(Integers(values))
      }
      Int16 => {
        let values = []
        for index = 0; index < column.repeat; index = index + 1 {
          values.push(read_int16_be(data, start + index * 2))
        }
        cells.push(Integers(values))
      }
      Int32 => {
        let values = []
        for index = 0; index < column.repeat; index = index + 1 {
          values.push(read_int32_be(data, start + index * 4))
        }
        cells.push(Integers(values))
      }
      Int64 => {
        let values = []
        for index = 0; index < column.repeat; index = index + 1 {
          values.push(read_int64_be(data, start + index * 8))
        }
        cells.push(Integers(values))
      }
      Float32 => {
        let values = []
        for index = 0; index < column.repeat; index = index + 1 {
          values.push(read_float32_be(data, start + index * 4))
        }
        cells.push(Reals(values))
      }
      Float64 => {
        let values = []
        for index = 0; index < column.repeat; index = index + 1 {
          values.push(read_float64_be(data, start + index * 8))
        }
        cells.push(Reals(values))
      }
    }
  }
  Ok(cells)
}
