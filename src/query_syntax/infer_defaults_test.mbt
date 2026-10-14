///|
test "INFER preserves key omission and normalizes default KEEP to the current row" {
  for key in ["", " ITEM KEY (id)", " ITEM KEY (tenant, id)"] {
    for keep in ["", " KEEP (*)"] {
      let query = parse_query(
        "FROM tickets |> INFER task" +
        key +
        " INPUT (text)" +
        keep +
        " AS assessment",
        query_limits(),
      ).unwrap()
      guard operation_at(query, 0) is Some(Infer(clause)) else { fail("INFER") }
      if key == "" {
        assert_true(clause.keys is None)
      } else {
        assert_eq(
          clause.keys.unwrap().length(),
          if key == " ITEM KEY (id)" {
            1
          } else {
            2
          },
        )
      }
      assert_eq(clause.keep.length(), 1)
      assert_true(clause.keep[0].wildcard)
      assert_true(clause.keep[0].path.is_empty())
      assert_true(clause.keep[0].name is None)
      assert_eq(clause.name.value, "assessment")
    }
  }
}

///|
test "omitting ITEM KEY does not loosen mandatory INPUT AS or explicit key syntax" {
  for
    text in [
      "FROM t |> INFER task AS assessment", "FROM t |> INFER task INPUT ()", "FROM t |> INFER task KEY (id) INPUT () AS assessment",
      "FROM t |> INFER task ITEM INPUT () AS assessment", "FROM t |> INFER task ITEM KEY () INPUT () AS assessment",
      "FROM t |> INFER task INPUT () ITEM KEY (id) AS assessment", "FROM t |> INFER task INPUT () KEEP () AS assessment",
      "SELECT NULL AS assessment |> UNION ALL (FROM t |> INFER task INPUT () AS assessment)",
    ] {
    assert_true(parse_query(text, query_limits()) is Err(_), msg=text)
  }
}

///|
test "INFER default shorthand diagnostics retain original UTF-8 positions" {
  for
    (input, expected) in [
      ("ROWS", "Reserved identifier requires backticks"),
      (
        "t.notes", "INFER INPUT shorthand requires one identifier; use name = expression",
      ),
    ] {
    guard parse_query(
        "/*😀é*/\r\nFROM t |> INFER task INPUT (" +
        input +
        ") AS assessment",
        query_limits(),
        source_path="defaults.sql",
      )
      is Err({ issue: Syntax(message), span: Some(span), }) else {
      fail(input)
    }
    assert_eq(message, expected)
    assert_eq(span.source_path, "defaults.sql")
    assert_eq(span.start_byte, 41)
    assert_eq(span.end_byte, 41)
  }
}
