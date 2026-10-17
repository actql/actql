///|
test "keyed record Effects retain their declared kind and original field path" {
  for
    (word, kind) in [
      ("UPDATE", KeyedEffectKind::Update),
      ("UPSERT", Upsert),
      ("DELETE", Delete),
    ] {
    let suffix = if kind == Delete { "" } else { " SET (Name = body)" }
    let query = parse_query(
      "FROM messages |> EFFECT write " +
      word +
      " salesforce.Account ID messages.id" +
      suffix,
      query_limits(),
    ).unwrap()
    let clause = terminal_effect(query).unwrap()
    assert_eq(clause.kind, kind)
    assert_eq(clause.name.unwrap().value, "write")
    assert_eq(clause.id.value, "id")
    let expression = clause.id_expression.unwrap()
    guard expression_node(expression, expression_root(expression)).unwrap().kind
      is Reference(path) else {
      fail("original ID field path")
    }
    assert_eq(path.map(part => part.value), ["messages", "id"])
    assert_eq(clause.set.length(), if kind == Delete { 0 } else { 1 })
  }
}

///|
test "keyed record operators do not consume a declared Effect name or namespace" {
  for (word, kind) in [("UPSERT", KeyedEffectKind::Upsert), ("DELETE", Delete)] {
    let suffix = if kind == Delete { "" } else { " SET (Name = body)" }
    for name in ["COMMAND", "STORE", "UPDATE", "UPSERT", "DELETE"] {
      let query = parse_query(
        "FROM messages |> EFFECT " +
        name +
        " " +
        word +
        " salesforce.Account ID id" +
        suffix,
        query_limits(),
      ).unwrap()
      assert_eq(terminal_effect(query).unwrap().kind, kind)
      assert_eq(terminal_effect(query).unwrap().name.unwrap().value, name)
      assert_true(terminal_short_command_effect(query) is None)
      assert_true(terminal_store_effect(query) is None)
    }
  }
  let command = parse_query(
    "FROM messages |> EFFECT COMMAND delete.events ID id",
    query_limits(),
  ).unwrap()
  assert_true(terminal_effect(command) is None)
  assert_eq(
    terminal_short_command_effect(command).unwrap().operation.map(part => {
      part.value
    }),
    ["delete", "events"],
  )
}

///|
test "keyed record Effects retain the old simple UPDATE representation and refuse malformed terminals" {
  let query = parse_query(
    "FROM messages |> EFFECT UPDATE salesforce.Account ID id SET (Name = body)",
    query_limits(),
  ).unwrap()
  assert_eq(terminal_effect(query).unwrap().kind, Update)
  assert_true(terminal_effect(query).unwrap().id_expression is None)
  for
    tail in [
      "DELETE salesforce.Account ID id SET (Name = body)", "UPSERT salesforce.Account ID id SET ()",
      "UPSERT salesforce.Account ID (id) SET (Name = body)", "DELETE salesforce.Account ID @id",
      "DELETE salesforce.Account ID id + 1", "DELETE salesforce.Account ID id |> SELECT id",
      "UPSERT 'salesforce.Account' ID id SET (Name = body)",
    ] {
    assert_true(
      parse_query("FROM messages |> EFFECT " + tail, query_limits()) is Err(_),
      msg=tail,
    )
  }
}
