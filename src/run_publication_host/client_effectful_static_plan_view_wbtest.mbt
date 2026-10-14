///|
fn effectful_static_value(wire : String) -> @canonical.CanonicalValue {
  @publication.parse_interactive_run_control_shape(
    "effectful_static_plan_view", wire, 65536, 8192, 64,
  ).unwrap()
}

///|
fn effectful_static_string_field(
  value : @canonical.CanonicalValue,
  field : String,
) -> String {
  match @canonical.object_field(value, field) {
    Some(@canonical.String(text)) => text
    _ => fail("missing static string field")
  }
}

///|
test "Effectful static envelope keeps the original computation bytes and honest unknowns" {
  let (original, compiled) = effect_static_computation_fixture()
  let component = client_effect_static_computation_plan_view(
    original, compiled, 65536, 8192, 64,
  ).unwrap()
  let wire = client_effectful_static_plan_view(
    original, compiled, 65536, 8192, 64,
  ).unwrap()
  let value = effectful_static_value(wire)
  let computation = @canonical.object_field(value, "computation").unwrap()
  assert_eq(
    effectful_static_string_field(computation, "scope"),
    "computation_component",
  )
  assert_eq(
    @canonical.stringify_value(
      @canonical.object_field(computation, "plan_view").unwrap(),
      65536,
      8192,
      64,
    ),
    component,
  )
  let identity = prepared_client_effect_identity(original)
  assert_eq(
    effectful_static_string_field(value, "program_definition_cid"),
    identity.program_definition_cid,
  )
  assert_eq(
    effectful_static_string_field(value, "parameter_values_cid"),
    identity.parameter_values_cid,
  )
  assert_eq(
    effectful_static_string_field(value, "check_environment_cid"),
    prepared_client_effect_computation_environment_cid(original),
  )
  let observations = @canonical.object_field(value, "observations").unwrap()
  for
    field in [
      "permission", "gate", "approval", "resolved_targets", "changed_values",
    ] {
    let observed = @canonical.object_field(observations, field).unwrap()
    assert_eq(effectful_static_string_field(observed, "state"), "unknown")
  }
  assert_true(wire.contains("\"provider_io\":0"))
  assert_true(
    wire.contains(
      "\"preview\":{\"reason\":\"not_sealed\",\"state\":\"unavailable\"}",
    ),
  )
  assert_true(!wire.contains("checkpoint_cid"))
  assert_true(!wire.contains("run_ref"))
  assert_true(original.normalization is None)
  assert_true(original.normalization_custody is None)
}

///|
test "Effectful static envelope retains checked member coordinates not invented graph edges" {
  let (original, compiled) = effect_static_computation_fixture()
  let value = effectful_static_value(
    client_effectful_static_plan_view(original, compiled, 65536, 8192, 64).unwrap(),
  )
  let set = @canonical.object_field(value, "effect_set").unwrap()
  assert_eq(effectful_static_string_field(set, "unit_id"), "source")
  let wire = @canonical.stringify_value(set, 65536, 8192, 64)
  // The Mapping CID is independent of this issuer, from the authored fixture.
  assert_true(
    wire.contains(
      "sha256:ce8b7dc9c08beafcd15440c15026a857361f9e04a2c1d9dec4bc8c9ab9f40283",
    ),
  )
  assert_true(wire.contains("\"declared_target\":\"connector://crm/account\""))
  assert_true(
    wire.contains("\"input\":{\"kind\":\"result\",\"result_name\":\"out\"}"),
  )
  assert_true(wire.contains("\"member_ordinal\":0"))
  assert_true(wire.contains("\"stage_ordinal\":0"))
  assert_true(wire.contains("\"effect_kind\":\"update\""))
  assert_true(
    wire.contains(
      "\"minimum_approval\":{\"kind\":\"contract_minimum\",\"value\":\"none\"}",
    ),
  )
  assert_true(!wire.contains("edge"))
  assert_true(!wire.contains("approved"))
}

///|
test "Effectful static issuer refuses equal valued foreign opaque preparations" {
  let (original, compiled) = effect_static_computation_fixture()
  let (other, other_compiled) = effect_static_computation_fixture()
  assert_eq(
    prepared_client_effect_identity(original),
    prepared_client_effect_identity(other),
  )
  assert_true(
    client_effectful_static_plan_view(other, compiled, 65536, 8192, 64)
    is Err(ForeignCompilation),
  )
  assert_true(
    client_effectful_static_plan_view(original, other_compiled, 65536, 8192, 64)
    is Err(ForeignCompilation),
  )
}

///|
test "Effectful static snapshot mutation cannot change a reissued original envelope" {
  let (original, compiled) = effect_static_computation_fixture()
  let before = client_effectful_static_plan_view(
    original, compiled, 65536, 8192, 64,
  ).unwrap()
  let snapshot = client_effect_static_declarations(
    original, compiled, 64, 10000,
  ).unwrap()
  snapshot.members.clear()
  assert_eq(
    client_effectful_static_plan_view(original, compiled, 65536, 8192, 64).unwrap(),
    before,
  )
}

///|
test "Effectful static binding refuses independently changed Program parameters and environment" {
  let (original, compiled) = effect_static_computation_fixture()
  let wire = client_effectful_static_plan_view(
    original, compiled, 65536, 8192, 64,
  ).unwrap()
  assert_true(
    check_client_effectful_static_plan_view_binding(
      original, compiled, wire, 65536, 8192, 64,
    )
    is Ok(_),
  )
  let value = effectful_static_value(wire)
  for
    field in [
      "program_definition_cid", "parameter_values_cid", "check_environment_cid",
    ] {
    let changed = @canonical.object_with_string_field(
      value, field, "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
    ).unwrap()
    let changed_wire = @canonical.stringify_value(changed, 65536, 8192, 64)
    assert_true(
      check_client_effectful_static_plan_view_binding(
        original, compiled, changed_wire, 65536, 8192, 64,
      )
      is Err(ForeignProjection),
    )
  }
  // Authored mutations target only static metadata, never a Run or saved DB.
  for
    changed_wire in [
      wire.replace(old="\"unit_id\":\"source\"", new="\"unit_id\":\"foreign\""),
      wire.replace(old="\"member_ordinal\":0", new="\"member_ordinal\":1"),
      wire.replace(old="\"stage_ordinal\":0", new="\"stage_ordinal\":1"),
      wire.replace(
        old="\"effect_id\":\"save\"",
        new="\"effect_id\":\"foreign\"",
      ),
    ] {
    assert_true(changed_wire != wire)
    assert_true(
      check_client_effectful_static_plan_view_binding(
        original, compiled, changed_wire, 65536, 8192, 64,
      )
      is Err(ForeignProjection),
    )
  }
  let component = @canonical.stringify_value(
    @canonical.object_field(
      @canonical.object_field(value, "computation").unwrap(),
      "plan_view",
    ).unwrap(),
    65536,
    8192,
    64,
  )
  for field in ["compiled_plan_cid", "self_cid"] {
    let component_json = @json.parse(component)
    guard component_json is Object(fields) else {
      fail("missing component object")
    }
    let foreign = Json::string(
      "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
    )
    if field == "compiled_plan_cid" {
      fields[field] = foreign
    } else {
      guard fields.get("logical_map") is Some(Object(map)) else {
        fail("missing map")
      }
      map[field] = foreign
    }
    let changed = @canonical.stringify_value(
      @canonical.from_json(component_json, 8192, 64, 65536, data_keys=true),
      65536,
      8192,
      64,
    )
    assert_true(changed != component)
    let changed_wire = wire.replace(old=component, new=changed)
    // Closed shape alone is not original compiler/Plan-map correspondence.
    assert_true(
      @publication.parse_interactive_run_control_shape(
        "effectful_static_plan_view", changed_wire, 65536, 8192, 64,
      )
      is Ok(_),
    )
    assert_true(
      check_client_effectful_static_plan_view_binding(
        original, compiled, changed_wire, 65536, 8192, 64,
      )
      is Err(ForeignProjection),
    )
  }
}

///|
test "Effectful static read emit and metadata work preserve exact and minus one bounds" {
  let (original, compiled) = effect_static_computation_fixture()
  let wire = client_effectful_static_plan_view(
    original,
    compiled,
    65536,
    8192,
    64,
    max_members=1,
    max_work=7,
  ).unwrap()
  let parsed = @source.parse_json_bytes_measured(@utf8.encode(wire), {
    max_input_bytes: 65536,
    max_nodes: 8192,
    max_depth: 64,
  }).unwrap()
  let usage = parsed.usage
  assert_eq(
    client_effectful_static_plan_view(
      original,
      compiled,
      usage.input_bytes,
      usage.nodes,
      usage.depth,
      max_members=1,
      max_work=7,
    ).unwrap(),
    wire,
  )
  assert_true(
    client_effectful_static_plan_view(
      original,
      compiled,
      usage.input_bytes - 1,
      8192,
      64,
    )
    is Err(_),
  )
  assert_true(
    client_effectful_static_plan_view(
      original,
      compiled,
      65536,
      usage.nodes - 1,
      64,
    )
    is Err(_),
  )
  assert_true(
    client_effectful_static_plan_view(
      original,
      compiled,
      65536,
      8192,
      usage.depth - 1,
    )
    is Err(_),
  )
  assert_true(
    client_effectful_static_plan_view(
      original,
      compiled,
      65536,
      8192,
      64,
      max_members=1,
      max_work=6,
    )
    is Err(_),
  )
  assert_true(
    client_effectful_static_plan_view(
      original,
      compiled,
      65536,
      8192,
      64,
      max_members=0,
    )
    is Err(_),
  )
  assert_true(
    client_effectful_static_plan_view(original, compiled, 0, 8192, 64)
    is Err(InvalidLimits),
  )
}

///|
test "Effectful static envelope shares one declaration work allowance across both members" {
  let (document, environment, limits) = local_update_normalization_fixture()
  let body =
    #|{"update":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"out"},"id":"id","set":{"Name":{"field":"value"}}}}
  let document = document.replace(
    old="\"effects\":{\"save\":" + body + "}",
    new="\"effects\":{\"save\":" + body + ",\"save2\":" + body + "}",
  )
  let original = prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    {
      ..limits,
      max_members: 2,
      effects: { ..limits.effects, max_members: 2, },
    },
  ).unwrap()
  let bounds = run_materials_limits()
  let compiled = issue_prepared_client_effect_compilation(
    original,
    run_materials_manifests(),
    bounds.sequence,
    bounds.max_sequence_steps,
    bounds.max_sequence_work,
    bounds.max_evidence_bytes,
    bounds.max_evidence_nodes,
    bounds.max_evidence_depth,
  ).unwrap()
  let wire = client_effectful_static_plan_view(
    original,
    compiled,
    65536,
    8192,
    64,
    max_members=2,
    max_work=20,
  ).unwrap()
  assert_true(wire.contains("\"effect_id\":\"save2\""))
  assert_true(
    client_effectful_static_plan_view(
      original,
      compiled,
      65536,
      8192,
      64,
      max_members=2,
      max_work=19,
    )
    is Err(_),
  )
  assert_true(
    client_effectful_static_plan_view(
      original,
      compiled,
      65536,
      8192,
      64,
      max_members=1,
      max_work=20,
    )
    is Err(_),
  )
}
