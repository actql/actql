///|
fn capacity_profile(changed : Bool) -> String {
  let names = [
    "max_aggregate_array_items", "max_artifact_bytes", "max_artifact_rows", "max_effect_items",
    "max_graph_input_edges", "max_graph_input_nodes", "max_graph_output_rows", "max_graph_paths",
    "max_infer_items", "max_model_input_tokens_per_item", "max_model_request_bytes_per_item",
    "max_model_total_duration_ms", "max_nested_value_bytes", "max_nested_value_depth",
    "max_relation_output_rows", "max_temporal_matches_per_key", "max_temporal_output_rows",
  ]
  "{\"capacity\":{" +
  names
  .map(name => {
    "\"" +
    name +
    "\":" +
    (if changed && name == "max_artifact_bytes" { "2" } else { "1" })
  })
  .join(",") +
  ",\"version\":\"actql-capacity-host-policy/0.1\"}}"
}

///|
fn selected_fixture(
  changed : Bool,
  profile? : String = capacity_profile(changed),
  expression? : String = "$n",
  steps? : String? = None,
  parameters? : String = "{\"n\":{\"type\":\"number\",\"default\":1}}",
  supplied? : @decode.Cursor? = None,
) -> (ReconciledContexts, @environment.Capacity) {
  let (stages, wiring, _, _, locals, evidence) = wired_inputs_fixture(
    true,
    profile~,
    expression~,
    steps~,
    parameters~,
    supplied~,
  )
  let wired = attach_result_wiring(
    stages,
    wiring,
    max_work=1000000,
    max_text_bytes=1000000,
  ).unwrap()
  let snapshots = evidence.unwrap()
  let context = attach_reconciled_inputs(
    wired,
    snapshots,
    locals,
    max_work=1000000,
    max_text_bytes=1000000,
    max_local_input_nodes=100000,
  ).unwrap()
  let capacity = @environment.read_capacity(
    @local_inputs.program_environment(snapshots),
    { max_bytes: 10000, max_nodes: 100, max_depth: 10, },
  ).unwrap()
  (context, capacity)
}

///|
test "selected capacity policy binds exact environment and already admitted policy CID" {
  let (context, capacity) = selected_fixture(false)
  let result = bind_capacity_policy(
    context,
    capacity,
    max_work=1000000,
    max_text_bytes=1000000,
    max_policy_nodes=100,
  ).unwrap()
  assert_true(physical_equal(policy_context(result), context))
  assert_true(physical_equal(selected_capacity(result), capacity))
  let selected = stage_policy(wired_stage_contexts(reconciled_wiring(context)))
  assert_false(physical_equal(selected, @environment.capacity_policy(capacity)))
  assert_eq(
    @policy.cid(selected),
    @policy.cid(@environment.capacity_policy(capacity)),
  )
  let before = reconciled_usage(context)
  let (bytes, nodes) = @environment.capacity_usage(capacity)
  assert_eq(nodes, 19)
  let used = selected_policy_usage(result)
  assert_eq(used, {
    work: before.work + nodes + 1,
    text_bytes: before.text_bytes + bytes,
    local_input_nodes: before.local_input_nodes,
    policy_nodes: nodes,
  })
  assert_true(
    bind_capacity_policy(
      context,
      capacity,
      max_work=used.work,
      max_text_bytes=used.text_bytes,
      max_policy_nodes=used.policy_nodes,
    )
    is Ok(_),
  )
  for
    (work, text, count) in [
      (used.work - 1, used.text_bytes, used.policy_nodes),
      (used.work, used.text_bytes - 1, used.policy_nodes),
      (used.work, used.text_bytes, used.policy_nodes - 1),
    ] {
    assert_true(
      bind_capacity_policy(
        context,
        capacity,
        max_work=work,
        max_text_bytes=text,
        max_policy_nodes=count,
      )
      is Err(BudgetExceeded),
    )
  }
  assert_true(
    bind_capacity_policy(
      context,
      capacity,
      max_work=-1,
      max_text_bytes=1000000,
      max_policy_nodes=100,
    )
    is Err(InvalidLimits),
  )
  let (_, foreign) = selected_fixture(false)
  assert_true(
    bind_capacity_policy(
      context,
      foreign,
      max_work=1000000,
      max_text_bytes=1000000,
      max_policy_nodes=100,
    )
    is Err(ForeignEnvironment),
  )
  let (changed, policy) = selected_fixture(true)
  assert_true(
    bind_capacity_policy(
      changed,
      policy,
      max_work=1000000,
      max_text_bytes=1000000,
      max_policy_nodes=100,
    )
    is Err(PolicyMismatch),
  )
}
