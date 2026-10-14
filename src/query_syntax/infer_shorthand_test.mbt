///|
test "INFER shorthand preserves mixed keys and original reference expressions" {
  let query = parse_query(
    "/*😀*/\r\nFROM t |> INFER task ITEM KEY (id) INPUT (notes, SELECT = notes, `ROWS`, `a.b`) KEEP (*) AS risk",
    query_limits(),
    source_path="short.sql",
  ).unwrap()
  guard operation_at(query, 0) is Some(Infer(clause)) else { fail("INFER") }
  assert_eq(clause.inputs.map(input => input.0), [
    { value: "notes", quoted: false, },
    { value: "SELECT", quoted: false, },
    { value: "ROWS", quoted: true, },
    { value: "a.b", quoted: true, },
  ])
  // Fixed UTF-8 ranges include the original emoji and CRLF; no expanded text.
  for
    (index, start, end, name) in [
      (0, 52, 57, "notes"),
      (1, 68, 73, "notes"),
      (2, 75, 81, "ROWS"),
      (3, 83, 88, "a.b"),
    ] {
    let expression = clause.inputs[index].1
    assert_eq(expression_node_count(expression), 1)
    guard expression_node(expression, expression_root(expression)).unwrap().kind
      is Reference([part]) else {
      fail("one reference")
    }
    assert_eq(part.value, name)
    let span = @origin.span(
      expression_origin(expression, expression_root(expression)).unwrap(),
    )
    assert_eq(span.source_path, "short.sql")
    assert_eq(span.start_byte, start)
    assert_eq(span.end_byte, end)
  }
}

///|
test "INFER shorthand requires one admitted binding identifier" {
  let prefix = "FROM t |> INFER task ITEM KEY (id) INPUT ("
  for
    input in [
      "t.notes", "notes + 1", "(notes)", "f(notes)", "@notes", "1", "'notes'", "SELECT",
      "ROWS", "CURRENT", "TRUE",
    ] {
    assert_true(
      parse_query(prefix + input + ") KEEP (*) AS risk", query_limits())
      is Err(_),
      msg=input,
    )
  }
  for
    input in [
      "notes = t.notes", "notes = notes + 1", "notes = (notes)", "SELECT = notes",
      "ROWS = notes", "`SELECT`", "`ROWS`",
    ] {
    assert_true(
      parse_query(prefix + input + ") KEEP (*) AS risk", query_limits())
      is Ok(_),
      msg=input,
    )
  }
  for input in ["notes", "notes = notes"] {
    assert_true(
      parse_query(prefix + input + ") KEEP (*) AS risk", {
        ..query_limits(),
        expression: { ..query_limits().expression, max_nodes: 0, },
      })
      is Err(_),
      msg=input,
    )
  }
}

///|
test "INFER shorthand refusals retain original UTF-8 positions" {
  for
    (input, expected) in [
      ("ROWS", "Reserved identifier requires backticks"),
      (
        "t.notes", "INFER INPUT shorthand requires one identifier; use name = expression",
      ),
    ] {
    guard parse_query(
        "/*😀é*/\r\nFROM t |> INFER task ITEM KEY (id) INPUT (" +
        input +
        ") KEEP (*) AS risk",
        query_limits(),
        source_path="original.sql",
      )
      is Err({ issue: Syntax(message), span: Some(span), }) else {
      fail(input)
    }
    assert_eq(message, expected)
    assert_eq(span.source_path, "original.sql")
    assert_eq(span.start_byte, 55)
    assert_eq(span.end_byte, 55)
  }
}

///|
test "terminal UPDATE omission is distinct from exact explicit names" {
  let tail = " TARGET 'connector://c/T' MAPPING m FROM RESULT updates ID id SET (Name = notes)"
  for
    (clause, name) in [
      ("EFFECT UPDATE", None),
      ("EFFECT aql_update_effect UPDATE", Some("aql_update_effect")),
      ("EFFECT `Save.Exact` UPDATE", Some("Save.Exact")),
      ("EFFECT UPDATE UPDATE", Some("UPDATE")),
    ] {
    let query = parse_query(
      "FROM t |> RESULT updates |> " + clause + tail,
      query_limits(),
    ).unwrap()
    assert_eq(
      terminal_effect(query).unwrap().name.map(part => part.value),
      name,
    )
  }
  assert_true(
    parse_query(
      "FROM t |> RESULT updates |> EFFECT `` UPDATE" + tail,
      query_limits(),
    )
    is Err(_),
  )
}

///|
test "anonymous UPDATE cannot name colliding or multiple terminal Effects implicitly" {
  let query = "FROM t |> RESULT updates |> EFFECT UPDATE TARGET 'connector://c/T' MAPPING m FROM RESULT updates ID id SET (Name = notes)"
  for
    tail in [
      " |> EFFECT aql_update_effect UPDATE TARGET 'connector://c/T' MAPPING m FROM RESULT updates ID id SET (Name = notes)",
      " |> EFFECT UPDATE TARGET 'connector://c/T' MAPPING m FROM RESULT updates ID id SET (Name = notes)",
      " |> CREATE TABLE out.records", "; EFFECT aql_update_effect COMMAND FROM RESULT updates AS row TARGET row.notes CONTRACT c INPUT ();",
      "; EFFECT other COMMAND FROM RESULT updates AS row TARGET row.notes CONTRACT c INPUT ();",
    ] {
    assert_true(
      parse_query_script(query + tail, query_limits()) is Err(_),
      msg=tail,
    )
  }
}
