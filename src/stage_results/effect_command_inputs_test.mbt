///|
fn command_input_effects(input : String) -> String {
  "{\"command\":{\"command\":{\"target\":{\"field\":\"ref\"},\"contract\":\"command:crm.invoke.v1\",\"from\":{\"result\":\"r\"},\"input\":" +
  input +
  "}}}"
}

///|
fn command_input_targets(
  input : String,
  input_fields : String,
  amount_nullable? : Bool = false,
) -> EffectCommandTargets {
  let (checked, headers) = effect_binding_inputs(
    command_input_effects(input),
    reference_nullable=Some(false),
    amount_nullable~,
  )
  let results = bind_effect_results(headers, checked, 20).unwrap()
  bind_effect_command_targets(
    results,
    command_target_catalog("crm/account", input_fields~),
    100,
  ).unwrap()
}

///|
fn command_input_limits(
  work? : Int = 100,
  nodes? : Int = 30,
  text? : Int = 100,
) -> EffectCommandInputLimits {
  { max_work: work, max_nodes: nodes, max_depth: 10, max_text_bytes: text, }
}

///|
test "Command input binds exact typed Result fields under one budget" {
  let targets = command_input_targets(
    "{\"value\":{\"field\":\"amount\"}}", "{\"value\":{\"nullable\":false,\"type\":\"number\"}}",
  )
  let inputs = bind_effect_command_inputs(targets, command_input_limits()).unwrap()
  assert_true(physical_equal(effect_command_inputs_targets(inputs), targets))
  assert_eq(effect_command_input_count(inputs), 2)
  let first = effect_command_input_at(inputs, 0).unwrap()
  assert_true(
    physical_equal(
      effect_command_input_target(first),
      effect_command_target_at(targets, 0).unwrap(),
    ),
  )
  assert_eq(effect_command_input_field_count(first), 1)
  let field = effect_command_input_field_at(first, 0).unwrap()
  assert_eq(effect_command_input_field_name(field), "value")
  assert_true(effect_command_input_field_value(field) is ResultField(_))
  assert_true(effect_command_input_field_at(first, 1) is None)
  let (used_work, used_nodes, used_text) = effect_command_inputs_usage(inputs)
  assert_true(used_work > 0)
  assert_true(used_nodes > 0)
  assert_true(used_text > 0)
  assert_true(
    bind_effect_command_inputs(targets, command_input_limits(work=used_work))
    is Ok(_),
  )
  assert_eq(
    effect_command_input_issue_kind(
      bind_effect_command_inputs(
        targets,
        command_input_limits(work=used_work - 1),
      ).unwrap_err(),
    ),
    WorkLimit,
  )
  assert_eq(
    effect_command_input_issue_kind(
      bind_effect_command_inputs(
        targets,
        command_input_limits(nodes=used_nodes - 1),
      ).unwrap_err(),
    ),
    WorkLimit,
  )
  assert_eq(
    effect_command_input_issue_kind(
      bind_effect_command_inputs(
        targets,
        command_input_limits(text=used_text - 1),
      ).unwrap_err(),
    ),
    WorkLimit,
  )
}

///|
test "Command input rejects missing, unknown and incompatible fields" {
  let numeric = "{\"value\":{\"nullable\":false,\"type\":\"number\"}}"
  let missing = command_input_targets("{}", numeric)
  assert_eq(
    effect_command_input_issue_kind(
      bind_effect_command_inputs(missing, command_input_limits()).unwrap_err(),
    ),
    MissingField("value"),
  )
  let unknown = command_input_targets("{\"other\":{\"literal\":7}}", "{}")
  assert_eq(
    effect_command_input_issue_kind(
      bind_effect_command_inputs(unknown, command_input_limits()).unwrap_err(),
    ),
    UnknownField("other"),
  )
  let string = command_input_targets(
    "{\"value\":{\"field\":\"amount\"}}", "{\"value\":{\"nullable\":false,\"type\":\"string\"}}",
  )
  assert_eq(
    effect_command_input_issue_kind(
      bind_effect_command_inputs(string, command_input_limits()).unwrap_err(),
    ),
    IncompatibleField("value"),
  )
  let nullable = command_input_targets(
    "{\"value\":{\"field\":\"amount\"}}",
    numeric,
    amount_nullable=true,
  )
  assert_eq(
    effect_command_input_issue_kind(
      bind_effect_command_inputs(nullable, command_input_limits()).unwrap_err(),
    ),
    IncompatibleField("value"),
  )
  let foreign_reference = command_input_targets(
    "{\"value\":{\"field\":\"ref\"}}", "{\"value\":{\"nullable\":false,\"resource_kind\":\"crm/contact\",\"type\":\"resource_ref\"}}",
  )
  assert_eq(
    effect_command_input_issue_kind(
      bind_effect_command_inputs(foreign_reference, command_input_limits()).unwrap_err(),
    ),
    IncompatibleField("value"),
  )
}

///|
test "Command input literals retain typed values and reject foreign types" {
  let numeric = "{\"value\":{\"nullable\":false,\"type\":\"number\"}}"
  let valid = command_input_targets("{\"value\":{\"literal\":7}}", numeric)
  let admitted = bind_effect_command_inputs(valid, command_input_limits()).unwrap()
  assert_true(
    effect_command_input_field_value(
      effect_command_input_field_at(
        effect_command_input_at(admitted, 0).unwrap(),
        0,
      ).unwrap(),
    )
    is Literal(_),
  )
  let foreign = command_input_targets(
    "{\"value\":{\"literal\":\"seven\"}}", numeric,
  )
  let issue = bind_effect_command_inputs(foreign, command_input_limits()).unwrap_err()
  assert_eq(
    effect_command_input_issue_kind(issue),
    IncompatibleLiteral("value"),
  )
  assert_eq(effect_command_input_issue_stage(issue), 0)
  assert_eq(effect_command_input_issue_effect(issue), "command")
  let null_value = command_input_targets(
    "{\"value\":{\"literal\":null}}", numeric,
  )
  assert_eq(
    effect_command_input_issue_kind(
      bind_effect_command_inputs(null_value, command_input_limits()).unwrap_err(),
    ),
    IncompatibleLiteral("value"),
  )
}

///|
fn command_input_literal_wire(
  inputs : EffectCommandInputs,
  index : Int,
) -> String raise {
  let input = effect_command_input_at(inputs, index).unwrap()
  assert_eq(effect_command_input_field_count(input), 1)
  let field = effect_command_input_field_at(input, 0).unwrap()
  assert_eq(effect_command_input_field_name(field), "value")
  guard effect_command_input_field_value(field) is Literal(checked) else {
    abort("expected an admitted Command literal")
  }
  let writer = @encode.writer(10000, 1000, 20)
  @value.emit_checked_wire_value(checked, writer)
  @encode.finish(writer)
}

///|
test "Command JSON literals retain exact source keys and aggregate bounds" {
  let source =
    #|{"value":{"literal":{"é":1,"é":2,"\r":3,"\n":4,"\r\n":5,"nested":[{"$json":{"é":"é\r\n"}},null]}}}
  let fields =
    #|{"value":{"nullable":false,"type":"json"}}
  let expected =
    #|{"$json":{"\n":4,"\r":3,"\r\n":5,"é":2,"nested":[{"$json":{"é":"é\r\n"}},null],"é":1}}
  // This fixture parses an actual Program and binds both Stage commands to
  // their Catalog-owned input contract before literal admission.
  let targets = command_input_targets(source, fields)
  let limits = command_input_limits(work=1000, nodes=200, text=1000)
  let admitted = bind_effect_command_inputs(targets, limits).unwrap()
  assert_eq(effect_command_input_count(admitted), 2)
  for index in 0..<effect_command_input_count(admitted) {
    assert_eq(command_input_literal_wire(admitted, index), expected)
  }
  let (work, nodes, text) = effect_command_inputs_usage(admitted)
  let exact = command_input_limits(work~, nodes~, text~)
  assert_true(bind_effect_command_inputs(targets, exact) is Ok(_))
  for
    reduced in [
      { ..exact, max_work: work - 1, },
      { ..exact, max_nodes: nodes - 1, },
      { ..exact, max_text_bytes: text - 1, },
    ] {
    assert_eq(
      effect_command_input_issue_kind(
        bind_effect_command_inputs(targets, reduced).unwrap_err(),
      ),
      WorkLimit,
    )
  }
}

///|
test "Command Object literal normalizes fields without normalizing nested JSON" {
  let source =
    #|{"value":{"literal":{"é":"v","nested":[{"é":2,"é":1,"\r\n":"data"}]}}}
  let fields =
    #|{"value":{"additional_properties":false,"fields":{"nested":{"items":{"nullable":false,"type":"json"},"nullable":false,"type":"array"},"é":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"}}
  let expected =
    #|{"nested":[{"$json":{"\r\n":"data","é":1,"é":2}}],"é":"v"}
  let targets = command_input_targets(source, fields)
  let admitted = bind_effect_command_inputs(
    targets,
    command_input_limits(work=1000, nodes=200, text=1000),
  ).unwrap()
  assert_eq(effect_command_input_count(admitted), 2)
  for index in 0..<effect_command_input_count(admitted) {
    assert_eq(command_input_literal_wire(admitted, index), expected)
  }
}

///|
test "Command Object literal rejects normalized field collision after source admission" {
  let source =
    #|{"value":{"literal":{"é":"first","é":"second","nested":[{"é":1,"é":2}]}}}
  let fields =
    #|{"value":{"additional_properties":false,"fields":{"nested":{"items":{"nullable":false,"type":"json"},"nullable":false,"type":"array"},"é":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"}}
  // Source parsing admits both exact spellings inside the quoted subtree;
  // the checked Object contract is what makes these two fields collide.
  let targets = command_input_targets(source, fields)
  let issue = bind_effect_command_inputs(
    targets,
    command_input_limits(work=1000, nodes=200, text=1000),
  ).unwrap_err()
  assert_eq(
    effect_command_input_issue_kind(issue),
    IncompatibleLiteral("value"),
  )
  assert_eq(effect_command_input_issue_stage(issue), 0)
  assert_eq(effect_command_input_issue_effect(issue), "command")
}
