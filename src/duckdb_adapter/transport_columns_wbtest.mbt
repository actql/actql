///|
fn transport_column_limits() -> TransportColumnLimits {
  {
    max_bytes: 10000,
    max_nodes: 100,
    max_columns: 10,
    max_rows: 10,
    max_text_bytes: 10000,
  }
}

///|
test "physical JSON decoding preserves raw strings and exact scalar payloads" {
  let text = "[[\"e\\u0301\\r\\n\",null,\"9007199254740993\"],[true,false,\"-123456789012345678901234567890\"]]"
  let columns = decode_transport_columns(text, transport_column_limits()).unwrap()
  assert_eq(columns.length(), 2)
  assert_eq(@decode.array_length(columns[0]), Some(3))
  assert_eq(
    @decode.text(@decode.element_at(columns[0], 0).unwrap()).unwrap(),
    "e\u0301\r\n",
  )
  assert_true(@decode.is_null(@decode.element_at(columns[0], 1).unwrap()))
  assert_eq(
    @decode.text(@decode.element_at(columns[0], 2).unwrap()).unwrap(),
    "9007199254740993",
  )
  assert_eq(
    @decode.boolean(@decode.element_at(columns[1], 0).unwrap()).unwrap(),
    true,
  )
  assert_eq(
    @decode.boolean(@decode.element_at(columns[1], 1).unwrap()).unwrap(),
    false,
  )
  assert_eq(
    @decode.text(@decode.element_at(columns[1], 2).unwrap()).unwrap(),
    "-123456789012345678901234567890",
  )
  assert_eq(
    decode_transport_columns("[]", transport_column_limits()).unwrap().length(),
    0,
  )
  assert_eq(
    @decode.array_length(
      decode_transport_columns("[[]]", transport_column_limits()).unwrap()[0],
    ),
    Some(0),
  )
}

///|
test "physical JSON allocation limits are exact and cumulative within the frame" {
  // Five JSON nodes, one row per column, two decoded UTF-8 bytes.
  let text = "[[\"é\"],[null]]"
  // This literal has 15 bytes: brackets 6, quotes 2, é 2, comma 1, null 4.
  let exact : TransportColumnLimits = {
    max_bytes: 15,
    max_nodes: 5,
    max_columns: 2,
    max_rows: 1,
    max_text_bytes: 2,
  }
  assert_true(decode_transport_columns(text, exact) is Ok(_))
  assert_eq(
    decode_transport_columns(text, { ..exact, max_bytes: 14, }).map(_ => ()),
    Err(InputLimit),
  )
  assert_eq(
    decode_transport_columns(text, { ..exact, max_nodes: 4, }).map(_ => ()),
    Err(NodeLimit),
  )
  assert_eq(
    decode_transport_columns(text, { ..exact, max_columns: 1, }).map(_ => ()),
    Err(ColumnLimit),
  )
  assert_eq(
    decode_transport_columns(text, { ..exact, max_rows: 0, }).map(_ => ()),
    Err(RowLimit),
  )
  assert_eq(
    decode_transport_columns(text, { ..exact, max_text_bytes: 1, }).map(_ => ()),
    Err(TextLimit),
  )
  assert_eq(
    decode_transport_columns("[[\"é\"],[\"é\"]]", { ..exact, max_bytes: 100, }).map(_ => {
        ()
      },
    ),
    Err(TextLimit),
  )
  assert_eq(
    decode_transport_columns("[]", { ..exact, max_nodes: -1, }).map(_ => ()),
    Err(InvalidLimits),
  )
}

///|
test "physical JSON rejects nested values numbers and malformed syntax without recursive tree traversal" {
  for text in ["[[[]]]", "[[{}]]", "[[1]]", "[null]", "null"] {
    assert_true(
      decode_transport_columns(text, transport_column_limits())
      is Err(InvalidShape),
    )
  }
  for text in ["[[true false]]", "[[nul]]", "[[\"x\"]", "[[\"\\q\"]]"] {
    assert_true(
      decode_transport_columns(text, transport_column_limits())
      is Err(InvalidJson),
    )
  }
  // Brackets and escaped quotes inside a physical string do not alter depth.
  assert_eq(
    @decode.text(
      @decode.element_at(
        decode_transport_columns("[[\"[\\\"]\"]]", transport_column_limits()).unwrap()[0],
        0,
      ).unwrap(),
    ).unwrap(),
    "[\"]",
  )
  for text in ["[[\"\\ud800\"]]", "[[\"\\udc00\"]]"] {
    assert_true(
      decode_transport_columns(text, transport_column_limits()) is Err(_),
    )
  }
  assert_eq(
    @decode.text(
      @decode.element_at(
        decode_transport_columns(
          "[[\"\\ud83d\\ude00\"]]",
          transport_column_limits(),
        ).unwrap()[0],
        0,
      ).unwrap(),
    ).unwrap(),
    "😀",
  )
}
