///|
fn presence_fields() -> String {
  let value =
    #|{"name":{"nullable":false,"type":"string"},"overwrite":{"nullable":false,"type":"boolean"}}
  value
}

///|
fn presence_record(
  required : String,
  fields? : String = presence_fields(),
) -> String {
  "{\"additional_properties\":false,\"fields\":" +
  fields +
  ",\"required_fields\":" +
  required +
  "}"
}

///|
fn presence_targets(
  input : String,
  required? : String = "[\"name\"]",
  fields? : String = presence_fields(),
  role? : String? = None,
) -> EffectCommandTargets {
  let (checked, headers) = effect_binding_inputs(
    command_input_effects(input),
    reference_nullable=Some(false),
  )
  let results = bind_effect_results(headers, checked, 20).unwrap()
  bind_effect_command_targets(
    results,
    command_target_catalog(
      "crm/account",
      input_fields=fields,
      required_fields=Some(required),
      input_role_body=match role {
        Some(value) => value
        None => presence_record(required, fields~)
      },
    ),
    100,
  ).unwrap()
}

///|
fn presence_limits() -> EffectCommandInputLimits {
  command_input_limits(work=2000, nodes=200, text=1000)
}

///|
test "Command presence binding omits only absent optional values and retains explicit false" {
  let targets = presence_targets("{\"name\":{\"literal\":\"n\"}}")
  let policies = @environment.check_source_data_policies(
    effect_command_targets_references(targets),
    { max_work: 1000, max_policies: 10, },
  ).unwrap()
  let roles = @environment.check_protocol_value_contracts(policies, {
    max_envelopes: 10,
    contracts: { max_nodes: 200, max_depth: 10, max_text_bytes: 1000, },
  }).unwrap()
  assert_eq(@environment.protocol_value_usage(roles).2, 2)
  let admitted = bind_effect_command_inputs(targets, presence_limits()).unwrap()
  assert_eq(effect_command_input_count(admitted), 2)
  for index in 0..<2 {
    let binding = effect_command_input_at(admitted, index).unwrap()
    assert_eq(effect_command_input_field_count(binding), 1)
    assert_eq(
      effect_command_input_field_name(
        effect_command_input_field_at(binding, 0).unwrap(),
      ),
      "name",
    )
    assert_true(
      physical_equal(
        effect_command_input_target(binding),
        effect_command_target_at(targets, index).unwrap(),
      ),
    )
  }
  let explicit = bind_effect_command_inputs(
    presence_targets(
      "{\"name\":{\"literal\":\"n\"},\"overwrite\":{\"literal\":false}}",
    ),
    presence_limits(),
  ).unwrap()
  let binding = effect_command_input_at(explicit, 0).unwrap()
  assert_eq(effect_command_input_field_count(binding), 2)
  let field = effect_command_input_field_at(binding, 1).unwrap()
  assert_eq(effect_command_input_field_name(field), "overwrite")
  guard effect_command_input_field_value(field) is Literal(value) else {
    abort("explicit literal")
  }
  let writer = @encode.writer(100, 10, 10)
  @value.emit_checked_wire_value(value, writer)
  assert_eq(@encode.finish(writer), "false")
  let empty = bind_effect_command_inputs(
    presence_targets("{}", required="[]"),
    presence_limits(),
  ).unwrap()
  assert_eq(
    effect_command_input_field_count(effect_command_input_at(empty, 0).unwrap()),
    0,
  )
}

///|
test "Command presence binding preserves missing required unknown and null refusals" {
  let cases : Array[(String, EffectCommandInputIssueKind)] = [
    ("{}", MissingField("name")),
    (
      "{\"name\":{\"literal\":\"n\"},\"extra\":{\"literal\":false}}",
      UnknownField("extra"),
    ),
    (
      "{\"name\":{\"literal\":\"n\"},\"overwrite\":{\"literal\":null}}",
      IncompatibleLiteral("overwrite"),
    ),
  ]
  for (input, expected) in cases {
    assert_eq(
      effect_command_input_issue_kind(
        bind_effect_command_inputs(presence_targets(input), presence_limits()).unwrap_err(),
      ),
      expected,
    )
  }
}

///|
test "Command presence binding rejects substituted legacy role subset and array order" {
  let input = "{\"name\":{\"literal\":\"n\"},\"overwrite\":{\"literal\":false}}"
  for
    body in [
      "{}",
      "{\"nullable\":false,\"type\":\"number\"}",
      presence_record("[]"),
      presence_record("[\"overwrite\",\"name\"]"),
      presence_record(
        "[\"name\",\"overwrite\"]",
        fields=presence_fields().replace(old="boolean", new="number"),
      ),
    ] {
    assert_eq(
      effect_command_input_issue_kind(
        bind_effect_command_inputs(
          presence_targets(
            input,
            required="[\"name\",\"overwrite\"]",
            role=Some(body),
          ),
          presence_limits(),
        ).unwrap_err(),
      ),
      InvalidContract,
    )
  }
  let targets = presence_targets(input)
  let foreign = presence_targets(input)
  let target = effect_command_target_contract(
    effect_command_target_at(targets, 0).unwrap(),
  )
  for work in [0, -1] {
    assert_true(
      @environment.command_target_input_contract(
        target,
        effect_command_targets_references(targets),
        { max_nodes: 200, max_depth: 10, max_text_bytes: 1000, },
        work,
      )
      is Err(_),
    )
  }
  assert_true(
    @environment.command_target_input_contract(
      target,
      effect_command_targets_references(foreign),
      { max_nodes: 200, max_depth: 10, max_text_bytes: 1000, },
      2000,
    )
    is Err(@environment.ForeignCommandInputOwner),
  )
}

///|
test "Command presence binding validates omitted child types and exact cumulative budgets" {
  let invalid = presence_fields().replace(old="boolean", new="invalid")
  assert_eq(
    effect_command_input_issue_kind(
      bind_effect_command_inputs(
        presence_targets("{\"name\":{\"literal\":\"n\"}}", fields=invalid),
        presence_limits(),
      ).unwrap_err(),
    ),
    InvalidContract,
  )
  for required in ["null", "[\"name\",\"name\"]", "[\"extra\"]", "[1]"] {
    assert_eq(
      effect_command_input_issue_kind(
        bind_effect_command_inputs(
          presence_targets("{}", required~),
          presence_limits(),
        ).unwrap_err(),
      ),
      InvalidContract,
    )
  }
  let targets = presence_targets("{\"name\":{\"literal\":\"n\"}}")
  let checked = bind_effect_command_inputs(targets, presence_limits()).unwrap()
  let (work, nodes, text) = effect_command_inputs_usage(checked)
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
