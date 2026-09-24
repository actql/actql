///|
test "standard Host prepares bounded placement for twenty real module tasks" {
  let (run, _) = captured_graph_fixture(
    linear_compute_stages=20,
    ledger_limits=Some({
      planning_work: 1000000,
      attempts: 40,
      holdings: 40,
      transfer_bytes: 3000000L,
      retained_bytes: 320000000L,
      execution_bytes: 134217728L,
    }),
  )
  let graph = @strategy.captured_dag_graph(run)
  assert_eq(@strategy.graph_task_count(graph), 21)
  let registry = search_registry()
  let host = adaptive_host(run, registry)
  let profiles : Array[@dbhost.DispatchEstimateProfile] = Array::makei(20, index => {
    local_rates: [
      {
        work_slots: [0, 1, 2, 3, 4],
        fixed_ms: Some((index + 1).to_int64()),
        per_row_ms: Some(0L),
        per_wire_byte_ms: Some(0L),
        per_pair_ms: Some(0L),
      },
    ],
    native_rates: [
      {
        work_slots: [0, 1, 2, 3, 4, 5, 6, 7],
        fixed_ms: Some((index + 2).to_int64()),
        per_row_ms: Some(0L),
        per_wire_byte_ms: Some(0L),
        per_pair_ms: Some(0L),
      },
    ],
    native_capacity: {
      transfer_bytes: 100000L,
      retained_bytes: 100L,
      execution_bytes: 134217728L,
    },
    output_rows_per_mille: Some(1000),
  })
  @dbhost.configure_dispatch_estimates(host, profiles, {
    max_offers: 40,
    max_strategies: 64,
    max_work: 1000000,
    max_revisions: 1,
  }).unwrap()
  let search_clock = @bench.monotonic_clock_start()
  assert_true(@dbhost.prepare_dispatch_policy_choice(host).unwrap())
  let search_microseconds = @bench.monotonic_clock_end(search_clock)
  let diagnostics = @dbhost.dispatch_policy_search_diagnostics(host).unwrap()
  assert_true(!diagnostics.complete)
  assert_eq(diagnostics.evaluated_assignments, 64)
  assert_eq(diagnostics.generated_prefixes, 1918)
  assert_eq(diagnostics.peak_frontier_states, 192)
  assert_eq(diagnostics.peak_index_cells, 3776)
  println("ACTQL_PLACEMENT_SEARCH " + search_microseconds.to_string())
  assert_true(@strategy.captured_dag_strategy(run) is None)
  @dbhost.commit_dispatch_offline_policy_choice(host).unwrap()
  let revision = @strategy.captured_dag_strategy(run).unwrap()
  assert_eq(
    @strategy.strategy_selection_source(revision),
    @strategy.BoundedLatency,
  )
  let explain = @strategy.explain_captured_strategy(run, 100000, 10000).unwrap()
  assert_true(explain.contains("\"bounded_frontier\""))
  assert_true(explain.contains("\"assessment_complete\":false"))
  @dbhost.stop_strategy_dispatch(host)
}
