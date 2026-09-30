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
fn table_column_width(
  kind : TableColumnKind,
  repeat : Int,
) -> Result[Int, FitsError] {
  match kind {
    Bit => Ok(repeat / 8 + (if repeat % 8 == 0 { 0 } else { 1 }))
    Variable32(_) => checked_product(repeat, 8, "P descriptor width")
    Variable64(_) => checked_product(repeat, 16, "Q descriptor width")
    _ => {
      let unit_width = match kind {
        Ascii | Logical | UnsignedByte => 1
        Int16 => 2
        Int32 | Float32 => 4
        Int64 | Float64 => 8
        Bit => abort("bit width handled above")
        Variable32(_) | Variable64(_) => abort("descriptor width handled above")
      }
      checked_product(repeat, unit_width, "binary-table column width")
    }
  }
}

///|
fn validate_table_columns(table : BinaryTable) -> Result[Unit, FitsError] {
  if table.row_length < 0 {
    return Err(InvalidParameter("NAXIS1", table.row_length))
  }
  let mut offset = 0
  for column in table.columns {
    if column.repeat < 0 {
      return Err(InvalidTableCell(column.index, "repeat must be non-negative"))
    }
    match column.kind {
      Variable32(element) | Variable64(element) => {
        if column.repeat > 1 {
          return Err(
            InvalidTableCell(column.index, "descriptor repeat must be 0 or 1"),
          )
        }
        match element {
          Variable32(_) | Variable64(_) =>
            return Err(
              InvalidTableCell(column.index, "nested descriptors are invalid"),
            )
          _ => ()
        }
      }
      _ =>
        match column.max_elements {
          Some(_) =>
            return Err(
              InvalidTableCell(
                column.index,
                "fixed field cannot have a heap maximum",
              ),
            )
          None => ()
        }
    }
    if column.offset != offset {
      return Err(
        InvalidTableCell(
          column.index,
          "expected byte offset \{offset}, got \{column.offset}",
        ),
      )
    }
    let width = match table_column_width(column.kind, column.repeat) {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    if column.width != width {
      return Err(
        InvalidTableCell(
          column.index,
          "expected width \{width}, got \{column.width}",
        ),
      )
    }
    offset = match checked_sum(offset, width, "binary-table row width") {
      Err(error) => return Err(error)
      Ok(value) => value
    }
  }
  if offset != table.row_length {
    return Err(InvalidTableRowWidth(table.row_length, offset))
  }
  let row_bytes = match
    checked_product(table.row_length, table.row_count, "binary-table row area") {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let rows_end = match
    checked_sum(table.data_offset, row_bytes, "binary-table row end") {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  if table.heap_offset < rows_end || table.heap_length < 0 {
    return Err(InvalidTableCell(0, "heap overlaps rows or has negative length"))
  }
  match
    checked_sum(table.heap_offset, table.heap_length, "binary-table heap end") {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  Ok(())
}

///|
fn table_element_kind(
  code : Char,
  keyword : String,
  format : String,
) -> Result[TableColumnKind, FitsError] {
  match code {
    'A' => Ok(Ascii)
    'L' => Ok(Logical)
    'X' => Ok(Bit)
    'B' => Ok(UnsignedByte)
    'I' => Ok(Int16)
    'J' => Ok(Int32)
    'K' => Ok(Int64)
    'E' => Ok(Float32)
    'D' => Ok(Float64)
    _ => Err(UnsupportedTableFormat(keyword, format))
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
  if position >= chars.length() {
    return Err(UnsupportedTableFormat(format_keyword, format))
  }
  let code = chars[position]
  let (kind, max_elements) = if code == 'P' || code == 'Q' {
    if repeat > 1 || position + 1 >= chars.length() {
      return Err(UnsupportedTableFormat(format_keyword, format))
    }
    let element = match
      table_element_kind(chars[position + 1], format_keyword, format) {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    position = position + 2
    let maximum = if position == chars.length() {
      None
    } else {
      if chars[position] != '(' ||
        chars[chars.length() - 1] != ')' ||
        position + 2 >= chars.length() {
        return Err(UnsupportedTableFormat(format_keyword, format))
      }
      position = position + 1
      let mut value = 0
      while position < chars.length() - 1 {
        let digit = chars[position].to_int() - '0'.to_int()
        if digit < 0 || digit > 9 {
          return Err(UnsupportedTableFormat(format_keyword, format))
        }
        if value > (2147483647 - digit) / 10 {
          return Err(SizeOverflow("binary-table maximum element count"))
        }
        value = value * 10 + digit
        position = position + 1
      }
      Some(value)
    }
    (
      if code == 'P' {
        Variable32(element)
      } else {
        Variable64(element)
      },
      maximum,
    )
  } else {
    if position + 1 != chars.length() {
      return Err(UnsupportedTableFormat(format_keyword, format))
    }
    let element = match table_element_kind(code, format_keyword, format) {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    (element, None)
  }
  let width = match table_column_width(kind, repeat) {
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
  Ok({ index, name, format, repeat, offset, width, kind, max_elements, })
}

///|
/// Parse the schema and heap geometry of a `BINTABLE` extension.
///
/// Supports fixed `A/L/X/B/I/J/K/E/D` fields and `P/Q` descriptors for these
/// element types. Complex values remain unsupported.
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
  for (keyword, expected) in [("BITPIX", 8), ("NAXIS", 2), ("GCOUNT", 1)] {
    let actual = match required_table_integer(hdu.header, keyword) {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    if actual != expected {
      return Err(InvalidParameter(keyword, actual))
    }
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
  let pcount = match required_table_integer(hdu.header, "PCOUNT") {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let expected_length = match
    checked_sum(row_bytes, pcount, "binary-table data length") {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  if expected_length != hdu.data_length {
    return Err(InvalidDataLength(expected_length, hdu.data_length))
  }
  let theap = match hdu.header.get("THEAP") {
    None => row_bytes
    Some(card) =>
      match parse_card_integer(card) {
        Err(error) => return Err(error)
        Ok(value) => value
      }
  }
  if theap < row_bytes || theap > hdu.data_length {
    return Err(InvalidParameter("THEAP", theap))
  }
  let heap_offset = match checked_sum(hdu.data_offset, theap, "heap offset") {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let table = {
    columns,
    row_length,
    row_count,
    data_offset: hdu.data_offset,
    heap_offset,
    heap_length: hdu.data_length - theap,
  }
  match validate_table_columns(table) {
    Err(error) => Err(error)
    Ok(_) => Ok(table)
  }
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
fn decode_fixed_cell(
  data : Bytes,
  start : Int,
  kind : TableColumnKind,
  count : Int,
  column_index : Int,
) -> Result[TableValue, FitsError] {
  match kind {
    Ascii =>
      match decode_ascii_cell(data, start, count) {
        Err(error) => return Err(error)
        Ok(value) => Ok(Text(value))
      }
    Logical => {
      let values = []
      for index = 0; index < count; index = index + 1 {
        match data[start + index] {
          b'T' => values.push(Some(true))
          b'F' => values.push(Some(false))
          b'\x00' => values.push(None)
          byte =>
            return Err(
              InvalidTableCell(
                column_index,
                "illegal logical byte \{byte.to_int()} at element \{index}",
              ),
            )
        }
      }
      Ok(Logicals(values))
    }
    Bit => {
      let values = []
      for index = 0; index < count; index = index + 1 {
        let byte = data[start + index / 8]
        let mask = 1 << (7 - index % 8)
        values.push((byte.to_int() & mask) != 0)
      }
      Ok(Bits(values))
    }
    UnsignedByte => {
      let values = []
      for index = 0; index < count; index = index + 1 {
        values.push(data[start + index].to_int64())
      }
      Ok(Integers(values))
    }
    Int16 => {
      let values = []
      for index = 0; index < count; index = index + 1 {
        values.push(read_int16_be(data, start + index * 2))
      }
      Ok(Integers(values))
    }
    Int32 => {
      let values = []
      for index = 0; index < count; index = index + 1 {
        values.push(read_int32_be(data, start + index * 4))
      }
      Ok(Integers(values))
    }
    Int64 => {
      let values = []
      for index = 0; index < count; index = index + 1 {
        values.push(read_int64_be(data, start + index * 8))
      }
      Ok(Integers(values))
    }
    Float32 => {
      let values = []
      for index = 0; index < count; index = index + 1 {
        values.push(read_float32_be(data, start + index * 4))
      }
      Ok(Reals(values))
    }
    Float64 => {
      let values = []
      for index = 0; index < count; index = index + 1 {
        values.push(read_float64_be(data, start + index * 8))
      }
      Ok(Reals(values))
    }
    Variable32(_) | Variable64(_) =>
      Err(InvalidTableCell(column_index, "nested descriptors are invalid"))
  }
}

///|
/// Decode one zero-based binary-table row into typed cells.
pub fn decode_binary_row(
  data : Bytes,
  table : BinaryTable,
  row_index : Int,
) -> Result[Array[TableValue], FitsError] {
  match validate_table_columns(table) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
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
    let value = match column.kind {
      Variable32(element) | Variable64(element) =>
        decode_heap_cell(data, table, row_index, column, start, element)
      kind => decode_fixed_cell(data, start, kind, column.repeat, column.index)
    }
    match value {
      Err(error) => return Err(error)
      Ok(cell) => cells.push(cell)
    }
  }
  Ok(cells)
}

///|
fn invalid_cell_type(column : TableColumn) -> FitsError {
  let expected = match column.kind {
    Ascii => "text"
    Logical => "logical array"
    Bit => "bit array"
    UnsignedByte | Int16 | Int32 | Int64 => "integer array"
    Float32 | Float64 => "real array"
    Variable32(_) | Variable64(_) => "heap-backed array"
  }
  InvalidTableCell(column.index, "expected \{expected}")
}

///|
fn encode_logical_cell(
  output : Array[Byte],
  column : TableColumn,
  values : Array[Bool?],
) -> Result[Unit, FitsError] {
  if values.length() != column.repeat {
    return Err(
      InvalidTableCell(
        column.index,
        "requires \{column.repeat} logical values, got \{values.length()}",
      ),
    )
  }
  for value in values {
    output.push(
      match value {
        Some(true) => b'T'
        Some(false) => b'F'
        None => b'\x00'
      },
    )
  }
  Ok(())
}

///|
fn encode_ascii_cell(
  output : Array[Byte],
  column : TableColumn,
  text : String,
) -> Result[Unit, FitsError] {
  let chars = text.to_array()
  if chars.length() > column.repeat {
    return Err(
      InvalidTableCell(
        column.index,
        "text has \{chars.length()} characters; maximum is \{column.repeat}",
      ),
    )
  }
  for ch in chars {
    let value = ch.to_int()
    if value < 0x20 || value > 0x7e {
      return Err(InvalidTableCell(column.index, "text must be printable ASCII"))
    }
    output.push(value.to_byte())
  }
  for index = chars.length(); index < column.repeat; index = index + 1 {
    output.push(b' ')
  }
  Ok(())
}

///|
fn encode_integer_cell(
  output : Array[Byte],
  column : TableColumn,
  values : Array[Int64],
) -> Result[Unit, FitsError] {
  if values.length() != column.repeat {
    return Err(
      InvalidTableCell(
        column.index,
        "requires \{column.repeat} integers, got \{values.length()}",
      ),
    )
  }
  let bitpix = match column.kind {
    UnsignedByte => 8
    Int16 => 16
    Int32 => 32
    Int64 => 64
    _ => return Err(invalid_cell_type(column))
  }
  let width = match table_column_width(column.kind, 1) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  for value in values {
    if !integer_value_fits(value, bitpix) {
      return Err(
        InvalidTableCell(
          column.index,
          "integer \{value} is outside the \{column.format} range",
        ),
      )
    }
    append_integer_be(output, value, width)
  }
  Ok(())
}

///|
fn encode_bit_cell(
  output : Array[Byte],
  column : TableColumn,
  values : Array[Bool],
) -> Result[Unit, FitsError] {
  if values.length() != column.repeat {
    return Err(
      InvalidTableCell(
        column.index,
        "requires \{column.repeat} bits, got \{values.length()}",
      ),
    )
  }
  for byte_index = 0; byte_index < column.width; byte_index = byte_index + 1 {
    let mut byte = 0
    for bit_index = 0; bit_index < 8; bit_index = bit_index + 1 {
      let value_index = byte_index * 8 + bit_index
      if value_index < values.length() && values[value_index] {
        byte = byte | (1 << (7 - bit_index))
      }
    }
    output.push(byte.to_byte())
  }
  Ok(())
}

///|
fn encode_real_cell(
  output : Array[Byte],
  column : TableColumn,
  values : Array[Double],
) -> Result[Unit, FitsError] {
  if values.length() != column.repeat {
    return Err(
      InvalidTableCell(
        column.index,
        "requires \{column.repeat} real values, got \{values.length()}",
      ),
    )
  }
  for index, value in values {
    match column.kind {
      Float32 => {
        let narrowed = Float::from_double(value)
        if !value.is_nan() && !value.is_inf() && narrowed.is_inf() {
          return Err(
            InvalidTableCell(
              column.index,
              "real value \{index} overflows binary32",
            ),
          )
        }
        append_uint32_be(output, narrowed.reinterpret_as_uint())
      }
      Float64 => append_uint64_be(output, value.reinterpret_as_uint64())
      _ => return Err(invalid_cell_type(column))
    }
  }
  Ok(())
}

///|
/// Encode one fixed-width binary-table row in FITS network byte order.
///
/// Text is padded with spaces to its declared width. Numeric cells must supply
/// exactly the column repeat count, and narrowing conversions are checked.
pub fn encode_binary_row(
  table : BinaryTable,
  cells : Array[TableValue],
) -> Result[Bytes, FitsError] {
  match validate_table_columns(table) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if cells.length() != table.columns.length() {
    return Err(InvalidTableCellCount(table.columns.length(), cells.length()))
  }
  let output = Array(capacity=table.row_length)
  for index, column in table.columns {
    let result = match column.kind {
      Ascii =>
        match cells[index] {
          Text(text) => encode_ascii_cell(output, column, text)
          _ => Err(invalid_cell_type(column))
        }
      Logical =>
        match cells[index] {
          Logicals(values) => encode_logical_cell(output, column, values)
          _ => Err(invalid_cell_type(column))
        }
      Bit =>
        match cells[index] {
          Bits(values) => encode_bit_cell(output, column, values)
          _ => Err(invalid_cell_type(column))
        }
      UnsignedByte | Int16 | Int32 | Int64 =>
        match cells[index] {
          Integers(values) => encode_integer_cell(output, column, values)
          _ => Err(invalid_cell_type(column))
        }
      Float32 | Float64 =>
        match cells[index] {
          Reals(values) => encode_real_cell(output, column, values)
          _ => Err(invalid_cell_type(column))
        }
      Variable32(_) | Variable64(_) =>
        Err(UnsupportedTableFormat("TFORM\{column.index}", column.format))
    }
    match result {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  Ok(Bytes::from_array(output))
}

///|
/// Encode every row of a fixed-width binary table as one contiguous data unit.
pub fn encode_binary_rows(
  table : BinaryTable,
  rows : Array[Array[TableValue]],
) -> Result[Bytes, FitsError] {
  match validate_table_columns(table) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if table.row_count < 0 {
    return Err(InvalidParameter("NAXIS2", table.row_count))
  }
  if rows.length() != table.row_count {
    return Err(InvalidTableRowCount(table.row_count, rows.length()))
  }
  let byte_length = match
    checked_product(table.row_length, table.row_count, "binary-table row area") {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let output = Array(capacity=byte_length)
  for row in rows {
    let encoded = match encode_binary_row(table, row) {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    append_bytes(output, encoded)
  }
  Ok(Bytes::from_array(output))
}
