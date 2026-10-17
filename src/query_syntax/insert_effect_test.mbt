///|
test "INSERT retains target field order and distinguishes omitted VALUES" {
  let implicit = parse_query(
    "FROM incoming |> EFFECT INSERT crm.records (`Name`, age)",
    query_limits(),
  ).unwrap()
  let clause = terminal_insert_effect(implicit).unwrap()
  assert_true(clause.name is None)
  assert_eq(clause.fields.map(field => field.value), ["Name", "age"])
  assert_true(clause.values is None)
  let explicit = parse_query(
    "FROM incoming |> EFFECT save INSERT TARGET 'connector://crm/account' MAPPING m (Name, age) VALUES (person.name, 42)",
    query_limits(),
  ).unwrap()
  let clause = terminal_insert_effect(explicit).unwrap()
  assert_eq(clause.name.unwrap().value, "save")
  assert_eq(clause.values.unwrap().length(), 2)
  guard clause.target is ConcreteTarget(target) else {
    fail("explicit original target")
  }
  assert_eq(target, "connector://crm/account")
}

///|
test "INSERT is terminal and retains record operator name disambiguation" {
  for name in ["COMMAND", "STORE", "UPDATE", "UPSERT", "DELETE", "INSERT"] {
    let query = parse_query(
      "FROM incoming |> EFFECT " +
      name +
      " INSERT crm.records (Name) VALUES ('original')",
      query_limits(),
    ).unwrap()
    assert_eq(terminal_insert_effect(query).unwrap().name.unwrap().value, name)
    assert_true(terminal_effect(query) is None)
    assert_true(terminal_short_command_effect(query) is None)
    assert_true(terminal_store_effect(query) is None)
  }
  for
    text in [
      "FROM incoming |> EFFECT INSERT crm.records ()", "FROM incoming |> EFFECT INSERT crm.records (Name, name)",
      "FROM incoming |> EFFECT INSERT crm.records (Name) VALUES ()", "FROM incoming |> EFFECT INSERT crm.records (Name) VALUES ('a', 'b')",
      "FROM incoming |> EFFECT INSERT crm.records (Name, age) VALUES ('a')", "FROM incoming |> EFFECT INSERT crm.records (Name) |> SELECT Name",
      "WITH q AS (FROM incoming |> EFFECT INSERT crm.records (Name)) FROM q", "CREATE TABLE output AS (FROM incoming |> EFFECT INSERT crm.records (Name))",
    ] {
    assert_true(parse_query(text, query_limits()) is Err(_), msg=text)
  }
}

///|
test "INSERT getter owns field lists and original VALUES occurrences" {
  let query = parse_query(
    "FROM incoming |> EFFECT INSERT crm.records (Name) VALUES (body)",
    query_limits(),
  ).unwrap()
  let clause = terminal_insert_effect(query).unwrap()
  clause.fields.clear()
  clause.values.unwrap().clear()
  assert_eq(terminal_insert_effect(query).unwrap().fields.length(), 1)
  assert_eq(terminal_insert_effect(query).unwrap().values.unwrap().length(), 1)
  let command = parse_query(
    "FROM incoming |> EFFECT COMMAND insert.events ID id",
    query_limits(),
  ).unwrap()
  assert_true(terminal_insert_effect(command) is None)
  assert_eq(
    terminal_short_command_effect(command).unwrap().operation.map(part => {
      part.value
    }),
    ["insert", "events"],
  )
}
