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
