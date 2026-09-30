///|
/// Read a local file through the Node.js host used by the JS example.
extern "js" fn node_read_file(path : String) -> Bytes =
  #| function(path) {
  #|   try {
  #|     globalThis.__moonastrofitsReadError = "";
  #|     return new Uint8Array(require("node:fs").readFileSync(path));
  #|   } catch (error) {
  #|     globalThis.__moonastrofitsReadError = error instanceof Error
  #|       ? error.message
  #|       : String(error);
  #|     return new Uint8Array();
  #|   }
  #| }

///|
/// Return the host error captured by `node_read_file`.
extern "js" fn node_last_read_error() -> String =
  #| function() {
  #|   return globalThis.__moonastrofitsReadError || "";
  #| }

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
          println(
            "  heap: offset=\{table.heap_offset} bytes=\{table.heap_length}",
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
/// Check the official 64-bit FITS fixture against independently observed
/// Astropy values. This path is run in CI on every supported host OS.
fn check_reference_fixture(data : Bytes, file : @fits.FitsFile) -> Unit {
  if data.length() != 17280 || file.hdus.length() != 3 {
    abort("reference fixture size or HDU count changed")
  }
  let expected : Array[Int64] = [
    -9223372036854775807L - 1L,
    -9223372036854775807L,
    -9223372036854775806L,
    -9223372036854775805L,
    -9223372036854775804L,
    -2L,
    -1L,
    0L,
    1L,
    2L,
    9223372036854775803L,
    9223372036854775804L,
    9223372036854775805L,
    9223372036854775806L,
    9223372036854775807L,
  ]
  let image = @fits.decode_integer_image(data, file.hdus[0]).unwrap()
  if image.axes != [5, 3] || image.raw != expected {
    abort("primary 64-bit image differs from Astropy reference")
  }
  let fixed = @fits.parse_binary_table(file.hdus[1]).unwrap()
  let variable = @fits.parse_binary_table(file.hdus[2]).unwrap()
  if fixed.row_count != 15 || variable.row_count != 15 {
    abort("reference binary table row count changed")
  }
  let prefix : Array[Int64] = []
  for index = 0; index < 15; index = index + 1 {
    let sequence = (index + 1).to_int64()
    let fixed_row = @fits.decode_binary_row(data, fixed, index).unwrap()
    if fixed_row !=
      [@fits.Integers([sequence]), @fits.Integers([expected[index]])] {
      abort("fixed table row \{index} differs from Astropy reference")
    }
    prefix.push(expected[index])
    let heap_row = @fits.decode_binary_row(data, variable, index).unwrap()
    if heap_row != [@fits.Integers([sequence]), @fits.Integers(prefix.copy())] {
      abort("variable table row \{index} differs from Astropy reference")
    }
  }
  println(
    "Astropy reference: PASS (15 image pixels, 15 fixed rows, 15 heap rows)",
  )
}

///|
/// Read and structurally validate a FITS file from disk.
fn main {
  let argv = @env.args()
  if argv.length() < 2 {
    println(
      "usage: moon run cmd/preflight-js --target js -- [--check-sample] <file.fits>",
    )
    return
  }
  let check_sample = argv.length() >= 4 &&
    argv[argv.length() - 2] == "--check-sample"
  let path = argv[argv.length() - 1]
  let data = node_read_file(path)
  let read_error = node_last_read_error()
  if read_error != "" {
    println("read error for \{path}: \{read_error}")
    return
  }
  println("MoonAstroFITS real-file preflight (JS host)")
  println("path: \{path}")
  println("bytes: \{data.length()}")
  match @fits.parse_fits(data) {
    Err(error) => {
      if check_sample {
        abort("invalid FITS: \{error.message()}")
      }
      println("invalid FITS: \{error.message()}")
    }
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
      if check_sample {
        check_reference_fixture(data, file)
      }
    }
  }
}
