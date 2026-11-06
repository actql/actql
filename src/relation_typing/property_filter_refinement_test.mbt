///|
fn property_guard_input() -> @schema.Schema {
  @schema.from_object(
    schema(
      (
        #|{"risk":{"type":"object","nullable":false,"fields":{"outcome":{"type":"string","nullable":false},"value":{"type":"object","nullable":true,"fields":{"level":{"type":"string","nullable":false},"reason":{"type":"string","nullable":false},"unrelated":{"type":"string","nullable":true}}}}},"other":{"type":"string","nullable":true},"replacement":{"type":"object","nullable":false,"fields":{"value":{"type":"object","nullable":true,"fields":{"level":{"type":"string","nullable":false},"reason":{"type":"string","nullable":false}}}}}}
      ),
    ),
  ).unwrap()
}

///|
fn property_guard_child(
  contract : @contract.Contract,
  name : String,
) -> @contract.Contract {
  guard contract.shape is @contract.Object(fields) else { abort("Object") }
  let mut found : @contract.Contract? = None
  for index in 0..<@contract.field_count(fields) {
    let field = @contract.field_at(fields, index).unwrap()
    if field.name == name {
      found = Some(field.contract)
    }
  }
  found.unwrap()
}

///|
fn property_guard_value(input : @schema.Schema) -> @contract.Contract {
  property_guard_child(
    @schema.lookup_reference(input, "risk").unwrap().contract,
    "value",
  )
}

///|
test "true strict property guards refine the same original Object receivers only" {
  let input = property_guard_input()
  for
    predicate in [
      "risk.value.level = 'high'", "'high' = risk.value.level", "risk.outcome = 'ok' AND risk.value.level = 'high'",
      "risk.value.level <> 'low'", "risk.value.level > 'a'",
    ] {
    let checked = @relation_typing.check(
      Filter,
      cursor(predicate.to_json().stringify()),
      input,
      None,
      limits(),
    ).unwrap()
    let output = @relation_typing.output_schema(checked)
    assert_false(property_guard_value(output).nullable, msg=predicate)
    assert_true(property_guard_value(input).nullable)
    assert_false(
      property_guard_child(property_guard_value(output), "reason").nullable,
    )
    assert_true(
      property_guard_child(property_guard_value(output), "unrelated").nullable,
    )
    assert_true(
      @schema.lookup_reference(output, "other").unwrap().contract.nullable,
    )
    assert_eq(@schema.field_count(output), @schema.field_count(input))
    assert_true(@schema.all_fields_required(output))
    assert_eq(@relation_typing.form(checked), Predicate)
  }
  // The leaf itself may also be nullable. A TRUE strict comparison proves
  // that same leaf and its receivers non-null independently of row values.
  let nullable_leaf = @relation_typing.check(
    Filter,
    cursor("\"risk.value.unrelated > 'a'\""),
    input,
    None,
    limits(),
  ).unwrap()
  let refined = property_guard_value(
    @relation_typing.output_schema(nullable_leaf),
  )
  assert_false(refined.nullable)
  assert_false(property_guard_child(refined, "unrelated").nullable)
  assert_true(
    property_guard_child(property_guard_value(input), "unrelated").nullable,
  )
}

///|
test "alternative paths computed receivers and null-safe comparisons do not prove this guard" {
  let input = property_guard_input()
  for
    predicate in [
      "risk.outcome = 'ok'", "risk.value.level = 'high' OR TRUE", "NOT (risk.value.level = 'high')",
      "risk.value.level IS DISTINCT FROM 'low'", "coalesce(risk.value.level, 'high') = 'high'",
      "CASE WHEN TRUE THEN TRUE ELSE risk.value.level = 'high' END",
    ] {
    let checked = @relation_typing.check(
      Filter,
      cursor(predicate.to_json().stringify()),
      input,
      None,
      limits(),
    ).unwrap()
    let output = @relation_typing.output_schema(checked)
    assert_true(property_guard_value(output).nullable, msg=predicate)
    assert_shallow_schema_unchanged(input, output)
  }
}

///|
fn assert_shallow_schema_unchanged(
  input : @schema.Schema,
  output : @schema.Schema,
) -> Unit raise {
  assert_eq(@schema.field_count(input), @schema.field_count(output))
  for index in 0..<@schema.field_count(input) {
    let before = @schema.field_at(input, index).unwrap()
    let after = @schema.field_at(output, index).unwrap()
    assert_eq(before.name, after.name)
    assert_eq(before.presence, after.presence)
    assert_true(@contract.type_equal(before.contract, after.contract, 1000))
  }
}

///|
test "property guard proof is charged to the original bounded typing account" {
  let input = property_guard_input()
  let source = cursor(
    "\"risk.value.level = 'high' AND risk.value.reason <> ''\"",
  )
  let checked = @relation_typing.check(Filter, source, input, None, limits()).unwrap()
  let exact = {
    ..limits(),
    max_work: @relation_typing.work_used(checked),
    max_text_bytes: @relation_typing.text_bytes_used(checked),
    max_nodes: @relation_typing.nodes_used(checked),
    max_tokens: @relation_typing.tokens_used(checked),
  }
  let again = @relation_typing.check(Filter, source, input, None, exact).unwrap()
  assert_false(
    property_guard_value(@relation_typing.output_schema(again)).nullable,
  )
  for
    reduced in [
      { ..exact, max_work: exact.max_work - 1, },
      { ..exact, max_text_bytes: exact.max_text_bytes - 1, },
      { ..exact, max_nodes: exact.max_nodes - 1, },
    ] {
    assert_true(
      @relation_typing.check(Filter, source, input, None, reduced) is Err(_),
    )
  }
}

///|
test "a later assignment cannot reuse the earlier receiver property proof" {
  let input = property_guard_input()
  let filtered = @relation_typing.check(
    Filter,
    cursor("\"risk.value.level = 'high'\""),
    input,
    None,
    limits(),
  ).unwrap()
  let proved = @relation_typing.output_schema(filtered)
  assert_false(property_guard_value(proved).nullable)
  let assigned = @relation_typing.check(
    Derive,
    cursor("[{\"risk\":{\"field\":\"replacement\"}}]"),
    proved,
    None,
    limits(),
  ).unwrap()
  let output = @relation_typing.output_schema(assigned)
  assert_true(property_guard_value(output).nullable)
  assert_true(property_guard_value(input).nullable)
  assert_false(property_guard_value(proved).nullable)
}
