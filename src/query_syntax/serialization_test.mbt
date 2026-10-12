///|
test "SERIALIZE retains explicit order profile data and ordinary continuation" {
  let query = parse_query(
    "FROM orders |> SERIALIZE FORMAT CSV ORDER BY id DESC NULLS FIRST OPTIONS (name = 'out.csv', header = TRUE, null_marker = r'\\N', max_bytes = @bytes) |> RESULT attachment",
    query_limits(),
  ).unwrap()
  guard operation_at(query, 0) is Some(Serialize(clause)) else {
    fail("SERIALIZE has its own normal Pipe AST")
  }
  assert_eq(clause.format, "csv")
  assert_true(!clause.preserve_order)
  assert_eq(clause.order_by.length(), 1)
  assert_eq(clause.order_by[0].direction, "desc")
  assert_eq(clause.order_by[0].nulls, "first")
  assert_eq(clause.options.map(option => option.0.value), [
    "name", "header", "null_marker", "max_bytes",
  ])
  assert_true(operation_at(query, 1) is Some(RetainResult(_)))
  clause.options.clear()
  guard operation_at(query, 0) is Some(Serialize(copy)) else {
    fail("owned AST")
  }
  assert_eq(copy.options.length(), 4)
  let preserve = parse_query(
    "SELECT 1 AS id |> SERIALIZE FORMAT JSONL PRESERVE ORDER OPTIONS (name = 'one.jsonl')",
    query_limits(),
  ).unwrap()
  assert_true(
    operation_at(preserve, 1)
    is Some(Serialize({ preserve_order: true, order_by: [], .. })),
  )
}

///|
test "SERIALIZE requires its own explicit order and closed unique options" {
  for
    text in [
      "FROM t |> SERIALISE FORMAT CSV PRESERVE ORDER OPTIONS (name = 'x')", "FROM t |> SERIALIZE FORMAT XML PRESERVE ORDER OPTIONS (name = 'x')",
      "FROM t |> SERIALIZE FORMAT JSONL OPTIONS (name = 'x')", "FROM t |> SERIALIZE FORMAT JSONL PRESERVE ORDER ORDER BY id OPTIONS (name = 'x')",
      "FROM t |> SERIALIZE FORMAT JSONL PRESERVE ORDER OPTIONS (name = 'x', NAME = 'y')",
      "FROM t |> SERIALIZE FORMAT JSONL PRESERVE ORDER OPTIONS (logical_name = 'x')",
      "FROM t |> SERIALIZE FORMAT JSONL PRESERVE ORDER OPTIONS (name = 'x',)",
    ] {
    match parse_query(text, query_limits(), source_path="serialize.pipe") {
      Err({ span: Some(span), .. }) =>
        assert_eq(span.source_path, "serialize.pipe")
      _ => fail(text)
    }
  }
}
