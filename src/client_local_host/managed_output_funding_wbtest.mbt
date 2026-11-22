///|
// Existing checked Row Source and actual Local Task/Resource owners. Physical
// transport and Account are fixture ports, not ordinary DuckDB acceptance.
fn metered_tail_dispatch(
  value : CapturedTasksFixture,
) -> (
  @strategy.CapturedDAG,
  @local_driver.LocalManagedDispatchConfiguration[Int],
) {
  let run = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(value.setup),
  )
  @host_driver.refresh_compute_host(
    @builtin.configured_host_runtime(value.setup),
  ).unwrap()
  let installed = @builtin.configured_local_module(
    @builtin.configured_host_modules(value.setup),
  ).unwrap()
  let inputs : Array[@local_driver.LocalManagedAvailableOutput[Int]] = [
    @local_driver.local_managed_captured_relation_input(),
  ]
  let obligations = @strategy.captured_next_managed_obligations(run, 100000).unwrap()
  let dispatch = @local_driver.prepare_local_managed_dispatch_with_outputs(
      installed, inputs, obligations, 0L,
    )
    .unwrap()
    .unwrap()
  (run, dispatch)
}

///|
test "metered Local tail keeps original Source and all results through same Ledger cleanup" {
  let value = captured_tasks_fixture()
  let before = @resources.ledger_usage(value.ledger)
  let execution = execute_captured_local_tasks_guarded(
    value.setup,
    value.capture,
    value.requirements,
    1,
    100000,
    () => true,
  ).unwrap()
  assert_eq(execution.rows().unwrap(), ["{\"id\":2}"])
  assert_true(execution.close())
  assert_true(execution.close())
  let after = @resources.ledger_usage(value.ledger)
  assert_eq(after.attempts, before.attempts + 2)
  assert_eq(after.held_bytes, before.held_bytes)
  assert_eq(after.reserved_execution_bytes, before.reserved_execution_bytes)
  assert_true(@row_source_host.row_capture_source(value.capture) is Ok(_))
  captured_tasks_close_source(value)
}

///|
test "actual Task output growth refusal preserves Source and returns only failed Task obligations" {
  let value = captured_tasks_fixture()
  let before = @resources.ledger_usage(value.ledger)
  let (run, dispatch) = metered_tail_dispatch(value)
  let (_, startup) = @local_driver.local_managed_dispatch_site_capacity(
    dispatch,
  ).unwrap()
  let limits = @resources.ledger_limits(value.ledger)
  let block = @resources.reserve_capacity(
    value.ledger,
    0L,
    limits.execution_bytes -
    @resources.ledger_usage(value.ledger).reserved_execution_bytes -
    startup,
  ).unwrap()
  let operations = @local_driver.start_local_managed_dispatch_node(dispatch).unwrap()
  let tasks : Array[LocalValuesTaskExecution?] = Array::make(3, None)
  tasks[1] = Some({ operations, settled: false, completed: None, })
  guard (operations.execute)()
    is Err(
      @local_driver.ExecutionCapacityRefusal(
        @resources.ExecutionLimit,
        needed,
        available,
        policy
      )
    ) else {
    fail("expected the original typed ExecutionLimit reservation refusal")
  }
  assert_true(needed > available && available >= 0L && policy >= available)
  assert_false(@strategy.captured_task_completed(run, 1))
  let mut closed = false
  for _ in 0..<10000 {
    if close_local_values_tasks(run, tasks) {
      closed = true
      break
    }
  }
  assert_true(closed)
  assert_true(@row_source_host.row_capture_source(value.capture) is Ok(_))
  @resources.settle_capacity(value.ledger, block).unwrap()
  let after = @resources.ledger_usage(value.ledger)
  assert_eq(after.attempts, before.attempts + 1)
  assert_eq(after.held_bytes, before.held_bytes)
  assert_eq(after.reserved_execution_bytes, before.reserved_execution_bytes)
  captured_tasks_close_source(value)
}

///|
test "actual Task accepts exact output backing when a spare page cannot fit" {
  // The original first compute task has two rows in each of its filter and
  // projection buffers: four row roots, four numbers and four id names.
  let output = @execution.execution_capacity_inventory_bytes([
    { unit: ValueNodeSlots, count: 8L, copies: 1, },
    { unit: DecodedTextBytes, count: 8L, copies: 1, },
  ]).unwrap()
  // The predicate visits 3,1,2. Its scalar operands peak at two canonical
  // bytes, then release before the Boolean result. The false result is the
  // five-byte peak; the same working owner retains that peak after release
  // while all four output rows accumulate. These units are canonical extent,
  // not one generic slot per Boolean. A spare 16KiB page still cannot fit.
  let predicate = @execution.execution_capacity_inventory_bytes([
    { unit: ValueNodeSlots, count: 5L, copies: 1, },
    { unit: CanonicalWireBytes, count: 5L, copies: 1, },
  ]).unwrap()
  assert_eq(output, 2112L)
  assert_eq(predicate, 1320L)
  let exact = output + predicate
  for short in [false, true] {
    let value = captured_tasks_fixture()
    let before = @resources.ledger_usage(value.ledger)
    let (run, dispatch) = metered_tail_dispatch(value)
    let (_, startup) = @local_driver.local_managed_dispatch_site_capacity(
      dispatch,
    ).unwrap()
    let block = @resources.reserve_capacity(
      value.ledger,
      0L,
      @resources.ledger_limits(value.ledger).execution_bytes -
      @resources.ledger_usage(value.ledger).reserved_execution_bytes -
      startup -
      (if short { exact - 1L } else { exact }),
    ).unwrap()
    let operations = @local_driver.start_local_managed_dispatch_node(dispatch).unwrap()
    let tasks : Array[LocalValuesTaskExecution?] = Array::make(3, None)
    tasks[1] = Some({ operations, settled: false, completed: None, })
    let result = (operations.execute)()
    if short {
      guard result
        is Err(
          @local_driver.ExecutionCapacityRefusal(
            @resources.ExecutionLimit,
            needed,
            available,
            _
          )
        ) else {
        fail(
          "one-byte-short exact backing must preserve its typed ExecutionLimit",
        )
      }
      assert_eq(needed, available + 1L)
      assert_false(@strategy.captured_task_completed(run, 1))
    } else {
      result.unwrap()
      assert_eq((operations.output_rows)(), 2)
      assert_eq((operations.output_row)(0).unwrap(), "{\"id\":3}")
      assert_eq((operations.output_row)(1).unwrap(), "{\"id\":2}")
      assert_true((operations.execution_stopped)())
      assert_eq(
        @resources.ledger_usage(value.ledger).reserved_execution_bytes,
        @resources.ledger_limits(value.ledger).execution_bytes,
      )
    }
    assert_true(close_local_values_tasks(run, tasks))
    @resources.settle_capacity(value.ledger, block).unwrap()
    let after = @resources.ledger_usage(value.ledger)
    assert_eq(after.attempts, before.attempts + 1)
    assert_eq(after.held_bytes, before.held_bytes)
    assert_eq(after.reserved_execution_bytes, before.reserved_execution_bytes)
    assert_true(@row_source_host.row_capture_source(value.capture) is Ok(_))
    captured_tasks_close_source(value)
  }
}

///|
test "small actual output completes on tight original retention despite large declared maximum" {
  let value = captured_tasks_fixture()
  let before = @resources.ledger_usage(value.ledger)
  let (run, dispatch) = metered_tail_dispatch(value)
  let (startup, _) = @local_driver.local_managed_dispatch_site_capacity(
    dispatch,
  ).unwrap()
  // Two earlier output buffers and the final two-row scratch use 3168 bytes.
  // The existing reference-free finalizer also retains 3528 metadata bytes:
  // twelve growing arrays plus its column/finish/row/receipt controls (width1).
  // Full-copy occurrence tuples and publication-bridge aliases add the same
  // bounded 6H/24R/4W control representation before the next row reservation.
  // Derive its fixture allowance from the unchanged common tariffs. This is
  // constructor overhead, not declared-row payload or a larger product quota.
  let original_projection_controls = @execution.preparation_representation_cost({
      record_headers: 6L,
      reference_slots: 24L,
      scalar_words: 4L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
  ).unwrap()
  let actual = 3168L + 3528L + original_projection_controls
  assert_true(
    startup + actual < value.requirements.maximum_limits().retained_bytes,
  )
  let block = @resources.reserve_capacity(
    value.ledger,
    @resources.ledger_limits(value.ledger).retained_bytes -
    before.held_bytes -
    before.reserved_retention_bytes -
    startup -
    actual,
    0L,
  ).unwrap()
  let operations = @local_driver.start_local_managed_dispatch_node(dispatch).unwrap()
  let task : LocalValuesTaskExecution = {
    operations,
    settled: false,
    completed: None,
  }
  let tasks : Array[LocalValuesTaskExecution?] = [None, Some(task), None]
  let payload : Ref[Int?] = Ref(Some(1))
  let available = () => payload.val is Some(_)
  (operations.execute)().unwrap()
  (operations.prepare_finalization)(
    payload.val.unwrap(),
    operations.storage_bytes,
    available,
  ).unwrap()
  let mut finished = false
  for _ in 0..<100000 {
    if (operations.advance_finalization)(1).unwrap().complete {
      finished = true
      break
    }
  }
  assert_true(finished)
  (operations.settle)().unwrap()
  task.settled = true
  let completed = (operations.complete)(
    payload.val.unwrap(),
    operations.storage_bytes,
    available,
  ).unwrap()
  task.completed = Some(completed)
  assert_eq(
    @execution.managed_completed_output_storage_bytes(completed),
    Some(startup + 1056L),
  )
  assert_eq(
    @resources.ledger_usage(value.ledger).held_bytes - before.held_bytes,
    startup + 1056L,
  )
  assert_true(@strategy.captured_task_completed(run, 1))
  // The fixture Host drops its actual retained payload after the last use.
  // A constant-true storage callback cannot acknowledge its destruction.
  payload.val = None
  let mut closed = false
  for _ in 0..<10000 {
    if close_local_values_tasks(run, tasks) {
      closed = true
      break
    }
  }
  assert_true(closed)
  @resources.settle_capacity(value.ledger, block).unwrap()
  let after = @resources.ledger_usage(value.ledger)
  assert_eq(after.attempts, before.attempts + 1)
  assert_eq(after.held_bytes, before.held_bytes)
  assert_eq(after.reserved_retention_bytes, before.reserved_retention_bytes)
  assert_eq(after.reserved_execution_bytes, before.reserved_execution_bytes)
  captured_tasks_close_source(value)
}

///|
test "real retention exhaustion refuses output before atomic capacity mutation" {
  let value = captured_tasks_fixture()
  let before = @resources.ledger_usage(value.ledger)
  let (run, dispatch) = metered_tail_dispatch(value)
  let (startup, execution) = @local_driver.local_managed_dispatch_site_capacity(
    dispatch,
  ).unwrap()
  let block = @resources.reserve_capacity(
    value.ledger,
    @resources.ledger_limits(value.ledger).retained_bytes -
    before.held_bytes -
    before.reserved_retention_bytes -
    startup -
    528L,
    0L,
  ).unwrap()
  let operations = @local_driver.start_local_managed_dispatch_node(dispatch).unwrap()
  let tasks : Array[LocalValuesTaskExecution?] = [
    None,
    Some({ operations, settled: false, completed: None, }),
    None,
  ]
  let started = @resources.ledger_usage(value.ledger)
  let mut working_grew_before_output = false
  let mut refused = false
  for _ in 0..<10000 {
    let before_step = @resources.ledger_usage(value.ledger)
    match (operations.advance)(1) {
      Err(
        @local_driver.ExecutionCapacityRefusal(
          @resources.RetentionLimit,
          needed,
          available,
          policy
        )
      ) => {
        assert_true(
          needed > available && available >= 0L && policy >= available,
        )
        let after_step = @resources.ledger_usage(value.ledger)
        // Earlier successful predicate funding remains live. This exact
        // failed grow atomically leaves BOTH reservation dimensions and
        // original holdings unchanged; spent work is not rolled back.
        assert_eq(
          after_step.reserved_retention_bytes,
          before_step.reserved_retention_bytes,
        )
        assert_eq(
          after_step.reserved_execution_bytes,
          before_step.reserved_execution_bytes,
        )
        assert_eq(after_step.held_bytes, before_step.held_bytes)
        assert_eq(after_step.live_reservations, before_step.live_reservations)
        refused = true
        break
      }
      Err(_) =>
        fail("expected the original typed RetentionLimit reservation refusal")
      Ok(progress) => {
        let after_step = @resources.ledger_usage(value.ledger)
        if after_step.reserved_execution_bytes >
          started.reserved_execution_bytes &&
          after_step.reserved_retention_bytes ==
          started.reserved_retention_bytes {
          working_grew_before_output = true
        }
        assert_false(progress.complete)
      }
    }
  }
  assert_true(refused && working_grew_before_output)
  assert_true(
    @resources.ledger_usage(value.ledger).reserved_execution_bytes >
    before.reserved_execution_bytes + execution,
  )
  assert_false(@strategy.captured_task_completed(run, 1))
  assert_true(close_local_values_tasks(run, tasks))
  @resources.settle_capacity(value.ledger, block).unwrap()
  let after = @resources.ledger_usage(value.ledger)
  assert_eq(after.attempts, before.attempts + 1)
  assert_eq(after.held_bytes, before.held_bytes)
  assert_eq(after.reserved_retention_bytes, before.reserved_retention_bytes)
  assert_eq(after.reserved_execution_bytes, before.reserved_execution_bytes)
  assert_true(@row_source_host.row_capture_source(value.capture) is Ok(_))
  captured_tasks_close_source(value)
}

///|
test "cancelling an actual growing Task retains Source until its own cleanup" {
  let value = captured_tasks_fixture()
  let before = @resources.ledger_usage(value.ledger)
  let (run, dispatch) = metered_tail_dispatch(value)
  let operations = @local_driver.start_local_managed_dispatch_node(dispatch).unwrap()
  let tasks : Array[LocalValuesTaskExecution?] = Array::make(3, None)
  tasks[1] = Some({ operations, settled: false, completed: None, })
  let started = @resources.ledger_usage(value.ledger).reserved_execution_bytes
  let mut grew = false
  for _ in 0..<100000 {
    (operations.advance)(1).unwrap() |> ignore
    if @resources.ledger_usage(value.ledger).reserved_execution_bytes > started {
      grew = true
      break
    }
  }
  assert_true(grew)
  assert_true((operations.request_cancel)())
  // Cancellation requests stop; the same started provider must report its
  // actual bounded stop before cleanup can relinquish its reservation.
  let mut stopped = false
  for _ in 0..<10000 {
    (operations.advance)(1) |> ignore
    if (operations.execution_stopped)() {
      stopped = true
      break
    }
  }
  assert_true(stopped)
  let mut closed = false
  for _ in 0..<10000 {
    if close_local_values_tasks(run, tasks) {
      closed = true
      break
    }
  }
  assert_true(closed)
  assert_false(@strategy.captured_task_completed(run, 1))
  assert_true(@row_source_host.row_capture_source(value.capture) is Ok(_))
  let after = @resources.ledger_usage(value.ledger)
  assert_eq(after.attempts, before.attempts + 1)
  assert_eq(after.held_bytes, before.held_bytes)
  assert_eq(after.reserved_execution_bytes, before.reserved_execution_bytes)
  captured_tasks_close_source(value)
}

///|
test "metered Cross Join task preserves exact duplicate rows on its original Source Ledger" {
  let document =
    #|{"version":"actql/0.1","id":"funded-cross-chain","stages":[{"id":"acquire","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > 0"},{"select":["id"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["id"]}}},{"id":"compute","inputs":{"r":{"result":{"stage":"acquire","result":"rows"}}},"steps":[{"from":"r","cross_join":{"with":"r","select":{"id":"left.id"}},"as":"pairs"},{"from":"pairs","select":["id"],"as":"selected"},{"from":"selected","select":["id"],"as":"out"}],"results":{"rows":{"from":"out","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"compute","result":"rows"}}}}
  let environment = @publication_host.admit_client_check_environment(
    source_query_original_environment,
    "sha256:40c45acbf81bdf192d79b7e8f65a5731ba6065b1d4b8cc7b4cab89ab4ac85c60",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let prepared = match
    @publication_host.prepare_effect_free_client_program(
      document,
      Json,
      environment,
      None,
      @publication_host.client_standard_program_preparation_limits(),
    ) {
    Ok(value) => value
    Err(Syntax(issue)) => fail("Cross Join syntax: " + @debug.to_string(issue))
    Err(Check(issue)) =>
      fail(
        "Cross Join check: " +
        @debug.to_string(@checked.diagnostic_category(issue)),
      )
    Err(_) => fail("Cross Join preparation outside syntax/check")
  }
  let value = captured_tasks_fixture(original=Some(prepared))
  let before = @resources.ledger_usage(value.ledger)
  let execution = execute_captured_local_tasks_guarded(
    value.setup,
    value.capture,
    value.requirements,
    1,
    100000,
    () => true,
  ).unwrap()
  let rows = execution.rows().unwrap()
  rows.sort()
  assert_eq(rows, [
    "{\"id\":1}", "{\"id\":1}", "{\"id\":1}", "{\"id\":2}", "{\"id\":2}", "{\"id\":2}",
    "{\"id\":3}", "{\"id\":3}", "{\"id\":3}",
  ])
  assert_true(execution.close())
  let after = @resources.ledger_usage(value.ledger)
  assert_eq(after.attempts, before.attempts + 1)
  assert_eq(after.held_bytes, before.held_bytes)
  assert_eq(after.reserved_execution_bytes, before.reserved_execution_bytes)
  assert_true(@row_source_host.row_capture_source(value.capture) is Ok(_))
  captured_tasks_close_source(value)
}
