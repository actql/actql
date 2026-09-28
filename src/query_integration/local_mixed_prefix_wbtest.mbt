///|
fn run_standard_host_selected_events_dedupe_prefix() -> Unit raise {
  let variant = "dedupe_filter"
  let (run, issuer) = captured_graph_fixture(
    local_carrier_events_chain=true,
    local_carrier_events_variant=variant,
    managed_publication=true,
    ledger_limits=Some({
      planning_work: 30000,
      attempts: 20,
      holdings: 20,
      transfer_bytes: 800000L,
      retained_bytes: 96000000L,
      execution_bytes: 402653184L,
    }),
  )
  let graph = @strategy.captured_dag_graph(run)
  assert_eq(@strategy.graph_task_count(graph), 8)
  assert_eq(@strategy.graph_task_prefix_end(graph, 2), None)
  assert_eq(@strategy.graph_task_selected_step(graph, 3), Some(1))
  assert_true(@strategy.graph_ordered_inputs_complete(graph))
  assert_true(
    @strategy.configure_captured_managed_identity_policy(
      run, true, false, false, false,
    ),
  )
  let registry = search_registry()
  let limits = dispatch_test_limits()
  let sequences = dispatch_test_generated(run)
  let capacity = @execution.generated_sequence_capacity(
    sequences[1],
    limits.local_execution,
    limits.guards,
  ).unwrap()
  let provider = @local_tea_provider.provider(
    carrier_events_storage_limits(),
    4096L,
    capacity,
  )
  let modules = @builtin.configure_compute_modules(
    @host_driver.open_dispatch_driver(run),
    registry,
    1,
    _ => @strategy.RunIssue::ForeignCandidate,
    with_local=Some(
      (
        @connector.capability_registration_at(registry, 0).unwrap(),
        {
          sequences,
          managed_providers: [provider],
          managed_capacity: limits.capacity,
          execution: limits.local_execution,
          measurement: limits.guards,
          max_work: limits.candidate_work,
        },
        _ => @strategy.RunIssue::ForeignCandidate,
        _ => @strategy.RunIssue::ForeignCandidate,
      ),
    ),
  ).unwrap()
  let installed = @builtin.configured_local_module(modules).unwrap()
  @local_driver.configure_local_retained_inputs(
    installed,
    {
      max_rows: 100,
      values: limits.local_execution.rows.input_values,
      wire: {
        ..retained_attempt_wire_limits(),
        max_bytes: 10000,
        max_nodes: 1000,
        max_depth: 20,
        max_columns: 10,
      },
      row: {
        max_bytes: 3000,
        max_nodes: 300,
        max_depth: 10,
        max_text_bytes: 3000,
      },
      max_batch_bytes: 3000,
    },
    None,
  ).unwrap()
  let values_live = Ref(true)
  let (values_ops, values) = run_local_managed_test_task(
    installed,
    run,
    1,
    [],
    [],
    1,
    values_live,
    obligations=@strategy.captured_next_managed_obligations(run, 10).unwrap(),
  )
  let values_rows = local_managed_test_rows(values_ops)
  let (bridge_ops, bridge, bridge_material) = run_local_managed_carrier_test_task(
    installed,
    run,
    2,
    [@local_driver.local_managed_relation_output(values)],
    [values_rows],
    obligations=@strategy.captured_next_managed_obligations(run, 10).unwrap(),
  )
  let (dedupe_ops, dedupe, dedupe_material) = run_local_managed_carrier_test_task(
    installed,
    run,
    3,
    [@local_driver.local_managed_carrier_output(bridge, bridge_material)],
    [],
    obligations=@strategy.captured_next_managed_obligations(run, 10).unwrap(),
  )
  let prefix_live = Ref(true)
  let (prefix_ops, prefix) = run_local_managed_test_task(
    installed,
    run,
    4,
    [],
    [],
    4,
    prefix_live,
    carrier_inputs=[(dedupe, dedupe_material)],
    obligations=@strategy.captured_next_managed_obligations(run, 10).unwrap(),
  )
  let prefix_rows = local_managed_test_rows(prefix_ops)
  assert_eq(prefix_rows.length(), 2)
  assert_true(prefix_rows[0].contains("\"event_id\":2"))
  assert_true(prefix_rows[1].contains("\"event_id\":4"))
  let filtered_live = Ref(true)
  let filtered_obligations = @strategy.captured_next_managed_obligations(
    run, 10,
  ).unwrap()
  let (filtered_ops, filtered) = run_local_managed_test_task(
    installed,
    run,
    5,
    [prefix],
    [prefix_rows],
    5,
    filtered_live,
    obligations=filtered_obligations,
  )
  assert_eq(local_managed_test_rows(filtered_ops), prefix_rows)
  let publication = @execution.managed_obligations_identities(
    filtered_obligations,
  ).filter(requirement => {
    requirement.domain == @execution.LogicalRelation &&
    requirement.subject == @execution.NamedResult
  })
  assert_eq(publication.length(), 1)
  assert_eq(
    @execution.managed_completed_identity_requirement_status(
      filtered,
      publication[0],
    ),
    Some(
      @execution.EstablishedSourceRetained(
        @execution.logical_relation_canonical_contract_cid(),
        "sha256:058f941f294541f1b2c6a5ee64dc74b06f03433d3474a9bc0a23a4c8e5ccf00b",
      ),
    ),
  )
  let first_live = Ref(true)
  let (first_ops, first) = run_local_managed_test_task(
    installed,
    run,
    6,
    [filtered],
    [prefix_rows],
    6,
    first_live,
    obligations=@strategy.captured_next_managed_obligations(run, 10).unwrap(),
  )
  let second_live = Ref(true)
  let (second_ops, second) = run_local_managed_test_task(
    installed,
    run,
    7,
    [filtered],
    [prefix_rows],
    7,
    second_live,
    obligations=@strategy.captured_next_managed_obligations(run, 10).unwrap(),
  )
  assert_eq(local_managed_test_rows(first_ops).length(), 2)
  assert_eq(local_managed_test_rows(second_ops).length(), 2)
  first_live.val = false
  @strategy.close_captured_task_output(run, 6)
  (first_ops.close)()
  (first_ops.cleanup_refresh)() |> ignore
  assert_false(@execution.managed_completed_output_available(first))
  assert_true(@execution.managed_completed_output_available(second))
  second_live.val = false
  @strategy.close_captured_task_output(run, 7)
  (second_ops.close)()
  (second_ops.cleanup_refresh)() |> ignore
  filtered_live.val = false
  @strategy.close_captured_task_output(run, 5)
  (filtered_ops.close)()
  (filtered_ops.cleanup_refresh)() |> ignore
  prefix_live.val = false
  @strategy.close_captured_task_output(run, 4)
  (prefix_ops.close)()
  (prefix_ops.cleanup_refresh)() |> ignore
  @strategy.close_captured_task_output(run, 3)
  (dedupe_ops.close)()
  (dedupe_ops.cleanup_refresh)() |> ignore
  @strategy.close_captured_task_output(run, 2)
  (bridge_ops.close)()
  (bridge_ops.cleanup_refresh)() |> ignore
  values_live.val = false
  @strategy.close_captured_task_output(run, 1)
  (values_ops.close)()
  (values_ops.cleanup_refresh)() |> ignore
  @strategy.stop_captured_dag(run)
  @strategy.close_captured_task_output(run, 0)
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)
  @mock.close_mock_query_issuer(issuer)
}

///|
test "standard Host runs selected Events dedupe into Relation consumers" {
  run_standard_host_selected_events_dedupe_prefix()
}

///|
test "standard Host runs selected Vectors normalization into Relation consumers" {
  run_standard_host_mixed_vectors_relation_path("normalize_filter")
}
