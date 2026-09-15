///|
test "DuckDB preparation preserves exact candidate request and is bound only once" {
  let (run, _) = captured_graph_fixture()
  let (registry, _, existing) = synchronous_test_choice(run)
  let request = @connector.fixed_compute_candidate_request(
    @connector.prepared_compute_candidate(existing),
  )
  let preparation = @duckdb_compute.prepare_duckdb_dispatch_candidate(
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    request,
    native_compile_limits(),
    { max_rows: 100, max_work: 1000, max_entries: 1000, },
    None,
    100,
  ).unwrap()
  assert_true(
    @duckdb_compute.duckdb_dispatch_preflight_work(preparation) is None,
  )
  let selected = @duckdb_compute.bind_duckdb_dispatch_candidate(preparation).unwrap()
  let candidate = @duckdb_compute.duckdb_selected_compute_candidate(selected)
  assert_true(
    physical_equal(
      @connector.fixed_compute_candidate_request(
        @connector.prepared_compute_candidate(candidate),
      ),
      request,
    ),
  )
  assert_true(
    @connector.fixed_compute_choice_payload(
      @duckdb_compute.duckdb_selected_compute_choice(selected),
      candidate,
    )
    is Some(_),
  )
  assert_true(
    @duckdb_compute.bind_duckdb_dispatch_candidate(preparation)
    is Err(NotSelected),
  )
  let pending = @duckdb_compute.prepare_duckdb_dispatch_candidate(
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    request,
    native_compile_limits(),
    { max_rows: 100, max_work: 1000, max_entries: 1000, },
    None,
    100,
  ).unwrap()
  @connector.close_capability_registry(registry)
  assert_true(
    @duckdb_compute.bind_duckdb_dispatch_candidate(pending)
    is Err(Selection(ForeignCapability(0))),
  )
}

///|
test "DuckDB join compilation exposes work before fixed-input preflight and preserves ceiling" {
  let (run, _) = captured_graph_fixture(join=true)
  captured_graph_local(run, 1).unwrap()
  captured_graph_local(run, 2).unwrap()
  let inputs = Array::makei(2, port => {
    @strategy.captured_task_input(run, 3, 100, 10000, input_index=port).unwrap()
  })
  let request = @connector.prepare_fixed_compute_request(
    inputs,
    dispatch_test_limits().capacity,
  ).unwrap()
  let registry = search_registry()
  let ledger = @strategy.captured_dag_ledger(run)
  let before = @resources.ledger_usage(ledger)
  let preparation = @duckdb_compute.prepare_duckdb_dispatch_candidate(
    registry,
    @connector.capability_registration_at(registry, 1).unwrap(),
    request,
    native_compile_limits(),
    { max_rows: 100, max_work: 1000, max_entries: 1000, },
    Some(7L),
    100,
  ).unwrap()
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_eq(
    @duckdb_compute.duckdb_dispatch_preflight_work(preparation),
    Some(1000),
  )
  @resources.charge_planning(ledger, 1000).unwrap()
  let selected = @duckdb_compute.bind_duckdb_dispatch_candidate(preparation).unwrap()
  let compute = @connector.fixed_compute_choice_payload(
    @duckdb_compute.duckdb_selected_compute_choice(selected),
    @duckdb_compute.duckdb_selected_compute_candidate(selected),
  ).unwrap()
  assert_eq(@duckdb.fixed_compute_join_output_ceiling(compute), Some(7))
  assert_false(@strategy.captured_task_completed(run, 3))
}
