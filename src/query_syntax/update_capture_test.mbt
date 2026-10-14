///|
test "UPDATE input omission is distinct from an exact explicit Result selection" {
  let prefix = "FROM t |> EFFECT UPDATE TARGET 'connector://c/T' MAPPING m "
  let implicit = parse_query(
    prefix +
    "ID id SET (Name = CASE WHEN ok THEN value.name ELSE 'fallback' END)",
    query_limits(),
  ).unwrap()
  assert_true(terminal_effect(implicit).unwrap().result is None)
  let explicit = parse_query(
    prefix + "FROM RESULT `Earlier.Exact` ID id SET (Name = value.name)",
    query_limits(),
  ).unwrap()
  let result = terminal_effect(explicit).unwrap().result.unwrap()
  assert_eq(result.value, "Earlier.Exact")
  assert_true(result.quoted)
}

///|
test "UPDATE private input does not relax declaration or target syntax" {
  let prefix = "FROM t |> EFFECT UPDATE TARGET 'connector://c/T' MAPPING m "
  for
    tail in [
      "FROM ID id SET (Name = value)", "FROM RESULT ID id SET (Name = value)", "ID id SET ()",
      "ID id SET (Name = value) |> SELECT id",
    ] {
    assert_true(parse_query(prefix + tail, query_limits()) is Err(_), msg=tail)
  }
  assert_true(
    parse_query(
      "FROM t |> EFFECT UPDATE TARGET target MAPPING m ID id SET (Name = value)",
      query_limits(),
    )
    is Err(_),
  )
}

///|
test "omitted UPDATE input does not generalize COMMAND input" {
  assert_true(
    parse_query_script(
      "FROM t; EFFECT send COMMAND TARGET destination CONTRACT c INPUT (name = value);",
      query_limits(),
    )
    is Err(_),
  )
}
