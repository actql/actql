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
    } else {
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
