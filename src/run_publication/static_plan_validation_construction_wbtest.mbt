///|
let validator_plan_view_fixture : String =
  #|{"capabilities":{"cost_guard":false,"durable_control":false,"execution_batch":false,"full_intermediate_retention":[],"inspect":false,"policy_revision_cid":"sha256:9999999999999999999999999999999999999999999999999999999999999999","sample_capture":[],"static_plan":true},"compiled_plan_cid":"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22","logical_map":{"compiled_plan_cid":"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22","program_definition_cid":"sha256:3333333333333333333333333333333333333333333333333333333333333333","self_cid":"sha256:867d5e152bedc53aa4d4015b25da927eef2589c59d127040ee7b4f6af16fbf14","steps":[{"can_stop_after":false,"can_stop_before":false,"key":{"compiled_plan_cid":"sha256:e601408109081ed6fef39782d17940a2a216d9166ba0e249f370769410fe6c22","occurrence":{"input_port_ordinal":0,"kind":"input_output"},"self_cid":"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b","stage_ordinal":1,"version":"actql-logical-step-key/0.1"},"names":["answer"],"operator":null,"ports":[{"can_sample":false,"carrier":"relation","carrier_contract_cid":"sha256:7777777777777777777777777777777777777777777777777777777777777777","port_id":"sha256:abbcfe1695d0131a6ea1bce21d849de09b3f861fd66a7456ff8274ac1faa0ce2","port_ordinal":0,"role":"input","sample_reason":"not_installed","source":{"input_port_ordinal":0,"kind":"stage_input","stage_ordinal":1}},{"can_sample":false,"carrier":"relation","carrier_contract_cid":"sha256:7777777777777777777777777777777777777777777777777777777777777777","port_id":"sha256:a231373ceaedc02373d14b4ed788390f5f0961e1b1d561085b7fea28278821b4","port_ordinal":0,"role":"output","sample_reason":"not_installed","source":{"input_port_ordinal":0,"kind":"stage_input","stage_ordinal":1}}],"step_id":"sha256:783641dbc77abc7291465c218c6270228415f6d432d50aff0d4b19a2c080e82b","stop_reason":"not_installed"}],"version":"actql-logical-map/0.1"},"observation":"static","provider_io":0,"quantities":[{"kind":"unknown","reason":"not_observed","unit":"work"}],"version":"actql-plan-view/0.1"}

///|
fn validator_observed_pending(
  name : String,
  complete : Bool,
  value : @json.CanonicalValue,
) -> (Int, Bool) {
  let cursor = start_protocol_validation(
    value,
    generated_protocol_schema_root(name, complete).unwrap(),
    protocol_schema_nodes(),
    {
      remaining: 100000,
      max_wire_bytes: 1000000,
      max_nodes: 100000,
      max_depth: 100,
    },
  )
  let mut peak = cursor.pending.length()
  while !cursor.pending.is_empty() {
    cursor.step()
    peak = Int::max(peak, cursor.pending.length())
  }
  (peak, cursor.result)
}

///|
test "static plan validator profiles derive continuations from original schema DAG" {
  for (name, complete, profile) in static_plan_validation_profiles {
    assert_true(profile is Some(_), msg=name)
    let fresh = fresh_static_plan_validation_construction(name, complete, 40).unwrap()
    assert_true(fresh.pending_reference_items > 0L)
    assert_true(fresh.owner.record_headers > fresh.pending_reference_items)
    if name == "logical_step_key" || name == "logical_port_key" {
      assert_eq(fresh.unique_reference_items, 0L)
      assert_eq(fresh.unique_item_bytes, 0)
    } else if name == "logical_map" || name == "plan_view" {
      assert_eq(fresh.unique_reference_items, 1L)
      assert_eq(fresh.unique_item_bytes, 0)
      assert_eq(fresh.unique_item_nodes, 0)
      assert_eq(fresh.unique_item_depth, 0)
    }
  }
  assert_true(
    fresh_static_plan_validation_construction("unowned", true, 40) is None,
  )
  assert_true(
    fresh_static_plan_validation_construction("plan_view", true, -1) is None,
  )
  assert_true(
    cold_static_plan_validation_construction("plan_view", true, -1, 0L, 0, 0, 0)
    is None,
  )
}

///|
test "actual nested plan view validation fits original continuation profile" {
  let view = parse_contract_wire(
    validator_plan_view_fixture, 1000000, 100000, 100,
  ).unwrap()
  let map = @json.object_field(view, "logical_map").unwrap()
  for (name, value) in [("plan_view", view), ("logical_map", map)] {
    let (peak, accepted) = validator_observed_pending(name, true, value)
    assert_true(accepted)
    let profile = fresh_static_plan_validation_construction(name, true, 8).unwrap()
    assert_true(peak.to_int64() <= profile.pending_reference_items)
  }
}

///|
test "cold validation borrows unique StringRule items without serializer construction" {
  let fresh = fresh_static_plan_validation_construction("plan_view", true, 8).unwrap()
  let cold = cold_static_plan_validation_construction(
    "plan_view", true, 128, 8192L, 4096, 1000, 30,
  ).unwrap()
  assert_eq(cold.unique_reference_items, 128L)
  assert_eq(cold.owned_utf16_units, 0L)
  assert_eq(cold.unique_item_bytes, 0)
  assert_eq(cold.unique_item_nodes, 0)
  assert_eq(cold.unique_item_depth, 0)
  assert_true(cold.owner.reference_slots > fresh.owner.reference_slots)
  let bad = parse_contract_wire("[{\"nested\":[1,2,3]}]", 4096, 100, 10).unwrap()
  guard bad is @json.Array(items) else { fail("array") }
  let budget : ProtocolValidationBudget = {
    remaining: 100,
    max_wire_bytes: 4096,
    max_nodes: 100,
    max_depth: 10,
  }
  assert_true(protocol_unique_array(@json.array_values(items), budget))
  assert_false(protocol_unique_string_array(@json.array_values(items), budget))
}

///|
test "original Effect evidence validator profiles cover timestamp and path-prefix constructors" {
  let cid = "sha256:" + "1".repeat(64)
  let prepared = "{\"version\":\"actql-prepared-invocation/0.1\",\"invocation_template_cid\":\"" +
    cid +
    "\",\"compiled_plan_cid\":\"" +
    cid +
    "\",\"execution_context_cid\":\"" +
    cid +
    "\",\"host_policy_cid\":\"" +
    cid +
    "\",\"policy_decision\":\"allow\",\"expires_at\":\"2026-11-15T00:00:00.000Z\",\"execution_material\":{\"program\":{},\"parameter_values\":{},\"invocation_bindings\":{}},\"prepared_invocation_cid\":\"" +
    cid +
    "\"}"
  let authorization = "{\"version\":\"actql-run-authorization/0.1\",\"prepared_invocation_cid\":\"" +
    cid +
    "\",\"execution_context_cid\":\"" +
    cid +
    "\",\"host_policy_cid\":\"" +
    cid +
    "\",\"decision\":\"allowed\",\"run_authorization_cid\":\"" +
    cid +
    "\"}"
  let normalization = "{\"version\":\"actql-normalization-journal/0.1\",\"rule_catalog_cid\":\"" +
    cid +
    "\",\"entries\":[{\"path\":\"$.x\",\"rule\":\"normalize\",\"authored\":\"old\",\"canonical\":\"new\"}],\"journal_cid\":\"" +
    cid +
    "\"}"
  for
    (name, wire) in [
      ("prepared_invocation", prepared),
      ("run_authorization", authorization),
      ("normalization_journal", normalization),
    ] {
    let value = parse_contract_wire(wire, 4096, 128, 8).unwrap()
    let profile = cold_static_plan_validation_construction(
      name, true, 128, 4096L, 4096, 128, 8,
    ).unwrap()
    let (peak, accepted) = validator_observed_pending(name, true, value)
    assert_true(accepted, msg=name)
    assert_true(peak.to_int64() <= profile.pending_reference_items, msg=name)
    assert_eq(profile.unique_reference_items, 0L)
    assert_eq(profile.owned_utf16_units, 0L)
  }
  guard static_plan_validation_selected_profile("prepared_invocation", true)
    is Some((_, _, timestamp)) else {
    fail("profile")
  }
  assert_true(timestamp)
  guard static_plan_validation_selected_profile("normalization_journal", true)
    is Some((_, unique, timestamp)) else {
    fail("profile")
  }
  assert_false(unique)
  assert_false(timestamp)
}

///|
// Independent authored structural vectors; these literals do not come from
// the product issuer. The real generated validator still owns acceptance.
let validator_explanation_body : String =
  #|{"version":"actql-explanation-facts/0.1","disclosure":"structural","program_definition_cid":"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","parameter_values_cid":"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","compiled_plan_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","logical_map_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","steps":[{"step_id":"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8","key":{"version":"actql-logical-step-key/0.1","compiled_plan_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","stage_ordinal":0,"occurrence":{"kind":"operation","operation_ordinal":0},"self_cid":"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8"},"operator":"filter","input_ports":["sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"],"output_ports":["sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"],"meaning":{"kind":"filter","predicate":{"state":"projected","root":0,"nodes":[{"form":"operation","operator":"gt","children":[1,2],"type":{"projection":"shape_and_nullability","kind":"boolean","nullable":false}},{"form":"field","scope":"fields","name":"id","type":{"projection":"shape_and_nullability","kind":"number","nullable":false}},{"form":"literal_redacted","type":{"projection":"shape_and_nullability","kind":"number","nullable":false}}]}}}]}

///|
let validator_explanation_facts : String =
  #|{"version":"actql-explanation-facts/0.1","disclosure":"structural","program_definition_cid":"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","parameter_values_cid":"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","compiled_plan_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","logical_map_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","steps":[{"step_id":"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8","key":{"version":"actql-logical-step-key/0.1","compiled_plan_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","stage_ordinal":0,"occurrence":{"kind":"operation","operation_ordinal":0},"self_cid":"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8"},"operator":"filter","input_ports":["sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"],"output_ports":["sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"],"meaning":{"kind":"filter","predicate":{"state":"projected","root":0,"nodes":[{"form":"operation","operator":"gt","children":[1,2],"type":{"projection":"shape_and_nullability","kind":"boolean","nullable":false}},{"form":"field","scope":"fields","name":"id","type":{"projection":"shape_and_nullability","kind":"number","nullable":false}},{"form":"literal_redacted","type":{"projection":"shape_and_nullability","kind":"number","nullable":false}}]}}}],"self_cid":"sha256:2b741894a384a3376f73ccc64cb1649a412b47000874881860511f3ae119a682"}

///|
let validator_explanation_projected : String =
  #|{"version":"actql-run-explanation-view/0.1","run_ref":{"namespaceId":"original-namespace","authorityScopeCid":"sha256:0000000000000000000000000000000000000000000000000000000000000000","runDefinitionCid":"sha256:1111111111111111111111111111111111111111111111111111111111111111"},"explanation":{"state":"projected","facts":{"version":"actql-explanation-facts/0.1","disclosure":"structural","program_definition_cid":"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","parameter_values_cid":"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","compiled_plan_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","logical_map_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","steps":[{"step_id":"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8","key":{"version":"actql-logical-step-key/0.1","compiled_plan_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","stage_ordinal":0,"occurrence":{"kind":"operation","operation_ordinal":0},"self_cid":"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8"},"operator":"filter","input_ports":["sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"],"output_ports":["sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"],"meaning":{"kind":"filter","predicate":{"state":"projected","root":0,"nodes":[{"form":"operation","operator":"gt","children":[1,2],"type":{"projection":"shape_and_nullability","kind":"boolean","nullable":false}},{"form":"field","scope":"fields","name":"id","type":{"projection":"shape_and_nullability","kind":"number","nullable":false}},{"form":"literal_redacted","type":{"projection":"shape_and_nullability","kind":"number","nullable":false}}]}}}],"self_cid":"sha256:2b741894a384a3376f73ccc64cb1649a412b47000874881860511f3ae119a682"}}}

///|
let validator_explanation_not_projected : String =
  #|{"version":"actql-run-explanation-view/0.1","run_ref":{"namespaceId":"original-namespace","authorityScopeCid":"sha256:0000000000000000000000000000000000000000000000000000000000000000","runDefinitionCid":"sha256:1111111111111111111111111111111111111111111111111111111111111111"},"explanation":{"state":"not_projected","reason":"not_retained"}}

///|
test "explanation validator construction covers body sealed facts and both read branches" {
  for
    (name, complete, wire) in [
      ("explanation_facts", false, validator_explanation_body),
      ("explanation_facts", true, validator_explanation_facts),
      ("run_explanation_view", true, validator_explanation_projected),
      ("run_explanation_view", true, validator_explanation_not_projected),
    ] {
    let value = parse_contract_wire(wire, 1000000, 100000, 100).unwrap()
    let quote = cold_static_plan_validation_construction(
      name, complete, 100000, 1000000L, 1000000, 100000, 100,
    ).unwrap()
    let (peak, accepted) = validator_observed_pending(name, complete, value)
    assert_true(accepted, msg=name)
    assert_true(peak.to_int64() <= quote.pending_reference_items, msg=name)
    // The structural schemas have no unique-array constructor. Neither large
    // cardinality allowances nor user spelling invent owned text or seen sets.
    assert_eq(quote.unique_reference_items, 0L)
    assert_eq(quote.owned_utf16_units, 0L)
    assert_eq(quote.owned_wire_bytes, 0L)
  }
  assert_true(
    cold_static_plan_validation_construction(
      "run_explanation_view", false, 0, 0L, 0, 0, 0,
    )
    is None,
  )
}

///|
let validator_explanation_private_literal : String =
  #|{"version":"actql-explanation-facts/0.1","disclosure":"structural","program_definition_cid":"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","parameter_values_cid":"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","compiled_plan_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","logical_map_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","steps":[{"step_id":"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8","key":{"version":"actql-logical-step-key/0.1","compiled_plan_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","stage_ordinal":0,"occurrence":{"kind":"operation","operation_ordinal":0},"self_cid":"sha256:eead8c6ef087723003d9b8913cdec681f4cf1f4b748e9c3911af71ea51fbcbf8"},"operator":"filter","input_ports":["sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"],"output_ports":["sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"],"meaning":{"kind":"filter","predicate":{"state":"projected","root":0,"nodes":[{"form":"operation","operator":"gt","children":[1,2],"type":{"projection":"shape_and_nullability","kind":"boolean","nullable":false}},{"form":"field","scope":"fields","name":"id","type":{"projection":"shape_and_nullability","kind":"number","nullable":false}},{"form":"literal_redacted","type":{"projection":"shape_and_nullability","kind":"number","nullable":false},"value":"private"}]}}}],"self_cid":"sha256:2b741894a384a3376f73ccc64cb1649a412b47000874881860511f3ae119a682"}

///|
test "explanation validator construction stays bounded on wide facts and refuses raw disclosure" {
  let narrow = cold_static_plan_validation_construction(
    "explanation_facts", true, 1, 1L, 1, 1, 1,
  ).unwrap()
  let wide = cold_static_plan_validation_construction(
    "explanation_facts", true, 100000, 1000000L, 1000000, 100000, 100,
  ).unwrap()
  assert_eq(narrow.owner, wide.owner)
  let value = parse_contract_wire(
    validator_explanation_facts, 1000000, 100000, 100,
  ).unwrap()
  guard @json.object_field(value, "steps") is Some(@json.Array(steps)) else {
    fail("original steps")
  }
  let step = @json.array_at(steps, 0).unwrap()
  let step_wire = @json.stringify_value(step, 1000000, 100000, 100) catch {
    _ => fail("fixture encoding")
  }
  let repeated_steps = parse_contract_wire(
    "[" + Array::make(64, step_wire).join(",") + "]",
    1000000,
    100000,
    100,
  ).unwrap()
  let repeated = @json.object_with_replaced_fields(value, [
    ("steps", repeated_steps),
  ]).unwrap()
  let (peak, accepted) = validator_observed_pending(
    "explanation_facts", true, repeated,
  )
  assert_true(accepted)
  assert_true(peak.to_int64() <= wide.pending_reference_items)
  let bad = parse_contract_wire(
    validator_explanation_private_literal, 1000000, 100000, 100,
  ).unwrap()
  let (peak, accepted) = validator_observed_pending(
    "explanation_facts", true, bad,
  )
  assert_false(accepted)
  assert_true(peak.to_int64() <= wide.pending_reference_items)
}

///|
test "explanation namespace validation preserves ASCII exclusions and Unicode scalar limits" {
  for code in 0..<128 {
    let text = String::from_array([code.to_char().unwrap()])
    let allowed = code >= 32 && code != 127
    assert_eq(protocol_string_pattern(text, 9), allowed)
    assert_eq(protocol_string_pattern("😀" + text + "日本語", 9), allowed)
  }
  assert_false(protocol_string_pattern("", 9))
  let original = parse_contract_wire(
    validator_explanation_not_projected, 1000000, 100000, 100,
  ).unwrap()
  let original_ref = @json.object_field(original, "run_ref").unwrap()
  let quote = cold_static_plan_validation_construction(
    "run_explanation_view", true, 100000, 1000000L, 1000000, 100000, 100,
  ).unwrap()
  for
    (name, allowed) in [
      ("😀".repeat(256), true),
      ("😀".repeat(257), false),
      ("日本語 é", true),
      ("line\nfeed", false),
      ("delete\u{7f}", false),
      ("", false),
    ] {
    let without_namespace = @json.object_without_field(
      original_ref, "namespaceId",
    ).unwrap()
    let changed_ref = @json.object_with_string_field(
      without_namespace, "namespaceId", name,
    ).unwrap()
    let changed = @json.object_with_replaced_fields(original, [
      ("run_ref", changed_ref),
    ]).unwrap()
    let (peak, accepted) = validator_observed_pending(
      "run_explanation_view", true, changed,
    )
    assert_eq(accepted, allowed)
    assert_true(peak.to_int64() <= quote.pending_reference_items)
  }
}
