///|
fn command_row_binding(input : String, fields : String) -> EffectCommandInputs {
  bind_effect_command_inputs(
    command_input_targets(input, fields, amount_nullable=true),
    command_input_limits(work=2000, nodes=200, text=2000),
  ).unwrap()
}

///|
fn command_row_target() -> String {
  (
    // This independent wire is a projection vector, not ReferenceIssuer
    // admission or evidence of current target authorization.
    #|{"$actql_ref":"resource","authority_scope_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","boundary_cid":"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","identity_cid":"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","provider_identity_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","provider_namespace":"crm","resource_kind":"crm/account","version":"actql-resource-ref/0.1"}
  )
}

///|
test "Command row selects the original authored member rather than command index" {
  let inputs = command_row_binding(
    (
      #|{"value":{"field":"amount"}}
    ),
    (
      #|{"value":{"nullable":true,"type":"number"}}
    ),
  )
  for index in 0..<2 {
    let selected = effect_command_input_for_member(inputs, index, 3)
      .unwrap()
      .unwrap()
    assert_true(
      physical_equal(selected, effect_command_input_at(inputs, index).unwrap()),
    )
  }
  assert_true(effect_command_input_for_member(inputs, 0, 2) is Err(WorkLimit))
  assert_true(
    effect_command_input_for_member(inputs, 2, 3) is Err(InvalidMember),
  )
}

///|
test "Command row retains exact target, typed NULL and admitted literal" {
  let inputs = command_row_binding(
    (
      #|{"z":{"literal":{"é":"é\r\n","é":2}},"a":{"field":"amount"}}
    ),
    (
      #|{"a":{"nullable":true,"type":"number"},"z":{"nullable":false,"type":"json"}}
    ),
  )
  let binding = effect_command_input_at(inputs, 0).unwrap()
  let target = command_row_target()
  let row = effect_plan_test_row("{\"amount\":null,\"ref\":" + target + "}")
  // Two Result bindings, three possible lookups over a two-field row and a
  // two-field sort: 2 + 3 + 3*2 + 2*2 = 15 units of planning capacity.
  let (selector, changes) = project_effect_command_row(
    binding, row, 2, 15, 1024, 64, 8,
  ).unwrap()
  assert_eq(selector, target)
  assert_eq(
    changes,
    (
      #|{"state":"present","value":{"a":null,"z":{"$json":{"é":"é\r\n","é":2}}}}
    ),
  )
  assert_eq(
    project_effect_command_row(binding, row, 2, 14, 1024, 64, 8).unwrap_err(),
    WorkLimit,
  )
  assert_eq(
    project_effect_command_row(binding, row, 1, 15, 1024, 64, 8).unwrap_err(),
    WorkLimit,
  )
  assert_eq(
    project_effect_command_row(binding, row, 2, 15, 20, 64, 8).unwrap_err(),
    OutputLimit,
  )
}

///|
test "Command row never invents missing input or null target" {
  let inputs = command_row_binding(
    (
      #|{"value":{"field":"amount"}}
    ),
    (
      #|{"value":{"nullable":true,"type":"number"}}
    ),
  )
  let binding = effect_command_input_at(inputs, 0).unwrap()
  assert_eq(
    project_effect_command_row(
      binding,
      effect_plan_test_row("{\"ref\":" + command_row_target() + "}"),
      1,
      100,
      1024,
      64,
      8,
    ).unwrap_err(),
    MissingSourceField("amount"),
  )
  for wire in ["{\"amount\":7}", "{\"amount\":7,\"ref\":null}"] {
    assert_eq(
      project_effect_command_row(
        binding,
        effect_plan_test_row(wire),
        1,
        100,
        1024,
        64,
        8,
      ).unwrap_err(),
      MissingTarget,
    )
  }
  assert_eq(
    project_effect_command_row(
      binding,
      effect_plan_test_row("[]"),
      1,
      100,
      1024,
      64,
      8,
    ).unwrap_err(),
    InvalidRow,
  )
}

///|
test "Command empty input still projects the required target" {
  let inputs = command_row_binding("{}", "{}")
  let row = effect_plan_test_row("{\"ref\":" + command_row_target() + "}")
  // Target binding + one lookup over one Result field = 3 units.
  assert_eq(
    project_effect_command_row(
      effect_command_input_at(inputs, 0).unwrap(),
      row,
      0,
      3,
      1024,
      64,
      8,
    ).unwrap(),
    (command_row_target(), "{\"state\":\"present\",\"value\":{}}"),
  )
  assert_eq(
    project_effect_command_row(
      effect_command_input_at(inputs, 0).unwrap(),
      row,
      0,
      2,
      1024,
      64,
      8,
    ).unwrap_err(),
    WorkLimit,
  )
}

///|
test "Command selection retains authored ordinals around Mapping members" {
  let effects =
    #|{"a_update":{"update":{"target":"crm","mapping":"mapping:crm.update.v1","from":{"result":"r"},"id":"amount","set":{"value":{"field":"amount"}}}},"z_command":{"command":{"target":{"field":"ref"},"contract":"command:crm.invoke.v1","from":{"result":"r"},"input":{"value":{"field":"amount"}}}}}
  let (checked, headers) = effect_binding_inputs(
    effects,
    reference_nullable=Some(false),
  )
  let results = bind_effect_results(headers, checked, 50).unwrap()
  let targets = bind_effect_command_targets(
    results,
    command_target_catalog(
      "crm/account",
      input_fields=(
        #|{"value":{"nullable":false,"type":"number"}}
      ),
    ),
    100,
  ).unwrap()
  let inputs = bind_effect_command_inputs(
    targets,
    command_input_limits(work=1000),
  ).unwrap()
  assert_eq(effect_result_binding_count(results), 4)
  assert_eq(effect_command_input_count(inputs), 2)
  for (member_index, command_index) in [(1, 0), (3, 1)] {
    assert_true(
      physical_equal(
        effect_command_input_for_member(inputs, member_index, 3)
        .unwrap()
        .unwrap(),
        effect_command_input_at(inputs, command_index).unwrap(),
      ),
    )
  }
  for member_index in [0, 2] {
    assert_true(
      effect_command_input_for_member(inputs, member_index, 3) is Ok(None),
    )
  }
}
