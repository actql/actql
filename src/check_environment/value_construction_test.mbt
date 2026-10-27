///|
test "actual value-role inventory retains Command ownership partial meters and one sequential normalization workspace" {
  let bodies = value_bodies("{\"nullable\":false,\"type\":\"number\"}")
  bodies["command_input"] = @json.parse(
    "{\"additional_properties\":false,\"fields\":{\"optional\":{\"nullable\":false,\"type\":\"boolean\"}},\"required_fields\":[]}",
  )
  let policies = value_policies(bodies)
  let observed = observe_protocol_value_construction(policies)
  assert_eq((observed.envelopes, observed.command_inputs), (8, 1))
  assert_true(
    observed.work <= protocol_value_construction_inspection_bound(policies),
  )
  let (result, nodes, text, entries) = observe_protocol_value_contracts(
    policies,
    protocol_value_limits(),
  )
  let actual = result.unwrap()
  assert_true(physical_equal(value_contract_policies(actual), policies))
  assert_eq(protocol_value_usage(actual), (nodes, text, entries))
  assert_eq((nodes, text, entries), (10, 57, 8))
  let short = {
    ..protocol_value_limits(),
    contracts: { ..protocol_value_limits().contracts, max_nodes: nodes - 1, },
  }
  let (failed, n, t, e) = observe_protocol_value_contracts(policies, short)
  let prior = check_protocol_value_contracts(policies, short)
  assert_true(
    failed is Err(issue) && prior is Err(original) && issue == original,
  )
  assert_true(n > 0 && n <= nodes - 1 && t > 0 && e < 8)
  let huge = @json.parse(
    "{\"type\":\"string\",\"nullable\":false,\"enum\":[\"" +
    String::make(10000, 'x') +
    "\"]}",
  )
  let more = value_policies(bodies, unused=Some(huge))
  let extra = observe_protocol_value_construction(more)
  assert_eq(extra.envelopes, 9)
  assert_eq(extra.scratch_utf16_units, observed.scratch_utf16_units)
  assert_true(extra.retained.record_headers > observed.retained.record_headers)
  assert_true(
    observe_protocol_value_contracts(more, protocol_value_limits()).0 is Ok(_),
  )
  let (limited, n, t, e) = observe_protocol_value_contracts(policies, {
    ..protocol_value_limits(),
    max_envelopes: 0,
  })
  assert_true(limited is Err(EnvelopeLimit))
  assert_eq((n, t, e), (0, 0, 0))
}
