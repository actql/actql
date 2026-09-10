///|
fn origin_member(c : @decode.Cursor, name : String) -> @decode.Cursor {
  @decode.lookup(@decode.open_object(c).unwrap(), name).unwrap()
}

///|
fn origin_body(root : @decode.Cursor) -> @decode.Cursor {
  origin_member(
    @decode.elements(
      origin_member(
        @decode.elements(origin_member(root, "stages")).unwrap()[0],
        "steps",
      ),
    ).unwrap()[0],
    "derive",
  )
}

///|
test "type diagnostics retain original Program slots and decoded scalar ranges" {
  let row = schema(
    "{\"customer\":{\"type\":\"object\",\"nullable\":false,\"fields\":{}}}",
  )
  let cases : Array[(String, Array[@decode.PathSegment], @text.Range?)] = [
    ("\"1 + TRUE\"", [], Some({ start: 4, end: 8, })),
    ("\"$missing + 1\"", [], Some({ start: 0, end: 8, })),
    ("\"customer.missing\"", [], Some({ start: 0, end: 16, })),
    (
      "{\"add\":[\"len('😀') + TRUE\",{\"literal\":1}]}",
      [Key("add"), Index(0)],
      Some({ start: 11, end: 15, }),
    ),
    ("\"to_number(TRUE)\"", [], Some({ start: 0, end: 15, })),
    (
      "{\"add\":[{\"literal\":1},{\"literal\":true}]}",
      [Key("add"), Index(1)],
      None,
    ),
    ("\"1 + \\u0054RUE\"", [], Some({ start: 4, end: 8, })),
    ("\"1 +\\r\\nTRUE\"", [], Some({ start: 4, end: 8, })),
  ]
  for (text, suffix, range) in cases {
    let root = cursor(
      "{\"stages\":[{\"steps\":[{\"derive\":{\"bad\":" + text + "}}]}]}",
    )
    let body = origin_body(root)
    let mut expected = origin_member(body, "bad")
    for segment in suffix {
      expected = match segment {
        Key(k) => origin_member(expected, k)
        Index(i) => @decode.elements(expected).unwrap()[i]
      }
    }
    match check_row(Derive, body, row, None, limits()) {
      Err(issue) => {
        assert_true(issue.kind is Expression(_))
        assert_eq(issue.path, @decode.cursor_path(expected))
        assert_eq(issue.span, @decode.cursor_span(expected))
        assert_eq(issue.range, range)
      }
      Ok(_) => fail("expected type rejection")
    }
  }
}

///|
test "YAML literal and folded expression diagnostics retain the scalar source span" {
  for
    spelling in [
      "|-\r\n            1 + TRUE", ">-\n            1 +\n            TRUE",
    ] {
    let parsed = @source.parse_yaml(
      "stages:\n  - steps:\n      - derive:\n          bad: " + spelling,
      { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      source_path="origin.aql",
    ).unwrap()
    let root = @decode.admit(parsed, {
      max_nodes: 1000,
      max_depth: 100,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    }).unwrap()
    let body = origin_body(root)
    let expected = origin_member(body, "bad")
    match check_row(Derive, body, input(), None, limits()) {
      Err(issue) => {
        assert_eq(issue.path, @decode.cursor_path(expected))
        assert_eq(issue.span, @decode.cursor_span(expected))
        assert_eq(issue.range, Some({ start: 4, end: 8, }))
      }
      Ok(_) => fail("expected type rejection")
    }
  }
}

///|
test "deep field references type check without eagerly expanding paths" {
  for n in [128, 256, 512, 1024] {
    let expression = "{\"add\":[{\"field\":\"amount\"},".repeat(n) +
      "{\"literal\":0}" +
      "]}".repeat(n)
    let result = check_row(
      Derive,
      cursor("{\"out\":" + expression + "}"),
      input(),
      None,
      limits(),
    ).unwrap()
    let refs = @relation_typing.references(
      @relation_typing.binding_at(result, 0).unwrap(),
    )
    assert_eq(refs.length(), n)
    assert_eq(
      @syntax.location_path(refs[n - 1].occurrence.location).length(),
      2 * n + 1,
    )
    let invalid = "{\"add\":[{\"field\":\"amount\"},".repeat(n) +
      "{\"field\":\"missing\"}" +
      "]}".repeat(n)
    match
      check_row(
        Derive,
        cursor("{\"out\":" + invalid + "}"),
        input(),
        None,
        limits(),
      ) {
      Err(issue) => {
        assert_eq(issue.kind, UnknownField("missing"))
        assert_eq(issue.range, None)
        assert_eq(issue.path.length(), 2 * n + 1)
        assert_eq(issue.path[0], @source.Key("out"))
        for i in 0..<n {
          assert_eq(issue.path[2 * i + 1], @source.Key("add"))
          assert_eq(issue.path[2 * i + 2], @source.Index(1))
        }
      }
      Ok(_) => fail("expected unknown field")
    }
  }
}
