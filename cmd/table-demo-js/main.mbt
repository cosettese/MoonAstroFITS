///|
/// Write a generated FITS file through Node.js without making the library
/// itself dependent on a particular filesystem or MoonBit backend.
extern "js" fn write_file(path : String, data : Bytes) -> String =
  #| function(path, data) {
  #|   try {
  #|     require("node:fs").writeFileSync(path, Buffer.from(data));
  #|     return "";
  #|   } catch (error) {
  #|     return error instanceof Error ? error.message : String(error);
  #|   }
  #| }

///|
fn main {
  let argv = @env.args()
  if argv.length() < 2 {
    println("usage: moon run cmd/table-demo-js --target js -- <output.fits>")
    return
  }
  let output_path = argv[argv.length() - 1]
  let primary_header : @fits.Header = {
    cards: [
      { keyword: "SIMPLE", value: Some("T"), comment: None, record_index: 0, },
      { keyword: "BITPIX", value: Some("8"), comment: None, record_index: 1, },
      { keyword: "NAXIS", value: Some("0"), comment: None, record_index: 2, },
      { keyword: "EXTEND", value: Some("T"), comment: None, record_index: 3, },
      { keyword: "END", value: None, comment: None, record_index: 4, },
    ],
    data_offset: 0,
  }
  let primary = @fits.encode_primary_hdu(primary_header, b"").unwrap()
  let fields : Array[@fits.TableField] = [
    { name: Some("TARGET"), format: "8A", },
    { name: Some("INDEX"), format: "1J", },
    { name: Some("SAMPLES"), format: "1QK(3)", },
  ]
  let rows : Array[Array[@fits.TableValue]] = [
    [
      @fits.Text("M31"),
      @fits.Integers([1L]),
      @fits.Integers([-9223372036854775807L - 1L, 1L]),
    ],
    [@fits.Text("M42"), @fits.Integers([2L]), @fits.Integers([])],
    [
      @fits.Text("M51"),
      @fits.Integers([3L]),
      @fits.Integers([9223372036854775807L]),
    ],
  ]
  let extension = @fits.encode_binary_table_extension(fields, rows).unwrap()
  let file = primary + extension
  let parsed = @fits.parse_fits(file).unwrap()
  if parsed.hdus.length() != 2 {
    abort("generated file must have exactly two HDUs")
  }
  let table = @fits.parse_binary_table(parsed.hdus[1]).unwrap()
  for index, row in rows {
    if @fits.decode_binary_row(file, table, index).unwrap() != row {
      abort("generated row \{index} failed round trip")
    }
  }
  let write_error = write_file(output_path, file)
  if write_error != "" {
    abort("cannot write \{output_path}: \{write_error}")
  }
  println(
    "wrote \{output_path}: \{file.length()} bytes, 2 HDUs, 3 BINTABLE rows, \{table.heap_length} heap bytes",
  )
}
