///|
// The original Core task chain plus the independently observed installed
// execution overlap. This test-only capacity token models bytes, not Host
// backing, Account permission, publication or physical stop acknowledgement.
test "set expression keeps original tasks beside measured installed execution overlap" {
  let prepared = set_output_expression_prepared()
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "set-first-task",
  ).unwrap()
  guard select_installed_source_input(prepared, request, 0, 0).unwrap()
    is @sourceviews.WholeInputRoute(original) else {
    fail("the same set expression selects Whole Source")
  }
  let policy = installed_row_input_policy(10000, 10000000, 110101, 2, 10000)
  let source = prepare_installed_catalog_whole_source_capacity(
    prepared, original, contracts, policy,
  ).unwrap()
  let plan = prepare_installed_managed_whole_source_plan(
    prepared,
    request,
    source,
    10000000L,
    239908928L,
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    retained_output=false,
    provider_factory=_ => [],
    runtime_admission=true,
  ).unwrap()
  let limits = {
    ..plan.limits,
    retained_bytes: client_local_retained_byte_ceiling(),
    execution_bytes: client_local_execution_byte_ceiling(),
  }
  let ledger = @resources.create_ledger(limits).unwrap()
  let overlap = @resources.reserve_capacity(ledger, 0L, 21923116L).unwrap()
  let rows = @row_source_host.start_accounted_row_input_acquisition(
    source.acquisition,
    source.provider,
    "set-original-source",
    _ => true,
    ledger,
    10000000L,
    239908928L,
  ).unwrap()
  @row_source_host.begin_row_run_with_page_limits(rows, policy.page, 10000).unwrap()
  let wire = @utf8.encode(
    "[{\"id\":3,\"amount\":30},{\"id\":1,\"amount\":null},{\"id\":2,\"amount\":20},{\"id\":3,\"amount\":30}]",
  )
  let charged = @row_source_host.charge_row_run_page(rows, wire).unwrap()
  assert_eq(
    @row_source_host.accept_charged_row_run_page(rows, charged, wire).unwrap(),
    4,
  )
  @row_source_host.finish_row_run(rows).unwrap()
  @row_source_host.begin_row_capture(rows).unwrap()
  let mut captured = false
  for _ in 0..<10000 {
    if @row_source_host.advance_row_capture(rows, 256).unwrap().0 {
      captured = true
      break
    }
  }
  assert_true(captured)
  let capture = @row_source_host.capture_row_run(rows).unwrap()
  let dag = @strategy.open_source_inputs_dag(
    plan.graph,
    [@row_source_host.row_capture_source(capture).unwrap()],
    ledger,
  ).unwrap()
  @row_source_host.check_row_input_compute_binding(capture, dag, 0).unwrap()
  let host = bind_client_local_configuration(
    dag,
    plan.configuration,
    1L,
    1L,
    1L,
    1L,
  ).unwrap()
  @host_driver.refresh_compute_host(@builtin.configured_host_runtime(host)).unwrap()
  let installed = @builtin.configured_local_module(
    @builtin.configured_host_modules(host),
  ).unwrap()
  let count = @strategy.graph_task_count(plan.graph)
  let tasks : Array[LocalValuesTaskExecution?] = Array::make(count, None)
  let output_live = Ref(true)
  let mut failure : @local_driver.LocalDispatchIssue? = None
  for _ in 0..<count {
    let task = @strategy.next_captured_task(dag).unwrap()
    let producers = @strategy.captured_next_managed_producers(dag)
    let available = producers.map(producer => {
      if producer == -1 {
        @local_driver.local_managed_supplied_relation_input()
      } else {
        @local_driver.local_managed_relation_output(
          tasks[producer].unwrap().completed.unwrap(),
        )
      }
    })
    let dispatch = @local_driver.prepare_local_managed_dispatch_with_outputs(
        installed,
        available,
        @strategy.captured_next_managed_obligations(dag, 100000).unwrap(),
        0L,
      )
      .unwrap()
      .unwrap()
    @strategy.select_captured_managed_registration(
      dag,
      task,
      @local_driver.local_dispatch_registration(installed),
    ).unwrap()
    let before = @resources.ledger_usage(ledger)
    println(
      "set-chain-start " +
      @debug.to_string(
        (
          task,
          before.reserved_execution_bytes,
          @local_driver.local_managed_dispatch_site_capacity(dispatch).unwrap(),
        ),
      ),
    )
    let operations = match
      @local_driver.start_local_managed_dispatch_node(dispatch) {
      Ok(value) => value
      Err(issue) => {
        if issue is @local_driver.Execution(Physical(physical)) {
          println(
            "set-chain-start-refused " + @debug.to_string((task, physical)),
          )
        }
        failure = Some(issue)
        break
      }
    }
    let current : LocalValuesTaskExecution = {
      operations,
      settled: false,
      completed: None,
    }
    tasks[task] = Some(current)
    for transfer in operations.inputs {
      let input = @execution.managed_producer_read_input_index(transfer.input)
      let producer = tasks[producers[input]].unwrap()
      let original_output = producer.completed.unwrap()
      assert_true(
        @execution.managed_producer_read_matches_reference(
          transfer.input,
          @execution.managed_completed_reference(original_output),
        ),
      )
      for
        row in 0..<@execution.managed_completed_output_row_count(
          original_output,
        ) {
        (transfer.append)((producer.operations.output_row)(row).unwrap()).unwrap()
      }
      (transfer.finish)().unwrap()
    }
    (operations.execute)().unwrap()
    (operations.prepare_finalization)(task, operations.storage_bytes, () => {
      output_live.val
    }).unwrap()
    let mut finalized = false
    for _ in 0..<10000 {
      if (operations.advance_finalization)(256).unwrap().complete {
        finalized = true
        break
      }
    }
    assert_true(finalized)
    (operations.settle)().unwrap()
    current.settled = true
    current.completed = Some(
      (operations.complete)(task, operations.storage_bytes, () => {
        output_live.val
      }).unwrap(),
    )
  }
  if failure is None {
    let result = tasks[@strategy.graph_result_task(plan.graph, 0).unwrap()].unwrap()
    assert_eq(
      @execution.managed_completed_output_row_count(result.completed.unwrap()),
      2,
    )
    for row in 0..<2 {
      assert_eq(@json.parse((result.operations.output_row)(row).unwrap()), {
        "id": 3,
      })
    }
  }
  output_live.val = false
  let mut cleaned = false
  for _ in 0..<10000 {
    if close_local_values_tasks(dag, tasks) {
      cleaned = true
      break
    }
  }
  assert_true(cleaned)
  @row_source_host.close_accounted_row_run(rows).unwrap()
  @resources.settle_capacity(ledger, overlap).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
  assert_true(failure is None)
}
