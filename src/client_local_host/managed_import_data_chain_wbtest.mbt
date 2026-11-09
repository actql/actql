///|
// Original checked Row Source and Local Task owners. The byte-only pressure
// reproduces a fixed ordinary Host prefix, not an execution/permission grant.
priv enum ManagedImportDataCase {
  Complete
  RefuseImport
  CancelImport
} derive(Eq)

///|
fn managed_import_data_chain(mode : ManagedImportDataCase) -> Unit raise {
  let prepared = before_limit_standard_prepared(
    "WITH paired AS (WITH seed AS (FROM records |> SELECT amount, id) SELECT l.id AS amount, l.amount AS id FROM seed AS l JOIN seed AS r ON l.id = r.id ORDER BY amount + 1) FROM paired |> RESULT copied_rows",
    @frontend.Text,
  )
  let publication_policy = @publication_host.prepared_client_publication_data_policy_cid(
    prepared,
  )
  let graph = @publication_host.prepared_client_graph(prepared)
  assert_eq(@strategy.graph_task_count(graph), 8)
  assert_eq(@strategy.graph_captured_prefix(graph), 1)
  assert_eq(@publication_host.prepared_client_acquisition_count(prepared), 1)
  assert_eq(@strategy.graph_result_count(graph), 1)
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "cte-join-alias-original",
  ).unwrap()
  guard select_installed_source_input(prepared, request, 0, 0).unwrap()
    is @sourceviews.WholeInputRoute(original) else {
    fail("the original request selects Whole Source")
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
  let rows = @row_source_host.start_accounted_row_input_acquisition(
    source.acquisition,
    source.provider,
    "cte-join-alias-source",
    _ => true,
    ledger,
    10000000L,
    239908928L,
  ).unwrap()
  @row_source_host.begin_row_run_with_page_limits(rows, policy.page, 10000).unwrap()
  let wire = @utf8.encode("[{\"id\":2,\"amount\":10},{\"id\":1,\"amount\":20}]")
  let charged = @row_source_host.charge_row_run_page(rows, wire).unwrap()
  assert_eq(
    @row_source_host.accept_charged_row_run_page(rows, charged, wire).unwrap(),
    2,
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
  let actual_source = @row_source_host.row_capture_source(capture).unwrap()
  let source_matches = Array::makei(
    @publication_host.prepared_client_acquisition_count(prepared),
    task => {
      @publication_host.prepared_client_captured_task_source_matches(
        prepared, actual_source, task,
      )
    },
  )
  assert_eq(source_matches, [true])
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
  // Keep the original preparation and every real parent output live alongside
  // an independent workspace. The finite fixture total leaves the same startup
  // headroom as the ordinary Host, without changing its 512 MiB limits.
  let original_prior = @resources.ledger_usage(ledger).reserved_execution_bytes
  assert_true(original_prior <= 261216696L)
  let host_context = @resources.reserve_capacity(
    ledger,
    0L,
    261216696L - original_prior,
  ).unwrap()
  let count = @strategy.graph_task_count(plan.graph)
  let tasks : Array[LocalValuesTaskExecution?] = Array::make(count, None)
  let output_live = Ref(true)
  let coexistence_fits = Ref(true)
  let refused_import : Ref[@resources.CapacityReservation?] = Ref(None)
  let mut control_observed = false
  let mut failure : @local_driver.LocalDispatchIssue? = None
  let mut selection_missing = false
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
    let dispatch = match
      @local_driver.prepare_local_managed_dispatch_with_outputs(
        installed,
        available,
        @strategy.captured_next_managed_obligations(dag, 100000).unwrap(),
        0L,
      ) {
      Ok(Some(value)) => value
      Ok(None) => {
        selection_missing = true
        break
      }
      Err(issue) => {
        failure = Some(issue)
        break
      }
    }
    @strategy.select_captured_managed_registration(
      dag,
      task,
      @local_driver.local_dispatch_registration(installed),
    ).unwrap()
    let before = @resources.ledger_usage(ledger)
    let observed_prior_execution = before.reserved_execution_bytes
    coexistence_fits.val = coexistence_fits.val &&
      @local_driver.local_managed_dispatch_site_capacity(dispatch).unwrap().1 +
      observed_prior_execution <=
      client_local_execution_byte_ceiling()
    let operations = match
      @local_driver.start_local_managed_dispatch_node(dispatch) {
      Ok(value) => value
      Err(issue) => {
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
    if task == 2 {
      assert_eq(operations.inputs.length(), 2)
      assert_false(
        @execution.managed_producer_read_same_binding(
          operations.inputs[0].input,
          operations.inputs[1].input,
        ),
      )
    }
    if task == 1 && mode != Complete {
      assert_eq(operations.inputs.length(), 1)
      if mode == RefuseImport {
        // A malformed row must fail at funding BEFORE the parser can observe
        // it. The existing byte-only reservation consumes no attempt credit.
        refused_import.val = Some(
          @resources.reserve_capacity(
            ledger,
            0L,
            @resources.ledger_limits(ledger).execution_bytes -
            @resources.ledger_usage(ledger).reserved_execution_bytes,
          ).unwrap(),
        )
        let before = @resources.ledger_usage(ledger).reserved_execution_bytes
        assert_true(
          (operations.inputs[0].append)("{")
          is Err(@local_driver.Execution(Physical(ExecutionLimit))),
        )
        assert_eq(
          @resources.ledger_usage(ledger).reserved_execution_bytes,
          before,
        )
        assert_true((operations.request_cancel)())
      } else {
        assert_true((operations.request_cancel)())
        let before = @resources.ledger_usage(ledger).reserved_execution_bytes
        assert_true((operations.inputs[0].append)("{") is Err(_))
        assert_eq(
          @resources.ledger_usage(ledger).reserved_execution_bytes,
          before,
        )
      }
      assert_false(@strategy.captured_task_completed(dag, task))
      assert_true(@row_source_host.row_capture_source(capture) is Ok(_))
      control_observed = true
      break
    }
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
    match (operations.execute)() {
      Ok(_) => ()
      Err(issue) => {
        failure = Some(issue)
        break
      }
    }
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
  if mode == Complete && failure is None && !selection_missing {
    assert_eq(@strategy.graph_result_count(plan.graph), 1)
    assert_eq(@strategy.graph_result_name(plan.graph, 0), Some("copied_rows"))
    let result = tasks[@strategy.graph_result_task(plan.graph, 0).unwrap()].unwrap()
    let expected = ["{\"amount\":1,\"id\":20}", "{\"amount\":2,\"id\":10}"]
    assert_eq(
      @execution.managed_completed_output_row_count(result.completed.unwrap()),
      2,
    )
    for row in 0..<2 {
      assert_eq(
        @json.parse((result.operations.output_row)(row).unwrap()),
        @json.parse(expected[row]),
      )
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
  if refused_import.val is Some(reservation) {
    @resources.settle_capacity(ledger, reservation).unwrap()
  }
  @resources.settle_capacity(ledger, host_context).unwrap()
  @row_source_host.close_accounted_row_run(rows).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
  assert_true(mode == Complete || control_observed)
  assert_true(failure is None)
  assert_false(selection_missing)
  assert_true(coexistence_fits.val)
  // The same checked Source and alias-order Program retain their policy.
  assert_eq(
    publication_policy,
    Some(
      "sha256:0ab54a0637544a1b96c511cd698af0b3356ccbf0f3da626cfbbbd5fe17a2a589",
    ),
  )
}

///|
test "managed input DATA funds all original alias JOIN parents at bounded startup" {
  managed_import_data_chain(Complete)
}

///|
test "managed input growth refusal precedes decode and retains the original Source" {
  managed_import_data_chain(RefuseImport)
}

///|
test "cancelled managed input cannot grow or decode a later row" {
  managed_import_data_chain(CancelImport)
}
