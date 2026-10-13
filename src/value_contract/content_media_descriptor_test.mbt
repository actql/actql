///|
test "Content media descriptors preserve opaque parameters through constructor read and render" {
  for
    (descriptor, encoded) in [
      (
        "text/plain;label=\"e\u{301}🚀\"", "text/plain;label=\\\"e\u{301}🚀\\\"",
      ),
      ("text/plain;label=\"é🚀\"", "text/plain;label=\\\"é🚀\\\""),
      ("text/html;charset=UTF-8", "text/html;charset=UTF-8"),
      (
        "multipart/form-data; boundary=AbC123", "multipart/form-data; boundary=AbC123",
      ),
      ("text/plain;q=\"A\\\";B\";x=Z", "text/plain;q=\\\"A\\\\\\\";B\\\";x=Z"),
    ] {
    let input = "{\"type\":\"content_ref\",\"nullable\":false,\"media_type\":\"" +
      encoded +
      "\"}"
    let expected = "{\"media_type\":\"" +
      encoded +
      "\",\"nullable\":false,\"type\":\"content_ref\"}"
    let actual = @value_contract.content_reference_contract(
      Some(descriptor),
      nullable=false,
      max_name_bytes=256,
    ).unwrap()
    assert_eq(render(actual), expected)
    assert_true(@value_contract.type_equal(actual, author(input), 10))
    assert_true(@value_contract.type_equal(actual, checked(expected), 10))
  }
  let nfd = author(
    "{\"type\":\"content_ref\",\"nullable\":false,\"media_type\":\"text/plain;label=\\\"e\u{301}\\\"\"}",
  )
  let nfc = author(
    "{\"type\":\"content_ref\",\"nullable\":false,\"media_type\":\"text/plain;label=\\\"é\\\"\"}",
  )
  assert_false(@value_contract.type_equal(nfd, nfc, 10))
}

///|
test "authored Content descriptors refuse ASCII noncanonical case rather than changing identity" {
  for
    descriptor in [
      "Application/PDF", "text/Plain", "text/plain;LABEL=Value", "TEXT/HTML;charset=UTF-8",
    ] {
    assert_true(
      @value_contract.content_reference_contract(
        Some(descriptor),
        nullable=false,
        max_name_bytes=256,
      )
      is None,
    )
    let input = "{\"type\":\"content_ref\",\"nullable\":false,\"media_type\":\"" +
      descriptor +
      "\"}"
    assert_eq(
      error_name(@value_contract.read_author(cursor(input), limits())),
      "NonCanonicalText",
    )
    assert_eq(
      error_name(@value_contract.read_checked(cursor(input), limits())),
      "NonCanonicalText",
    )
  }
  for
    descriptor in [
      "application", "application/", "text/plain;missing", "text/plain;=value", "text/plain;name=",
    ] {
    assert_true(
      @value_contract.content_reference_contract(
        Some(descriptor),
        nullable=false,
        max_name_bytes=256,
      )
      is None,
    )
    let input = "{\"type\":\"content_ref\",\"nullable\":false,\"media_type\":\"" +
      descriptor +
      "\"}"
    assert_eq(
      error_name(@value_contract.read_author(cursor(input), limits())),
      "InvalidRange",
    )
    assert_eq(
      error_name(@value_contract.read_checked(cursor(input), limits())),
      "InvalidRange",
    )
  }
}

///|
test "Content descriptor admission charges exact UTF8 text without identifier normalization" {
  let input = "{\"type\":\"content_ref\",\"nullable\":false,\"media_type\":\"text/plain;label=\\\"e\u{301}\\\"\"}"
  // 11 ASCII bytes for content_ref; descriptor has 22 bytes including the
  // independently counted decomposed e + U+0301 and both quotation marks.
  assert_eq(
    error_name(@value_contract.read_author(cursor(input), limits(text=33))),
    "accepted",
  )
  assert_eq(
    error_name(@value_contract.read_checked(cursor(input), limits(text=33))),
    "accepted",
  )
  assert_eq(
    error_name(@value_contract.read_author(cursor(input), limits(text=32))),
    "BudgetExceeded",
  )
  assert_eq(
    error_name(@value_contract.read_checked(cursor(input), limits(text=32))),
    "BudgetExceeded",
  )
  assert_true(
    @value_contract.content_reference_contract(
      Some("text/plain;label=\"e\u{301}\""),
      nullable=false,
      max_name_bytes=22,
    )
    is Some(_),
  )
  assert_true(
    @value_contract.content_reference_contract(
      Some("text/plain;label=\"e\u{301}\""),
      nullable=false,
      max_name_bytes=21,
    )
    is None,
  )
}
