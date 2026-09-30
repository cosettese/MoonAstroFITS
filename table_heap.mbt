///|
/// Decode a P/Q descriptor after checking that its referenced bytes are wholly
/// inside the declared heap. A zero-length array has no referenced storage.
fn decode_heap_cell(
  data : Bytes,
  table : BinaryTable,
  row_index : Int,
  column : TableColumn,
  descriptor_start : Int,
  element : TableColumnKind,
) -> Result[TableValue, FitsError] {
  if column.repeat == 0 {
    return decode_heap_payload(data, 0, 0, column, element)
  }
  let (count64, offset64) = match column.kind {
    Variable32(_) =>
      (
        read_int32_be(data, descriptor_start),
        read_int32_be(data, descriptor_start + 4),
      )
    Variable64(_) =>
      (
        read_int64_be(data, descriptor_start),
        read_int64_be(data, descriptor_start + 8),
      )
    _ => return Err(InvalidTableCell(column.index, "expected P/Q descriptor"))
  }
  if count64 < 0L || count64 > 2147483647L {
    return Err(
      InvalidHeapDescriptor(
        column.index,
        row_index,
        "element count is negative or too large",
      ),
    )
  }
  let count = count64.to_int()
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
  if count == 0 {
    return decode_heap_payload(data, 0, 0, column, element)
  }
  if offset64 < 0L || offset64 > 2147483647L {
    return Err(
      InvalidHeapDescriptor(
        column.index,
        row_index,
        "heap offset is negative or too large",
      ),
    )
  }
  let offset = offset64.to_int()
  let byte_length = match table_column_width(element, count) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  if offset > table.heap_length || byte_length > table.heap_length - offset {
    return Err(
      InvalidHeapDescriptor(
        column.index,
        row_index,
        "array extends beyond declared heap",
      ),
    )
  }
  let start = match
    checked_sum(table.heap_offset, offset, "heap array offset") {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  decode_heap_payload(data, start, count, column, element)
}

///|
/// Reuse the fixed-cell decoder so heap and inline values have identical
/// treatment of endianness, logical nulls, ASCII and packed bits.
fn decode_heap_payload(
  data : Bytes,
  start : Int,
  count : Int,
  column : TableColumn,
  element : TableColumnKind,
) -> Result[TableValue, FitsError] {
  let width = match table_column_width(element, count) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let end = match checked_sum(start, width, "heap array end") {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  if start < 0 || start > data.length() || end > data.length() {
    return Err(
      Truncated(
        start,
        width,
        if start <= data.length() {
          data.length() - start
        } else {
          0
        },
      ),
    )
  }
  decode_fixed_cell(data, start, element, count, column.index)
}

///|
fn heap_cell_count(cell : TableValue) -> Int {
  match cell {
    Text(value) => value.to_array().length()
    Logicals(values) => values.length()
    Bits(values) => values.length()
    Integers(values) => values.length()
    Reals(values) => values.length()
  }
}

///|
fn encode_heap_cell(
  row_output : Array[Byte],
  heap_output : Array[Byte],
  column : TableColumn,
  row_index : Int,
  element : TableColumnKind,
  cell : TableValue,
  heap_limit : Int,
) -> Result[Unit, FitsError] {
  let count = heap_cell_count(cell)
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
  if column.repeat == 0 && count != 0 {
    return Err(
      InvalidHeapDescriptor(
        column.index,
        row_index,
        "zero-repeat descriptor requires an empty cell",
      ),
    )
  }
  let width = match table_column_width(element, count) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  if width > heap_limit - heap_output.length() {
    return Err(
      InvalidHeapDescriptor(
        column.index,
        row_index,
        "encoded array exceeds declared heap length",
      ),
    )
  }
  let offset = heap_output.length()
  let payload_column = {
    index: column.index,
    name: column.name,
    format: column.format,
    repeat: count,
    offset: 0,
    width,
    kind: element,
    max_elements: None,
  }
  match encode_fixed_cell(heap_output, payload_column, cell) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if column.repeat == 1 {
    let descriptor_width = match column.kind {
      Variable32(_) => 4
      Variable64(_) => 8
      _ => return Err(InvalidTableCell(column.index, "expected P/Q descriptor"))
    }
    append_integer_be(row_output, count.to_int64(), descriptor_width)
    append_integer_be(row_output, offset.to_int64(), descriptor_width)
  }
  Ok(())
}

///|
/// Encode all rows, an optional THEAP gap, and the heap into one BINTABLE data
/// unit. The supplied table's PCOUNT/THEAP geometry is authoritative: heap
/// payloads are packed in row-major order and unused bytes are zero-filled.
/// This function does not write FITS header cards or 2880-byte HDU padding.
pub fn encode_binary_table_data(
  table : BinaryTable,
  rows : Array[Array[TableValue]],
) -> Result[Bytes, FitsError] {
  match validate_table_columns(table) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if rows.length() != table.row_count {
    return Err(InvalidTableRowCount(table.row_count, rows.length()))
  }
  let row_output = Array(capacity=table.row_length * table.row_count)
  let heap_output : Array[Byte] = []
  for row_index, row in rows {
    if row.length() != table.columns.length() {
      return Err(InvalidTableCellCount(table.columns.length(), row.length()))
    }
    for column_index, column in table.columns {
      let result = match column.kind {
        Variable32(element) | Variable64(element) =>
          encode_heap_cell(
            row_output,
            heap_output,
            column,
            row_index,
            element,
            row[column_index],
            table.heap_length,
          )
        _ => encode_fixed_cell(row_output, column, row[column_index])
      }
      match result {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
    }
  }
  let row_bytes = match
    checked_product(table.row_length, table.row_count, "binary-table row area") {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let heap_start = table.heap_offset - table.data_offset
  let total_length = match
    checked_sum(heap_start, table.heap_length, "binary-table data length") {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let output = Array(capacity=total_length)
  for byte in row_output {
    output.push(byte)
  }
  for index = row_bytes; index < heap_start; index = index + 1 {
    output.push(b'\x00')
  }
  for byte in heap_output {
    output.push(byte)
  }
  for index = heap_output.length(); index < table.heap_length; index = index + 1 {
    output.push(b'\x00')
  }
  Ok(Bytes::from_array(output))
}
