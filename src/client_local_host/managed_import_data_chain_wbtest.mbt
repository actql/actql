///|
// Original checked Row Source and Local Task owners. The byte-only pressure
// reproduces a fixed ordinary Host prefix, not an execution/permission grant.
priv enum ManagedImportDataCase {
  Complete
  RefuseImport
  CancelImport
  RefuseCapture
} derive(Eq)

///|
fn managed_import_data_chain(
  mode : ManagedImportDataCase,
  source_wire? : String = "[{\"id\":2,\"amount\":10},{\"id\":1,\"amount\":20}]",
  source_rows? : Int = 2,
  source_current? : (@resources.Ledger) -> Bool = _ => true,
  check_capture_workspace? : Bool = false,
  refusal_after_workspace? : Bool = false,
  two_input_task? : Int? = Some(2),
  parameter_declarations? : String? = None,
  parameter_values? : String? = None,
  query? : String = "WITH paired AS (WITH seed AS (FROM records |> SELECT amount, id) SELECT l.id AS amount, l.amount AS id FROM seed AS l JOIN seed AS r ON l.id = r.id ORDER BY amount + 1) FROM paired |> RESULT copied_rows",
  expected_tasks? : Int? = Some(8),
  result_name? : String = "copied_rows",
  expected_rows? : Array[String] = [
    "{\"amount\":1,\"id\":20}", "{\"amount\":2,\"id\":10}",
  ],
  prior_execution? : Int64 = 261216696L,
  host_preparation_execution? : Int64? = None,
  expected_policy? : String? = Some(
    "sha256:0ab54a0637544a1b96c511cd698af0b3356ccbf0f3da626cfbbbd5fe17a2a589",
  ),
  ledger_factory? : (
    @publication_host.PreparedClientProgram,
    @resources.LedgerLimits,
  ) -> @resources.Ledger = (_, limits) => {
    @resources.create_ledger(limits).unwrap()
  },
  before_append? : (
    Int,
    Int,
    Int,
    String,
    @local_driver.LocalManagedDispatchOperations[Int],
  ) -> Unit = (_, _, _, _, _) => (),
  append_observation? : () -> Bool = () => true,
  provider_factory? : (@execution.ExecutionCapacity) -> Array[
    @local.ManagedProvider,
  ] = _ => [],
  expect_budget_refusal? : Bool = false,
  input_control_task? : Int = 1,
) -> Unit raise {
  let prepared = before_limit_standard_prepared(
    query,
    @frontend.Text,
    parameter_declarations~,
    parameter_values=parameter_values.map(funded_value_cursor),
  )
  let publication_policy = @publication_host.prepared_client_publication_data_policy_cid(
    prepared,
  )
  let graph = @publication_host.prepared_client_graph(prepared)
  let task_count = @strategy.graph_task_count(graph)
  assert_true(task_count > 0 && task_count <= 100)
  if expected_tasks is Some(expected) {
    assert_eq(task_count, expected)
  }
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
    provider_factory~,
    runtime_admission=true,
  ).unwrap()
  let limits = {
    ..plan.limits,
    retained_bytes: client_local_retained_byte_ceiling(),
    execution_bytes: client_local_execution_byte_ceiling(),
  }
  let ledger = ledger_factory(prepared, limits)
  let rows = @row_source_host.start_accounted_row_input_acquisition(
    source.acquisition,
    source.provider,
    "cte-join-alias-source",
    _ => source_current(ledger),
    ledger,
    10000000L,
    239908928L,
  ).unwrap()
  @row_source_host.begin_row_run_with_page_limits(rows, policy.page, 10000).unwrap()
  let wire = @utf8.encode(source_wire)
  let charged = @row_source_host.charge_row_run_page(rows, wire).unwrap()
  assert_eq(
    @row_source_host.accept_charged_row_run_page(rows, charged, wire).unwrap(),
    source_rows,
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
  let before_capture = @resources.ledger_usage(ledger)
  let capture_result = @row_source_host.capture_row_run(rows)
  if mode == RefuseCapture {
    assert_true(
      capture_result is Err(@row_source_host.Evidence(UnverifiedTransport)),
    )
    let failed = @resources.ledger_usage(ledger)
    assert_true(failed.held_bytes > before_capture.held_bytes)
    if refusal_after_workspace {
      assert_eq(
        before_capture.reserved_execution_bytes -
        failed.reserved_execution_bytes,
        239908928L,
      )
    } else {
      assert_eq(
        failed.reserved_execution_bytes,
        before_capture.reserved_execution_bytes,
      )
    }
    // The same partially captured original owns its holding and cleanup.
    // Re-entering capture cannot create a second holding or return bytes.
    assert_true(@row_source_host.capture_row_run(rows) is Err(_))
    assert_eq(@resources.ledger_usage(ledger), failed)
    @row_source_host.close_accounted_row_run(rows).unwrap()
    assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
    assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
    return
  }
  let capture = capture_result.unwrap()
  if check_capture_workspace {
    let after = @resources.ledger_usage(ledger)
    assert_eq(
      before_capture.reserved_execution_bytes - after.reserved_execution_bytes,
      239908928L,
    )
    assert_eq(after.attempts, before_capture.attempts)
    assert_eq(after.transferred_bytes, before_capture.transferred_bytes)
    assert_eq(
      after.reserved_transfer_bytes,
      before_capture.reserved_transfer_bytes,
    )
    assert_true(after.held_bytes > before_capture.held_bytes)
    assert_true(@row_source_host.row_capture_source(capture) is Ok(_))
    let current = @resources.ledger_usage(ledger)
    assert_true(@row_source_host.capture_row_run(rows) is Err(_))
    assert_eq(@resources.ledger_usage(ledger), current)
  }
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
  assert_true(original_prior <= prior_execution)
  let host_context = @resources.reserve_capacity(
    ledger,
    0L,
    host_preparation_execution.unwrap_or(prior_execution - original_prior),
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
    if parameter_values is Some(_) || expected_tasks is None {
      let selected = plan.sequences[task]
      println(
        "acquired UNNEST task=\{task} selected-steps=\{@execution.generated_sequence_step_count(selected)}",
      )
      for slot in 0..<@execution.generated_sequence_step_count(selected) {
        let step = @execution.generated_sequence_step_index_at(selected, slot).unwrap()
        let owner = @execution.generated_sequence_owner(selected)
        let node = @lower.node_at(@lower.bound_preparation(owner), step).unwrap()
        println(
          "acquired UNNEST task=\{task} slot=\{slot} operation=\{@lower.operation(node)}",
        )
        if @execution.generated_sequence_step_at(selected, slot)
          is Some(@lower.RowStep(kernel)) &&
          @lower.kernel_count_group(kernel) is Some(group) {
          println(
            "managed COUNT slot=\{slot} keys=\{@lower.count_group_key_count(group)} aggregates=\{@lower.count_group_aggregate_count(group)}",
          )
        }
        if expected_tasks is None &&
          @execution.generated_sequence_step_count(selected) > 1 {
          let child = @execution.select_generated_sequence_step(selected, step).unwrap()
          let provider = @local.local_bounded_relation_provider(
            plan.capacity_plan.execution,
            plan.capacity_plan.measurement,
            child,
          ).unwrap()
          let quote = @local.managed_provider_capacity(provider, child).unwrap()
          println(
            "managed child slot=\{slot} R=\{quote.retained_bytes} E=\{quote.execution_bytes}",
          )
        }
      }
    }
    if expected_tasks is None {
      println(
        "managed DISTINCT task=\{task} execution=\{@local_driver.local_managed_dispatch_site_capacity(dispatch).unwrap().1} prior=\{observed_prior_execution}",
      )
    }
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
    if two_input_task is Some(original) && task == original {
      assert_eq(operations.inputs.length(), 2)
      assert_false(
        @execution.managed_producer_read_same_binding(
          operations.inputs[0].input,
          operations.inputs[1].input,
        ),
      )
    }
    if task == input_control_task && mode != Complete {
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
    // Physical task input slots and operation-local port ordinals can differ
    // when a source-free left branch precedes an independent captured Source.
    // Transfers retain physical managed-input order; supplied Source ports do
    // not allocate a managed transfer. Check each exact completed occurrence.
    let mut transfer_index = 0
    for input, producer_task in producers {
      if producer_task < 0 {
        continue
      }
      let transfer = operations.inputs[transfer_index]
      transfer_index += 1
      let producer = tasks[producer_task].unwrap()
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
        let wire = (producer.operations.output_row)(row).unwrap()
        before_append(task, input, row, wire, operations)
        let appended = (transfer.append)(wire)
        assert_true(append_observation())
        appended.unwrap()
      }
      (transfer.finish)().unwrap()
    }
    assert_eq(transfer_index, operations.inputs.length())
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
    assert_eq(@strategy.graph_result_name(plan.graph, 0), Some(result_name))
    let result = tasks[@strategy.graph_result_task(plan.graph, 0).unwrap()].unwrap()
    let expected = expected_rows
    assert_eq(
      @execution.managed_completed_output_row_count(result.completed.unwrap()),
      expected.length(),
    )
    for row in 0..<expected.length() {
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
  if expect_budget_refusal {
    assert_true(
      failure
      is Some(
        @local_driver.Execution(@strategy.Physical(@resources.ExecutionLimit))
      ),
    )
    assert_false(coexistence_fits.val)
  } else {
    assert_true(failure is None)
    assert_true(coexistence_fits.val)
  }
  assert_false(selection_missing)
  // Every route retains its SAME admitted original policy through import,
  // execution and cleanup. The original alias fixture also pins its exact CID.
  assert_eq(
    @publication_host.prepared_client_publication_data_policy_cid(prepared),
    publication_policy,
  )
  if expected_policy is Some(expected) {
    assert_eq(publication_policy, Some(expected))
  }
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

///|
test "managed DISTINCT equal aliases fit original limits with retained parents" {
  managed_import_data_chain(
    Complete,
    query="WITH seed AS (SELECT id AS x, amount AS y FROM records) SELECT DISTINCT l.x + 1 AS a, l.x + 1 AS b FROM seed AS l JOIN seed AS r ON l.x = r.x ORDER BY l.x + 1",
    expected_tasks=None,
    result_name="main",
    expected_rows=["{\"a\":2,\"b\":2}", "{\"a\":3,\"b\":3}"],
    prior_execution=261345424L,
  )
}

///|
fn managed_group_star_import(mode : ManagedImportDataCase) -> Unit raise {
  managed_import_data_chain(
    mode,
    query="SELECT * FROM records GROUP BY id, amount ORDER BY id",
    expected_tasks=None,
    result_name="main",
    source_wire="[{\"id\":3,\"amount\":30},{\"id\":1,\"amount\":null},{\"id\":2,\"amount\":20},{\"id\":3,\"amount\":30}]",
    source_rows=4,
    two_input_task=None,
    expected_rows=[
      "{\"amount\":null,\"id\":1}", "{\"amount\":20,\"id\":2}", "{\"amount\":30,\"id\":3}",
    ],
    prior_execution=259702694L,
    expected_policy=None,
  )
}

///|
test "unmetered grouped task funds original import independently of output retention" {
  managed_group_star_import(Complete)
}

///|
test "unmetered grouped import refusal precedes decoding and retains its original Source" {
  managed_group_star_import(RefuseImport)
}

///|
test "cancelled unmetered grouped import cannot grow or decode a later row" {
  managed_group_star_import(CancelImport)
}

///|
fn managed_group_star_count_import(mode : ManagedImportDataCase) -> Unit raise {
  managed_import_data_chain(
    mode,
    query="SELECT *, COUNT(*) AS n FROM records GROUP BY id, amount ORDER BY id",
    expected_tasks=None,
    result_name="main",
    source_wire="[{\"id\":3,\"amount\":30},{\"id\":1,\"amount\":null},{\"id\":2,\"amount\":20},{\"id\":3,\"amount\":30}]",
    source_rows=4,
    two_input_task=None,
    expected_rows=[
      "{\"amount\":null,\"id\":1,\"n\":1}", "{\"amount\":20,\"id\":2,\"n\":1}", "{\"amount\":30,\"id\":3,\"n\":2}",
    ],
    prior_execution=259814088L,
    expected_policy=None,
  )
}

///|
test "grouped scalar count borrows original input with retained parents and complete output" {
  managed_group_star_count_import(Complete)
}

///|
test "grouped scalar count import refusal precedes decode and preserves original Source" {
  managed_group_star_count_import(RefuseImport)
}

///|
test "cancelled grouped scalar count cannot grow or decode later input" {
  managed_group_star_count_import(CancelImport)
}

///|
test "captured Whole Source returns completed transport scratch before its CTE consumers" {
  managed_import_data_chain(
    Complete,
    query="WITH chosen AS (SELECT id, amount FROM records) SELECT *, COUNT(*) AS n FROM chosen GROUP BY amount, id ORDER BY id",
    expected_tasks=None,
    result_name="main",
    source_wire="[{\"id\":3,\"amount\":30},{\"id\":1,\"amount\":null},{\"id\":2,\"amount\":20},{\"id\":3,\"amount\":30}]",
    source_rows=4,
    two_input_task=None,
    expected_rows=[
      "{\"amount\":null,\"id\":1,\"n\":1}", "{\"amount\":20,\"id\":2,\"n\":1}", "{\"amount\":30,\"id\":3,\"n\":2}",
    ],
    // Same observed non-Row preparation remains alongside the actual RowRun.
    // Unlike a fixed total floor, it cannot refill returned transport scratch.
    host_preparation_execution=Some(19950040L),
    check_capture_workspace=true,
    expected_policy=None,
  )
}

///|
test "captured input current refusal keeps original holding and scratch until cleanup" {
  managed_import_data_chain(RefuseCapture, source_current=ledger => {
    @resources.ledger_usage(ledger).held_bytes == 0L
  })
}

///|
test "post-return current refusal cannot restore workspace or recapture the original input" {
  managed_import_data_chain(
    RefuseCapture,
    source_current=ledger => {
      @resources.ledger_usage(ledger).reserved_execution_bytes >= 239908928L
    },
    refusal_after_workspace=true,
  )
}

///|
fn managed_group_direct_count_import(
  mode : ManagedImportDataCase,
) -> Unit raise {
  managed_import_data_chain(
    mode,
    query="SELECT *, COUNT(amount) AS n FROM records GROUP BY id, amount ORDER BY id",
    expected_tasks=None,
    result_name="main",
    source_wire="[{\"id\":3,\"amount\":30},{\"id\":1,\"amount\":null},{\"id\":2,\"amount\":20},{\"id\":3,\"amount\":30}]",
    source_rows=4,
    two_input_task=None,
    expected_rows=[
      "{\"amount\":null,\"id\":1,\"n\":0}", "{\"amount\":20,\"id\":2,\"n\":1}", "{\"amount\":30,\"id\":3,\"n\":2}",
    ],
    prior_execution=259814088L,
    expected_policy=None,
  )
}

///|
test "direct field count borrows nullable original input with retained parents" {
  managed_group_direct_count_import(Complete)
}

///|
test "direct field count import refusal precedes decoding on the original Source" {
  managed_group_direct_count_import(RefuseImport)
}

///|
test "cancelled direct field count cannot grow or decode its next input" {
  managed_group_direct_count_import(CancelImport)
}

///|
fn managed_correlated_unnest_import(mode : ManagedImportDataCase) -> Unit raise {
  managed_import_data_chain(
    mode,
    query="SELECT r.id, element, position FROM records r CROSS JOIN UNNEST(@items) element WITH OFFSET position ORDER BY r.id, position",
    parameter_declarations=Some(
      "{\"items\":{\"type\":\"array\",\"nullable\":true,\"max_items\":3,\"items\":{\"type\":\"number\",\"nullable\":true}}}",
    ),
    parameter_values=Some("{\"items\":[2,null,2]}"),
    expected_tasks=None,
    result_name="main",
    source_wire="[{\"id\":2,\"amount\":20},{\"id\":1,\"amount\":null}]",
    source_rows=2,
    two_input_task=None,
    expected_rows=[
      "{\"id\":1,\"element\":2,\"position\":0}", "{\"id\":1,\"element\":null,\"position\":1}",
      "{\"id\":1,\"element\":2,\"position\":2}", "{\"id\":2,\"element\":2,\"position\":0}",
      "{\"id\":2,\"element\":null,\"position\":1}", "{\"id\":2,\"element\":2,\"position\":2}",
    ],
    prior_execution=21170378L,
    expected_policy=None,
  )
}

///|
test "acquired correlated UNNEST keeps original Source parameter scope and all parent outputs" {
  managed_correlated_unnest_import(Complete)
}

///|
test "acquired correlated UNNEST refuses import growth before original row decode" {
  managed_correlated_unnest_import(RefuseImport)
}

///|
test "acquired correlated UNNEST cancellation retains original Source and parents" {
  managed_correlated_unnest_import(CancelImport)
}

///|
test "runtime optional estimate cannot start an injected over-budget provider" {
  let starts = Ref(0)
  let currents = Ref(0)
  managed_import_data_chain(
    Complete,
    expected_tasks=None,
    expected_policy=None,
    prior_execution=21170378L,
    source_current=_ => {
      currents.val += 1
      true
    },
    expect_budget_refusal=true,
    provider_factory=_ => {
      [
        @local.managed_provider(
          _ => true,
          _ => @execution.execution_capacity(0L, 733600000L),
          (_, _, _, _, _) => {
            starts.val += 1
            Err(@connector.InvalidLimits)
          },
        ),
      ]
    },
  )
  assert_true(currents.val > 0)
  assert_eq(starts.val, 0)
}

///|
fn managed_source_free_expanded_import(
  mode : ManagedImportDataCase,
) -> Unit raise {
  managed_import_data_chain(
    mode,
    input_control_task=2,
    query="SELECT p.id, element, position FROM UNNEST(@parents) p CROSS JOIN UNNEST(p.items) element WITH OFFSET position CROSS JOIN records r MAX_OUTPUT_ROWS 10 ORDER BY p.id, position",
    parameter_declarations=Some(
      "{\"parents\":{\"type\":\"array\",\"max_items\":4,\"items\":{\"type\":\"object\",\"fields\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"items\":{\"type\":\"array\",\"nullable\":true,\"max_items\":3,\"items\":{\"type\":\"number\",\"nullable\":true}}}}}}",
    ),
    parameter_values=Some(
      "{\"parents\":[{\"id\":2,\"items\":[2,null,2]},{\"id\":1,\"items\":[1]},{\"id\":3,\"items\":[]},{\"id\":4,\"items\":null}]}",
    ),
    source_wire="[{\"id\":1,\"amount\":10},{\"id\":2,\"amount\":20}]",
    source_rows=2,
    expected_tasks=None,
    result_name="main",
    two_input_task=None,
    expected_rows=[
      "{\"id\":1,\"element\":1,\"position\":0}", "{\"id\":1,\"element\":1,\"position\":0}",
      "{\"id\":2,\"element\":2,\"position\":0}", "{\"id\":2,\"element\":2,\"position\":0}",
      "{\"id\":2,\"element\":null,\"position\":1}", "{\"id\":2,\"element\":null,\"position\":1}",
      "{\"id\":2,\"element\":2,\"position\":2}", "{\"id\":2,\"element\":2,\"position\":2}",
    ],
    prior_execution=21170378L,
    expected_policy=None,
  )
}

///|
test "source-free expanded parent and acquired right execute on the original finite Ledger" {
  managed_source_free_expanded_import(Complete)
}

///|
test "expanded left import refusal precedes decoding with its independent Source retained" {
  managed_source_free_expanded_import(RefuseImport)
}

///|
test "cancelled expanded left import cannot grow or decode a later original row" {
  managed_source_free_expanded_import(CancelImport)
}

///|
fn managed_joined_object_import(mode : ManagedImportDataCase) -> Unit raise {
  managed_import_data_chain(
    mode,
    input_control_task=7,
    query="WITH parents AS (FROM UNNEST(@parents) p |> SELECT id, items), expanded AS (FROM parents p |> JOIN records r ON p.id = r.id MAX_OUTPUT_ROWS 4 |> CROSS JOIN UNNEST(p.items) e WITH OFFSET position |> SELECT p.id, e.*, position |> ORDER BY p.id, position) FROM expanded |> RESULT answer",
    parameter_declarations=Some(
      "{\"parents\":{\"type\":\"array\",\"max_items\":4,\"items\":{\"type\":\"object\",\"fields\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"items\":{\"type\":\"array\",\"nullable\":true,\"max_items\":3,\"items\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"code\":{\"type\":\"number\",\"nullable\":false},\"label\":{\"type\":\"string\",\"nullable\":true}}}}}}}}",
    ),
    parameter_values=Some(
      "{\"parents\":[{\"id\":2,\"items\":[{\"code\":20,\"label\":null},null,{\"code\":20,\"label\":null}]},{\"id\":1,\"items\":[{\"code\":10,\"label\":\"a\"}]},{\"id\":3,\"items\":[]},{\"id\":4,\"items\":null}]}",
    ),
    source_wire="[{\"id\":2,\"amount\":null},{\"id\":1,\"amount\":10}]",
    source_rows=2,
    expected_tasks=None,
    result_name="answer",
    two_input_task=None,
    expected_rows=[
      "{\"id\":1,\"code\":10,\"label\":\"a\",\"position\":0}", "{\"id\":2,\"code\":20,\"label\":null,\"position\":0}",
      "{\"id\":2,\"code\":null,\"label\":null,\"position\":1}", "{\"id\":2,\"code\":20,\"label\":null,\"position\":2}",
    ],
    prior_execution=26641742L,
    expected_policy=None,
  )
}

///|
test "joined object UNNEST star preserves its acquired original task budget" {
  managed_joined_object_import(Complete)
}

///|
test "joined recursive carried data refuses import before decoding on the same Source" {
  managed_joined_object_import(RefuseImport)
}

///|
test "cancelled joined recursive data cannot grow or decode a later original row" {
  managed_joined_object_import(CancelImport)
}

///|
test "coalesced USING target keeps original right and left values within the same Ledger" {
  managed_import_data_chain(
    Complete,
    query="FROM records AS l |> RIGHT JOIN records AS r USING (id) MAX_OUTPUT_ROWS 10 |> SET id = -id |> SELECT id AS `current`, l.id AS left_original, r.id AS right_original |> ORDER BY right_original",
    source_wire="[{\"id\":3,\"amount\":30},{\"id\":1,\"amount\":null},{\"id\":2,\"amount\":20},{\"id\":3,\"amount\":30}]",
    source_rows=4,
    expected_tasks=None,
    two_input_task=None,
    result_name="main",
    expected_rows=[
      "{\"current\":-1,\"left_original\":1,\"right_original\":1}", "{\"current\":-2,\"left_original\":2,\"right_original\":2}",
      "{\"current\":-3,\"left_original\":3,\"right_original\":3}", "{\"current\":-3,\"left_original\":3,\"right_original\":3}",
      "{\"current\":-3,\"left_original\":3,\"right_original\":3}", "{\"current\":-3,\"left_original\":3,\"right_original\":3}",
    ],
    prior_execution=20770160L,
    expected_policy=None,
  )
}

///|
test "coalesced USING import refusal precedes decode and preserves the same Source" {
  managed_import_data_chain(
    RefuseImport,
    input_control_task=1,
    query="FROM records AS l |> RIGHT JOIN records AS r USING (id) MAX_OUTPUT_ROWS 10 |> SET id = -id |> SELECT id AS `current`, l.id AS left_original, r.id AS right_original |> ORDER BY right_original",
    source_wire="[{\"id\":3,\"amount\":30},{\"id\":1,\"amount\":null},{\"id\":2,\"amount\":20},{\"id\":3,\"amount\":30}]",
    source_rows=4,
    expected_tasks=None,
    two_input_task=None,
    result_name="main",
    expected_rows=[
      "{\"current\":-1,\"left_original\":1,\"right_original\":1}", "{\"current\":-2,\"left_original\":2,\"right_original\":2}",
      "{\"current\":-3,\"left_original\":3,\"right_original\":3}", "{\"current\":-3,\"left_original\":3,\"right_original\":3}",
      "{\"current\":-3,\"left_original\":3,\"right_original\":3}", "{\"current\":-3,\"left_original\":3,\"right_original\":3}",
    ],
    prior_execution=20770160L,
    expected_policy=None,
  )
}

///|
test "cancelled coalesced USING chain cannot import a later original row" {
  managed_import_data_chain(
    CancelImport,
    input_control_task=1,
    query="FROM records AS l |> RIGHT JOIN records AS r USING (id) MAX_OUTPUT_ROWS 10 |> SET id = -id |> SELECT id AS `current`, l.id AS left_original, r.id AS right_original |> ORDER BY right_original",
    source_wire="[{\"id\":3,\"amount\":30},{\"id\":1,\"amount\":null},{\"id\":2,\"amount\":20},{\"id\":3,\"amount\":30}]",
    source_rows=4,
    expected_tasks=None,
    two_input_task=None,
    result_name="main",
    expected_rows=[
      "{\"current\":-1,\"left_original\":1,\"right_original\":1}", "{\"current\":-2,\"left_original\":2,\"right_original\":2}",
      "{\"current\":-3,\"left_original\":3,\"right_original\":3}", "{\"current\":-3,\"left_original\":3,\"right_original\":3}",
      "{\"current\":-3,\"left_original\":3,\"right_original\":3}", "{\"current\":-3,\"left_original\":3,\"right_original\":3}",
    ],
    prior_execution=20770160L,
    expected_policy=None,
  )
}

///|
test "empty original Source global aggregate retains its singleton through ordering" {
  managed_import_data_chain(
    Complete,
    query="SELECT 1 AS marker FROM records ORDER BY COUNT(*) + 1",
    source_wire="[]",
    source_rows=0,
    expected_tasks=None,
    two_input_task=None,
    result_name="main",
    expected_rows=["{\"marker\":1}"],
    prior_execution=20400678L,
    expected_policy=None,
  )
}

///|
test "empty Source count import refusal precedes decode and preserves original parents" {
  managed_import_data_chain(
    RefuseImport,
    input_control_task=1,
    query="SELECT 1 AS marker FROM records ORDER BY COUNT(*) + 1",
    source_wire="[]",
    source_rows=0,
    expected_tasks=None,
    two_input_task=None,
    result_name="main",
    expected_rows=["{\"marker\":1}"],
    prior_execution=20400678L,
    expected_policy=None,
  )
}

///|
test "cancelled empty Source count cannot decode a new row or publish its singleton" {
  managed_import_data_chain(
    CancelImport,
    input_control_task=1,
    query="SELECT 1 AS marker FROM records ORDER BY COUNT(*) + 1",
    source_wire="[]",
    source_rows=0,
    expected_tasks=None,
    two_input_task=None,
    result_name="main",
    expected_rows=["{\"marker\":1}"],
    prior_execution=20400678L,
    expected_policy=None,
  )
}
