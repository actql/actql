///|
// The existing checked two-Source fixture preserves its mapping and Plan.
// Failure happens only after both actual RowRuns have completed and entered
// this SAME physical DAG; Text-key constructor coverage is separate.
#cfg(target="js")
test "captured JOIN start refusal retires the same original Whole Sources and Ledger" {
  let plan = effect_operation_source_plan_fixture(whole_inputs=true)
  assert_eq(plan.captures.length(), 0)
  assert_eq(plan.whole_sources.length(), 2)
  assert_eq(@strategy.graph_captured_prefix(plan.graph), 0)
  let coordinates = plan.direct_occurrences.unwrap()
  assert_eq(
    @publication_host.client_direct_acquisition_occurrence_at(coordinates, 0),
    Some((0, 0, 0)),
  )
  assert_eq(
    @publication_host.client_direct_acquisition_occurrence_at(coordinates, 1),
    Some((0, 1, 0)),
  )
  let (input, initial, ledger, capacity) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial,
    input,
    capacity,
    plan.prepared,
    plan.request,
    plan,
  ).unwrap()
  assert_true(
    installed_effect_managed_sources_ledger(owner, plan.prepared, plan.request)
    is Err(ForeignOriginal),
  )
  let sources = []
  let reads = []
  let rows = []
  for occurrence in 0..<2 {
    let (declaration, source) = plan.whole_sources[occurrence].unwrap()
    assert_true(source.provider is None)
    assert_eq(
      installed_effect_managed_source_input_kind(
        owner,
        plan.prepared,
        plan.request,
        occurrence,
      ).unwrap(),
      "whole-input",
    )
    let (read, original, acquisition, selected) = begin_installed_effect_managed_whole_source_read(
      owner,
      plan.prepared,
      plan.request,
      declaration,
      occurrence,
    ).unwrap()
    assert_true(physical_equal(selected, source))
    assert_true(physical_equal(original, source.original))
    assert_true(read.requirement is None && read.acquisition is None)
    assert_true(
      begin_installed_effect_managed_whole_source_read(
        owner,
        plan.prepared,
        plan.request,
        declaration,
        occurrence,
      )
      is Err(AlreadyBound),
    )
    let run = match
      start_installed_whole_source_read_rows(
        read,
        acquisition,
        "effect-whole-" + occurrence.to_string(),
        _ => true,
        1024L,
        2048L,
      ) {
      Ok(value) => value
      Err(Acquisition(Physical(issue))) =>
        fail("WholeSource physical admission: " + @debug.to_string(issue))
      Err(Acquisition(_)) => fail("WholeSource row admission")
      Err(_) => fail("WholeSource managed read")
    }
    @row_source_host.begin_row_run_with_page_limits(
      run,
      { max_bytes: 128, max_nodes: 1000, max_depth: 20, max_rows: 3, },
      3,
    ).unwrap()
    let body = @utf8.encode("[{\"id\":3}]")
    let charge = @row_source_host.charge_row_run_page(run, body).unwrap()
    @row_source_host.accept_charged_row_run_page(run, charge, body).unwrap()
    |> ignore
    @row_source_host.finish_row_run(run).unwrap()
    @row_source_host.begin_row_capture(run).unwrap()
    let mut complete = false
    for _ in 0..<10000 {
      if @row_source_host.advance_row_capture(run, 256).unwrap().0 {
        complete = true
        break
      }
    }
    assert_true(complete)
    let capture = @row_source_host.capture_row_run(run).unwrap()
    let actual = @row_source_host.row_capture_source(capture).unwrap()
    assert_true(
      @query.captured_source_matches_input_acquisition(actual, original),
    )
    sources.push(actual)
    reads.push(read)
    rows.push(capture)
  }
  assert_true(
    physical_equal(
      installed_effect_managed_sources_ledger(
        owner,
        plan.prepared,
        plan.request,
      ).unwrap(),
      ledger,
    ),
  )
  let bound = effect_parent_bound_run(plan.prepared)
  assert_true(
    open_installed_effect_managed_host(owner, bound, [sources[1], sources[0]])
    is Err(ForeignOriginal),
  )
  let (host, captured, _) = open_installed_effect_managed_host(
      owner, bound, sources,
    )
    .unwrap()
    .unwrap()
  let dag = @strategy.captured_effect_run_dag(captured)
  assert_eq(sources.length(), 2)
  let installed = @builtin.configured_local_module(
    @builtin.configured_host_modules(host),
  ).unwrap()
  let dispatch = @local_driver.prepare_local_managed_dispatch_with_outputs(
      installed,
      [
        @local_driver.local_managed_supplied_relation_input(),
        @local_driver.local_managed_supplied_relation_input(),
      ],
      @execution.process_managed_obligations(
        @strategy.graph_task_owner(plan.graph, 0).unwrap(),
      ),
      0L,
    )
    .unwrap()
    .unwrap()
  @strategy.select_captured_managed_registration(
    dag,
    0,
    @local_driver.local_dispatch_registration(installed),
  ).unwrap()
  // Both original Sources have completed and entered this exact DAG before
  // an independent finite sibling leaves no execution room for ManagedStart.
  let before = @resources.ledger_usage(ledger)
  let remaining = @resources.ledger_limits(ledger).execution_bytes -
    before.reserved_execution_bytes
  let pressure = @resources.reserve_capacity(ledger, 0L, remaining).unwrap()
  assert_true(
    @local_driver.start_local_managed_dispatch_node(dispatch)
    is Err(Execution(Physical(ExecutionLimit))),
  )
  @strategy.stop_captured_dag(dag)
  assert_true(retire_installed_effect_captured_consumers(owner).unwrap())
  for read in reads {
    retire_installed_source_read(read).unwrap()
  }
  @resources.settle_capacity(ledger, pressure).unwrap()
  // The first original close completes; a retry adds no release receipt.
  retire_installed_managed_run(owner).unwrap()
  let closed = @resources.ledger_usage(ledger)
  assert_eq(closed.live_reservations, 0)
  assert_eq(closed.reserved_retention_bytes, 0L)
  assert_eq(closed.reserved_execution_bytes, 0L)
  retire_installed_managed_run(owner).unwrap()
}
