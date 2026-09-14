///|
test "encode a canonical header byte for byte" {
  let source = test_header([
    "SIMPLE  =                    T / conforms to FITS", "BITPIX  =                   16",
    "NAXIS   =                    0", "OBJECT  = 'M31' / target", "HISTORY calibrated",
    "END",
  ])
  let header = @moonastrofits.parse_header(source).unwrap()
  let encoded = @moonastrofits.encode_header(header).unwrap()
  assert_eq(encoded, source)
}

///|
test "header encoding round trips lexical cards" {
  let source = test_header([
    "SIMPLE  =                    T", "UNDEF   =", "OBJECT  = 'M31 / core' / target field",
    "COMMENT first pass", "HISTORY calibrated", "END",
  ])
  let first = @moonastrofits.parse_header(source).unwrap()
  let encoded = @moonastrofits.encode_header(first).unwrap()
  let second = @moonastrofits.parse_header(encoded).unwrap()
  assert_eq(second.cards, first.cards)
  assert_eq(second.data_offset, 2880)
}

///|
test "header encoding pads multiple blocks deterministically" {
  let cards : Array[@moonastrofits.Card] = []
  for index = 0; index < 36; index = index + 1 {
    cards.push({
      keyword: "HISTORY",
      value: None,
      comment: Some("step \{index}"),
      record_index: index,
    })
  }
  cards.push({ keyword: "END", value: None, comment: None, record_index: 36, })
  let encoded = @moonastrofits.encode_header({ cards, data_offset: 0, }).unwrap()
  assert_eq(encoded.length(), 5760)
  assert_eq(@moonastrofits.parse_header(encoded).unwrap().cards.length(), 37)
}

///|
test "reject missing or non-terminal END and oversized cards" {
  let simple : @moonastrofits.Card = {
    keyword: "SIMPLE",
    value: Some("T"),
    comment: None,
    record_index: 0,
  }
  assert_true(
    @moonastrofits.encode_header({ cards: [simple], data_offset: 0, })
    is Err(@moonastrofits.MissingEnd(_)),
  )
  let end : @moonastrofits.Card = {
    keyword: "END",
    value: None,
    comment: None,
    record_index: 0,
  }
  assert_true(
    @moonastrofits.encode_header({ cards: [end, simple], data_offset: 0, })
    is Err(@moonastrofits.InvalidCard(_, _)),
  )
  let long : @moonastrofits.Card = {
    keyword: "COMMENT",
    value: None,
    comment: Some(
      "123456789012345678901234567890123456789012345678901234567890123456789012345",
    ),
    record_index: 0,
  }
  assert_true(
    @moonastrofits.encode_header({ cards: [long, end], data_offset: 0, })
    is Err(@moonastrofits.CardTooLong(_, _)),
  )
}

///|
test "reject non-ASCII encoded text" {
  let card : @moonastrofits.Card = {
    keyword: "COMMENT",
    value: None,
    comment: Some("星"),
    record_index: 0,
  }
  let end : @moonastrofits.Card = {
    keyword: "END",
    value: None,
    comment: None,
    record_index: 1,
  }
  assert_true(
    @moonastrofits.encode_header({ cards: [card, end], data_offset: 0, })
    is Err(@moonastrofits.InvalidCard(_, _)),
  )
}
