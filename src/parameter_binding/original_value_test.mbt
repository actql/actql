///|
fn original_default_values(
  definitions : @parameter_binding.Declarations,
  input : String?,
) -> @parameter_binding.BoundValues {
  let result = @parameter_binding.bind(
    definitions,
    input.map(cursor),
    values_limit(),
  ).unwrap()
  guard! result is @parameter_binding.Ready(values)
  values
}

///|
test "original selected defaults retain declaration type value and separate origin across full int64" {
  for
    text in ["-9223372036854775808", "9007199254740993", "9223372036854775807"] {
    let wire = "{\"id\":{\"type\":\"int64\",\"nullable\":false,\"default\":\"" +
      text +
      "\"}}"
    let definitions = declarations(wire)
    let selected = original_default_values(definitions, None)
    let again = original_default_values(definitions, None)
    let supplied = original_default_values(
      definitions,
      Some("{\"id\":\"" + text + "\"}"),
    )
    let declaration = @parameter_binding.declaration_at(definitions, 0).unwrap()
    assert_true(
      physical_equal(
        @parameter_binding.bound_value_declaration(selected, 0).unwrap(),
        declaration,
      ),
    )
    assert_true(
      physical_equal(
        @parameter_binding.bound_value_declaration(supplied, 0).unwrap(),
        declaration,
      ),
    )
    assert_true(
      @parameter_binding.bound_value_at(selected, 0).unwrap().origin
      is @parameter_binding.Default,
    )
    assert_true(
      @parameter_binding.bound_value_at(supplied, 0).unwrap().origin
      is @parameter_binding.Supplied,
    )
    assert_true(
      physical_equal(
        @parameter_binding.bound_value_at(selected, 0).unwrap().value,
        @parameter_binding.bound_value_at(again, 0).unwrap().value,
      ),
    )
    assert_eq(identity_cid(selected), identity_cid(supplied))
    let foreign = declarations(wire)
    assert_false(
      physical_equal(
        @parameter_binding.bound_value_declaration(selected, 0).unwrap(),
        @parameter_binding.declaration_at(foreign, 0).unwrap(),
      ),
    )
    assert_true(
      @parameter_binding.bound_value_declaration(selected, -1) is None,
    )
    assert_true(@parameter_binding.bound_value_declaration(selected, 1) is None)
  }
}

///|
test "original default projection preserves override explicit NULL missing and value budgets" {
  let definitions = declarations(
    "{\"id\":{\"type\":\"int64\",\"nullable\":true,\"default\":\"9007199254740993\"}}",
  )
  let selected = original_default_values(definitions, None)
  let overridden = original_default_values(
    definitions,
    Some("{\"id\":\"9007199254740992\"}"),
  )
  let null_value = original_default_values(definitions, Some("{\"id\":null}"))
  assert_true(
    @parameter_binding.bound_value_at(overridden, 0).unwrap().origin
    is @parameter_binding.Supplied,
  )
  assert_true(
    @parameter_binding.bound_value_at(null_value, 0).unwrap().origin
    is @parameter_binding.Supplied,
  )
  assert_true(
    @parameter_binding.bound_value_at(null_value, 0).unwrap().value.value
    is @value.Null,
  )
  assert_not_eq(identity_cid(selected), identity_cid(overridden))
  for
    input in [
      "{\"id\":9007199254740993}", "{\"id\":\"9223372036854775808\"}", "{\"id\":true}",
    ] {
    assert_true(
      @parameter_binding.bind(definitions, Some(cursor(input)), values_limit())
      is Err(_),
    )
  }
  assert_true(
    @parameter_binding.bind(
      declarations("{\"id\":{\"type\":\"int64\"}}"),
      None,
      values_limit(),
    )
    is Ok(@parameter_binding.NeedsBindings(_)),
  )
  assert_true(
    @parameter_binding.bind(definitions, None, values_limit(nodes=0)) is Err(_),
  )
  assert_true(
    @parameter_binding.bind(definitions, None, values_limit(text=1)) is Err(_),
  )
}
