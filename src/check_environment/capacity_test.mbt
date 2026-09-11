///|
fn capacity_body() -> String {
  "{\"max_aggregate_array_items\":1,\"max_artifact_bytes\":1,\"max_artifact_rows\":1,\"max_effect_items\":1,\"max_graph_input_edges\":1,\"max_graph_input_nodes\":1,\"max_graph_output_rows\":1,\"max_graph_paths\":1,\"max_infer_items\":1,\"max_model_input_tokens_per_item\":1,\"max_model_request_bytes_per_item\":1,\"max_model_total_duration_ms\":1,\"max_nested_value_bytes\":1,\"max_nested_value_depth\":1,\"max_relation_output_rows\":1,\"max_temporal_matches_per_key\":1,\"max_temporal_output_rows\":1,\"version\":\"actql-capacity-host-policy/0.1\"}"
}

///|
fn capacity_wire(profile : String) -> WireEnvironment {
  let (body, expected) = wire(profile, "[]")
  read(@utf8.encode(body), expected, caps()).unwrap()
}

///|
test "capacity component retains environment and its independent policy identity" {
  let environment = capacity_wire("{\"capacity\":" + capacity_body() + "}")
  let limits : @policy.Limits = {
    max_bytes: 10000,
    max_nodes: 100,
    max_depth: 4,
  }
  let checked = read_capacity(environment, limits).unwrap()
  assert_true(physical_equal(capacity_environment(checked), environment))
  let policy = capacity_policy(checked)
  assert_eq(
    @policy.cid(policy),
    "sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63",
  )
  assert_true(@policy.cid(policy) != cid(environment))
  assert_eq(
    @policy.ceiling_value(
      @policy.ceiling(policy, "max_relation_output_rows").unwrap(),
    ),
    1L,
  )
  let other = capacity_wire("{\"capacity\":" + capacity_body() + "}")
  assert_false(physical_equal(capacity_environment(checked), other))
  assert_true(
    read_capacity(environment, {
      max_bytes: capacity_body().length(),
      max_nodes: 19,
      max_depth: 1,
    })
    is Ok(_),
  )
  for
    limited in [
      { ..limits, max_bytes: capacity_body().length() - 1, },
      { ..limits, max_nodes: 18, },
      { ..limits, max_depth: 0, },
    ] {
    assert_true(
      read_capacity(environment, limited) is Err(CapacityIssue::BudgetExceeded),
    )
  }
  assert_true(
    read_capacity(environment, { ..limits, max_bytes: -1, })
    is Err(InvalidLimits),
  )
}

///|
test "missing capacity has no default and present invalid capacity cannot be ignored" {
  let limits : @policy.Limits = {
    max_bytes: 10000,
    max_nodes: 100,
    max_depth: 4,
  }
  assert_true(
    read_capacity(capacity_wire("{}"), limits) is Err(MissingCapacity),
  )
  for value in ["null", "[]", "1"] {
    assert_true(
      read_capacity(capacity_wire("{\"capacity\":" + value + "}"), limits)
      is Err(InvalidComponent),
    )
  }
  assert_true(
    read_capacity(capacity_wire("{\"capacity\":{}}"), limits) is Err(Policy(_)),
  )
  let malformed = capacity_body().replace(
    old="\"max_artifact_bytes\":1",
    new="\"max_artifact_bytes\":0",
  )
  assert_true(
    read_capacity(capacity_wire("{\"capacity\":" + malformed + "}"), limits)
    is Err(Policy(@policy.InvalidCeiling("max_artifact_bytes"))),
  )
}
