///|
fn input_key_effects(key : String?, published? : Bool = false) -> String {
  "{\"command\":{\"command\":{\"from\":{\"result\":\"r\"},\"target\":" +
  (if published {
    "{\"published_command\":{\"target_ref\":\"connector://mailbox/current\",\"identifier_field\":\"amount\"}}"
  } else {
    "{\"field\":\"ref\"}"
  }) +
  ",\"contract\":\"" +
  (if published { "command:mail.send.v1" } else { "command:crm.invoke.v1" }) +
  "\",\"input\":" +
  (if published { "{\"body\":{\"literal\":\"original\"}}" } else { "{}" }) +
  (match key {
    None => ""
    Some(name) => ",\"input_key\":\"" + name + "\""
  }) +
  "}}}"
}

///|
fn input_key_targets(
  key : String?,
  published? : Bool = false,
) -> EffectCommandTargets {
  let (checked, headers) = effect_binding_inputs(
    input_key_effects(key, published~),
    reference_nullable=Some(false),
  )
  let results = bind_effect_results(headers, checked, 100).unwrap()
  bind_effect_command_targets(
    results,
    if published {
      published_command_references("identifier-number")
    } else {
      command_target_catalog("crm/account")
    },
    10000,
  ).unwrap()
}

///|
test "Command input key getter retains exact typed field and original Effect binding at every stage" {
  let targets = input_key_targets(Some("amount"))
  let inputs = bind_effect_command_inputs(targets, command_input_limits()).unwrap()
  for index in 0..<2 {
    let original = effect_command_target_at(targets, index).unwrap()
    let input = effect_command_input_at(inputs, index).unwrap()
    assert_true(physical_equal(effect_command_input_target(input), original))
    let effect = effect_command_target_effect(original)
    let header = effect_result_binding_header(effect)
    assert_eq(@syntax.effect_header_stage(header), index)
    assert_eq(@syntax.effect_header_command_input_key(header), Some("amount"))
    let key = effect_command_input_key(input).unwrap()
    let bound = effect_result_field_binding_at(effect, 1).unwrap()
    assert_eq(effect_result_field_binding_role(bound), EffectCommandInputKey)
    assert_true(physical_equal(key, effect_result_field_binding_field(bound)))
    assert_eq(@schema.field_reference_name(key), "amount")
    assert_true(!@schema.field_contract(key).nullable)
    assert_eq(effect_command_input_field_count(input), 0)
  }
  assert_true(
    !physical_equal(
      effect_command_input_at(inputs, 0).unwrap(),
      effect_command_input_at(inputs, 1).unwrap(),
    ),
  )
}

///|
test "authored Command input key and declared target identifier retain different original fields" {
  let targets = input_key_targets(Some("ref"), published=true)
  let inputs = bind_effect_command_inputs(
    targets,
    command_input_limits(work=10000, nodes=100, text=10000),
  ).unwrap()
  let input = effect_command_input_at(inputs, 0).unwrap()
  assert_eq(
    @schema.field_reference_name(effect_command_input_key(input).unwrap()),
    "ref",
  )
  let effect = effect_command_target_effect(effect_command_input_target(input))
  let identifier = effect_result_field_binding_at(effect, 0).unwrap()
  assert_eq(
    effect_result_field_binding_role(identifier),
    EffectCommandIdentifier,
  )
  assert_eq(
    @schema.field_reference_name(effect_result_field_binding_field(identifier)),
    "amount",
  )
  assert_eq(effect_command_input_field_count(input), 1)
  assert_eq(
    effect_command_input_field_name(
      effect_command_input_field_at(input, 0).unwrap(),
    ),
    "body",
  )
}

///|
test "Command input key refuses missing nullable and non KeyComparable original fields before capture" {
  let cases : Array[
    (String, Bool, @contract.Primitive, EffectResultBindingIssueKind),
  ] = [
    ("missing", false, @contract.NumberType, MissingField),
    ("amount", true, @contract.NumberType, InvalidCommandInputKey),
    ("amount", false, @contract.JsonType, InvalidCommandInputKey),
  ]
  for (name, nullable, kind, expected) in cases {
    let (checked, headers) = effect_binding_inputs(
      input_key_effects(Some(name)),
      reference_nullable=Some(false),
      amount_type=Some(@contract.primitive(kind, nullable~)),
    )
    let issue = bind_effect_results(headers, checked, 100).unwrap_err()
    assert_eq(effect_result_binding_issue_kind(issue), expected)
    assert_eq(effect_result_binding_issue_field(issue), Some(name))
    assert_eq(effect_result_binding_issue_stage(issue), 0)
    assert_eq(effect_result_binding_issue_effect(issue), "command")
  }
}

///|
test "Command input key stays absent for legacy members and shares existing binding budgets" {
  let old = bind_effect_command_inputs(
    input_key_targets(None),
    command_input_limits(),
  ).unwrap()
  assert_true(
    effect_command_input_key(effect_command_input_at(old, 0).unwrap()) is None,
  )
  let targets = input_key_targets(Some("amount"))
  let inputs = bind_effect_command_inputs(targets, command_input_limits()).unwrap()
  let (work, _, _) = effect_command_inputs_usage(inputs)
  assert_true(
    bind_effect_command_inputs(targets, command_input_limits(work~)) is Ok(_),
  )
  assert_eq(
    effect_command_input_issue_kind(
      bind_effect_command_inputs(targets, command_input_limits(work=work - 1)).unwrap_err(),
    ),
    WorkLimit,
  )
  let (checked, headers) = effect_binding_inputs(
    input_key_effects(Some("amount")),
    reference_nullable=Some(false),
  )
  let bound = bind_effect_results(headers, checked, 100).unwrap()
  let used = effect_result_bindings_work(bound)
  assert_true(bind_effect_results(headers, checked, used) is Ok(_))
  assert_eq(
    effect_result_binding_issue_kind(
      bind_effect_results(headers, checked, used - 1).unwrap_err(),
    ),
    WorkLimit,
  )
  let (foreign, _) = effect_binding_inputs(
    input_key_effects(Some("amount")),
    reference_nullable=Some(false),
  )
  assert_eq(
    effect_result_binding_issue_kind(
      bind_effect_results(headers, foreign, 100).unwrap_err(),
    ),
    ForeignProgram,
  )
}
