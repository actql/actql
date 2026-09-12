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
  capacity_policy? : @policy.Policy = policy(),
  profile? : String = capacity_profile(changed),
  expression? : String = "$n",
  steps? : String? = None,
  second_steps? : String? = None,
  accepted? : Bool = false,
  parameters? : String = "{\"n\":{\"type\":\"number\",\"default\":1}}",
  supplied? : @decode.Cursor? = None,
) -> (ReconciledContexts, @environment.Capacity) {
  let (stages, wiring, _, _, locals, evidence) = wired_inputs_fixture(
    true,
    capacity_policy~,
    profile~,
    expression~,
    steps~,
    second_steps~,
    accepted~,
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
  let lookup = selected_lookup_execution(result)
  assert_true(@environment.lookup_execution_policy(lookup) is None)
  assert_true(
    physical_equal(
      @environment.lookup_execution_environment(lookup),
      @environment.capacity_environment(capacity),
    ),
  )
  assert_eq(used, {
    work: before.work +
    nodes +
    1 +
    @environment.lookup_execution_usage(lookup).0,
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

///|
test "selected Host policy validates lookup execution even without source acquisitions" {
  let body = "{\"max_network_attempts_per_request\":3,\"max_request_bytes_per_attempt\":1024,\"max_total_decoded_response_bytes\":65536,\"max_total_duration_ms\":30000,\"max_total_request_bytes\":8192,\"max_total_response_bytes\":16384,\"version\":\"actql-lookup-execution-policy/0.1\"}"
  for text in [body, "null", "{}", body.replace(old="65536", new="0")] {
    let profile = capacity_profile(false).replace(
      old="}}",
      new="},\"lookup_execution\":" + text + "}",
    )
    let (context, capacity) = selected_fixture(false, profile~)
    let outcome = bind_capacity_policy(
      context,
      capacity,
      max_work=1000000,
      max_text_bytes=1000000,
      max_policy_nodes=100,
    )
    if text != body {
      assert_true(
        outcome is Err(LookupExecution(@environment.InvalidComponent)),
      )
      continue
    }
    let selected = outcome.unwrap()
    let lookup = selected_lookup_execution(selected)
    assert_eq(
      @environment.lookup_execution_cid(
        @environment.lookup_execution_policy(lookup).unwrap(),
      ),
      "sha256:82de374c9295b0ac8727956d9ec90ec9282c492d4d576505cf6c0b3e923fc209",
    )
    assert_true(
      physical_equal(
        @environment.lookup_execution_environment(lookup),
        @environment.capacity_environment(capacity),
      ),
    )
    let usage = selected_policy_usage(selected)
    assert_eq(usage.policy_nodes, 27)
    assert_true(
      bind_capacity_policy(
        context,
        capacity,
        max_work=usage.work,
        max_text_bytes=usage.text_bytes,
        max_policy_nodes=usage.policy_nodes,
      )
      is Ok(_),
    )
    for
      (work, bytes, nodes) in [
        (usage.work - 1, usage.text_bytes, usage.policy_nodes),
        (usage.work, usage.text_bytes - 1, usage.policy_nodes),
        (usage.work, usage.text_bytes, usage.policy_nodes - 1),
      ] {
      assert_true(
        bind_capacity_policy(
          context,
          capacity,
          max_work=work,
          max_text_bytes=bytes,
          max_policy_nodes=nodes,
        )
        is Err(BudgetExceeded),
      )
    }
  }
}
