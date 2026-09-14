///|
fn append_test_card(output : Array[Byte], text : String) -> Unit {
  for ch in text {
    output.push(ch.to_int().to_byte())
  }
  for index = text.length(); index < 80; index = index + 1 {
    output.push(b' ')
  }
}

///|
fn test_header(cards : Array[String]) -> Bytes {
  let output = []
  for card in cards {
    append_test_card(output, card)
  }
  while output.length() % 2880 != 0 {
    output.push(b' ')
  }
  Bytes::from_array(output)
}

///|
test "parse FITS cards and preserve source order" {
  let data = test_header([
    "SIMPLE  =                    T / conforms to FITS", "BITPIX  =                   16",
    "NAXIS   =                    2", "NAXIS1  =                    3", "NAXIS2  =                    2",
    "OBJECT  = 'M31 / central''s field' / slash stays quoted", "HISTORY first import",
    "HISTORY calibrated", "END",
  ])
  let header = @moonastrofits.parse_header(data).unwrap()
  assert_eq(header.data_offset, 2880)
  assert_eq(header.cards.length(), 9)
  assert_eq(header.get("BITPIX").unwrap().value, Some("16"))
  assert_eq(
    header.get("OBJECT").unwrap().value,
    Some("'M31 / central''s field'"),
  )
  assert_eq(header.get("OBJECT").unwrap().comment, Some("slash stays quoted"))
  assert_eq(header.get_all("HISTORY").length(), 2)
}

///|
test "undefined values remain distinct from commentary cards" {
  let header = @moonastrofits.parse_header(
    test_header([
      "SIMPLE  =                    T", "UNDEF   =", "COMMENT no value indicator",
      "END",
    ]),
  ).unwrap()
  assert_eq(header.get("UNDEF").unwrap().value, Some(""))
  assert_eq(header.get("COMMENT").unwrap().value, None)
  assert_eq(header.get("COMMENT").unwrap().comment, Some("no value indicator"))
}

///|
test "reject missing END and truncated padded headers" {
  let no_end = test_header(["SIMPLE  =                    T"])
  assert_true(
    @moonastrofits.parse_header(no_end) is Err(@moonastrofits.MissingEnd(_)),
  )
  let short = b"END                                                                             "
  assert_true(
    @moonastrofits.parse_header(short) is Err(@moonastrofits.Truncated(_, _, _)),
  )
}

///|
test "reject non-ASCII header bytes and non-space padding" {
  let non_ascii = test_header(["SIMPLE  =                    T", "END"]).to_array()
  non_ascii[11] = b'\x01'
  assert_true(
    @moonastrofits.parse_header(Bytes::from_array(non_ascii))
    is Err(@moonastrofits.NonAscii(_, _)),
  )
  let bad_padding = test_header(["END"]).to_array()
  bad_padding[80] = b'X'
  assert_true(
    @moonastrofits.parse_header(Bytes::from_array(bad_padding))
    is Err(@moonastrofits.InvalidPadding(_, _)),
  )
}

///|
test "reject lowercase and valued END keywords" {
  assert_true(
    @moonastrofits.parse_header(test_header(["simple  = T", "END"]))
    is Err(@moonastrofits.InvalidKeyword(_, _)),
  )
  assert_true(
    @moonastrofits.parse_header(test_header(["END     = T"]))
    is Err(@moonastrofits.InvalidCard(_, _)),
  )
}
