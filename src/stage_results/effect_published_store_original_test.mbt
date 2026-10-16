///|
fn published_store_input_originals() -> EffectCommandInputs {
  let environment = published_store_environment("object")
  let (mappings, references) = published_store_parts(environment)
  let effects =
    #|{"upload":{"command":{"contract":"command:fixture.upload.v1","from":{"result":"r"},"input":{"id":{"literal":"one"},"value":{"literal":"original"}},"target":{"published_store":{"mapping_ref":"mapping:fixture.archive.v1","target_ref":"connector://storage/archive"}}}}}
  let (checked, headers) = effect_binding_inputs(effects)
  let candidate = prepare_effect_static_candidate(
    headers,
    checked,
    environment,
    mappings,
    references,
    effect_static_candidate_limits(),
  ).unwrap()
  effect_static_candidate_command_inputs(candidate)
}

///|
fn published_store_issued_target(
  live : Ref[Bool],
  kind? : String = "file",
) -> @value.CheckedValue {
  let wire = command_row_target().replace(old="crm/account", new=kind)
  let source = @source.parse_json_bytes(
    @utf8.encode(
      "{\"nullable\":false,\"resource_kind\":\"" +
      kind +
      "\",\"type\":\"resource_ref\"}",
    ),
    { max_input_bytes: 1024, max_nodes: 64, max_depth: 8, },
  ).unwrap()
  let cursor = @decode.admit(source, {
    max_nodes: 64,
    max_depth: 8,
    max_string_bytes: 1024,
    max_total_string_bytes: 1024,
  }).unwrap()
  let contract = @contract.read_checked(cursor, {
    max_nodes: 64,
    max_depth: 8,
    max_text_bytes: 1024,
  }).unwrap()
  let issuer = @value.bind_reference_issuer(
    (_, candidate) => candidate == wire,
    _ => live.val,
  )
  @value.issue_reference(issuer, contract, wire, {
    max_bytes: 1024,
    max_nodes: 64,
    max_depth: 8,
    max_text_units: 1024,
  }).unwrap()
}

///|
test "published STORE projects only the original issued target without a query target field" {
  let inputs = published_store_input_originals()
  let binding = effect_command_input_at(inputs, 0).unwrap()
  let pair = effect_command_target_store_binding(
    effect_command_input_target(binding),
  ).unwrap()
  let live = Ref(true)
  let checked = published_store_issued_target(live)
  let original = bind_effect_published_store_target(binding, pair, checked).unwrap()
  let row = effect_plan_test_row("{\"amount\":1}")
  let expected_target = command_row_target().replace(
    old="crm/account",
    new="file",
  )
  let (selector, changes) = project_effect_command_row(
    binding,
    row,
    2,
    100,
    1024,
    64,
    8,
    published_target=Some(original),
  ).unwrap()
  assert_eq(selector, expected_target)
  assert_eq(
    changes, "{\"state\":\"present\",\"value\":{\"id\":\"one\",\"value\":\"original\"}}",
  )
  assert_eq(
    project_effect_command_row(binding, row, 2, 100, 1024, 64, 8).unwrap_err(),
    MissingTarget,
  )
  assert_eq(
    project_effect_command_row(
      binding,
      row,
      2,
      100,
      20,
      64,
      8,
      published_target=Some(original),
    ).unwrap_err(),
    OutputLimit,
  )
  assert_eq(
    project_effect_command_row(
      binding,
      row,
      2,
      100,
      1024,
      2,
      8,
      published_target=Some(original),
    ).unwrap_err(),
    OutputLimit,
  )
  assert_eq(
    project_effect_command_row(
      binding,
      row,
      2,
      0,
      1024,
      64,
      8,
      published_target=Some(original),
    ).unwrap_err(),
    WorkLimit,
  )
  live.val = false
  assert_false(effect_published_store_target_current(original, binding))
  assert_eq(
    project_effect_command_row(
      binding,
      row,
      2,
      100,
      1024,
      64,
      8,
      published_target=Some(original),
    ).unwrap_err(),
    InvalidTargetOriginal,
  )
  assert_true(
    bind_effect_published_store_target(binding, pair, checked)
    is Err(Unavailable),
  )
}

///|
test "published STORE refuses a foreign occurrence or equal pair and never upgrades DATA to an issuer" {
  let inputs = published_store_input_originals()
  let first = effect_command_input_at(inputs, 0).unwrap()
  let second = effect_command_input_at(inputs, 1).unwrap()
  let pair = effect_command_target_store_binding(
    effect_command_input_target(first),
  ).unwrap()
  let second_pair = effect_command_target_store_binding(
    effect_command_input_target(second),
  ).unwrap()
  let checked = published_store_issued_target(Ref(true))
  assert_true(
    bind_effect_published_store_target(first, second_pair, checked)
    is Err(ForeignBinding),
  )
  let original = bind_effect_published_store_target(first, pair, checked).unwrap()
  assert_false(effect_published_store_target_current(original, second))
  assert_eq(
    project_effect_command_row(
      second,
      effect_plan_test_row("{}"),
      2,
      100,
      1024,
      64,
      8,
      published_target=Some(original),
    ).unwrap_err(),
    InvalidTargetOriginal,
  )
  let foreign = effect_command_input_at(published_store_input_originals(), 0).unwrap()
  let foreign_pair = effect_command_target_store_binding(
    effect_command_input_target(foreign),
  ).unwrap()
  assert_eq(
    @environment.mapping_shape_cid(@environment.store_command_mapping(pair)),
    @environment.mapping_shape_cid(
      @environment.store_command_mapping(foreign_pair),
    ),
  )
  assert_true(
    bind_effect_published_store_target(first, foreign_pair, checked)
    is Err(ForeignBinding),
  )
  let field = effect_command_input_at(command_row_binding("{}", "{}"), 0).unwrap()
  assert_true(
    bind_effect_published_store_target(field, pair, checked)
    is Err(ForeignBinding),
  )
  let plain = @value.checked_text_value(
    "not a Ref",
    @contract.primitive(@contract.StringType, nullable=false),
  ).unwrap()
  assert_true(
    bind_effect_published_store_target(first, pair, plain)
    is Err(IncompatibleReference),
  )
  assert_true(
    bind_effect_published_store_target(
      first,
      pair,
      published_store_issued_target(Ref(true), kind="folder"),
    )
    is Err(IncompatibleReference),
  )
}
