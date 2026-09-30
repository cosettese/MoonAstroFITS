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
