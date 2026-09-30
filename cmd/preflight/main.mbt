///|
/// Return a stable, human-readable label for the structural HDU kind.
fn hdu_kind_name(kind : @fits.HduKind) -> String {
  match kind {
    Primary => "PRIMARY"
    ImageExtension => "IMAGE"
    OtherExtension(name) => name
  }
}

///|
/// Print one real-file preflight summary for the conformance fixture.
fn print_hdu(data : Bytes, hdu : @fits.Hdu) -> Unit {
  println(
    "HDU \{hdu.index}: kind=\{hdu_kind_name(hdu.kind)} data_bytes=\{hdu.data_length}",
  )
  match hdu.image {
    None => ()
    Some(image) =>
      println(
        "  image: BITPIX=\{image.bitpix} axes=\{@debug.repr(image.axes)} pixels=\{image.pixel_count}",
      )
  }
  match hdu.kind {
    OtherExtension("BINTABLE") =>
      match @fits.parse_binary_table(hdu) {
        Err(error) =>
          println(
            "  table: unsupported or invalid fixed-width schema (\{error.message()})",
          )
        Ok(table) => {
          println(
            "  table: rows=\{table.row_count} row_bytes=\{table.row_length} columns=\{table.columns.length()}",
          )
          for column in table.columns {
            println(
              "    column \{column.index}: TFORM=\{column.format} width=\{column.width}",
            )
          }
          match @fits.decode_binary_row(data, table, 0) {
            Err(error) => println("  first row: \{error.message()}")
            Ok(row) => println("  first row cells: \{row.length()}")
          }
        }
      }
    _ => ()
  }
}

///|
/// Read and structurally validate a FITS file from disk.
async fn main {
  let argv = @env.args()
  if argv.length() < 2 {
    println("usage: moon run cmd/preflight --target native -- <file.fits>")
    return
  }
  let path = argv[argv.length() - 1]
  let data = @fs.read_file(path).binary() catch {
    error => {
      println("read error for \{path}: \{error}")
      return
    }
  }
  println("MoonAstroFITS real-file preflight")
  println("path: \{path}")
  println("bytes: \{data.length()}")
  match @fits.parse_fits(data) {
    Err(error) => println("invalid FITS: \{error.message()}")
    Ok(file) => {
      println("structural validation: PASS (\{file.hdus.length()} HDUs)")
      for hdu in file.hdus {
        print_hdu(data, hdu)
      }
      match file.primary() {
        None => ()
        Some(primary) =>
          match @fits.decode_integer_image(data, primary) {
            Err(error) => println("primary integer decode: \{error.message()}")
            Ok(image) =>
              println(
                "primary integer decode: PASS (\{image.raw.length()} samples, BSCALE=\{image.bscale}, BZERO=\{image.bzero})",
              )
          }
      }
      println(
        "note: Q descriptor tables are structurally traversed but intentionally outside the fixed-width table API",
      )
    }
  }
}
