///|
test "Core owner control current admission fences reentry and activation before the state constructor" {
  let witness_root = capacity_boundary_root(100000L, 100000L)
  let witness = source_free_shared_host(
    plan(
      prepared(@input.Program(control_values_program)),
      "control-window-witness",
    ),
    witness_root,
  ).unwrap()
  prepare_local_compute_task_boundaries(witness).unwrap() |> ignore
  let base = @resources.ledger_usage(witness_root).reserved_retention_bytes
  @strategy.stop_captured_dag(local_compute_run(witness))
  @strategy.refresh_captured_retention(local_compute_run(witness))
  let action : Ref[(() -> Unit)?] = Ref(None)
  let (root, frame) = logical_callback_ledger(
    () => if action.val is Some(callback) { callback() },
    initial_window=2L *
      (base + @strategy.captured_task_control_construction_bytes()) -
      1L,
  )
  let host = source_free_shared_host(
    plan(
      prepared(@input.Program(control_values_program)),
      "control-admission-current",
    ),
    root,
  ).unwrap()
  let run = local_compute_run(host)
  let hooks = prepare_local_compute_task_boundaries(host).unwrap()
  let before = @resources.ledger_usage(root)
  let nested : Ref[Result[Unit, @strategy.CapturedTaskControlIssue]?] = Ref(
    None,
  )
  let activation : Ref[Result[Unit, @strategy.RunIssue]?] = Ref(None)
  let calls = Ref(0)
  action.val = Some(() => {
    calls.val += 1
    nested.val = Some(control_prepare(host))
    activation.val = Some(
      @strategy.authorize_captured_task_activation(
        run,
        0,
        @strategy.task_activation_covered(),
      ),
    )
  })
  assert_eq(
    control_prepare(host),
    Err(@strategy.Resource(@resources.ChildFundingUnavailable)),
  )
  action.val = None
  assert_eq(calls.val, 1)
  assert_eq(nested.val, Some(Err(@strategy.InProgress)))
  assert_true(activation.val is Some(Err(NotReady)))
  assert_true(
    @strategy.captured_task_control_state(run, hooks) is Err(NotPrepared),
  )
  let after = @resources.ledger_usage(root)
  assert_eq(after.live_reservations, before.live_reservations)
  assert_eq(after.reserved_retention_bytes, before.reserved_retention_bytes)
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  assert_eq(@resources.ledger_usage(root).live_reservations, 0)
  @resources.stop_imported_child_ledger(frame).unwrap()
}

///|
test "Core owner control stop retains a declined token until the same owner retries and the old holder stays unusable" {
  let action : Ref[(() -> Unit)?] = Ref(None)
  let (root, frame) = logical_callback_ledger(() => {
    if action.val is Some(callback) {
      callback()
    }
  })
  let host = source_free_shared_host(
    plan(
      prepared(@input.Program(control_values_program)),
      "control-declined-stop",
    ),
    root,
  ).unwrap()
  let run = local_compute_run(host)
  control_prepare(host).unwrap()
  let hooks = @strategy.captured_task_boundary_hooks(run).unwrap()
  let before = @resources.ledger_usage(root)
  let rejected_command : Ref[Result[Unit, @strategy.CapturedTaskControlIssue]?] = Ref(
    None,
  )
  let calls = Ref(0)
  action.val = Some(() => {
    calls.val += 1
    rejected_command.val = Some(control_command(host, 0, @strategy.ResumeStep))
    @strategy.stop_captured_dag(run)
  })
  // Force the existing Resource owner's actual acquire-current fence. No
  // false return callback or manufactured physical ACK is supplied.
  assert_true(
    @resources.reserve_capacity(root, 5000L, 5000L)
    is Err(ChildFundingUnavailable),
  )
  action.val = None
  assert_eq(calls.val, 1)
  assert_true(
    rejected_command.val
    is Some(Err(Resource(@resources.ChildFundingUnavailable))),
  )
  assert_true(@strategy.captured_task_control_state(run, hooks) is Err(Stopped))
  assert_true(@strategy.captured_task_boundary_cleanup_pending(run))
  assert_true(
    @strategy.captured_task_boundary_cleanup_issue(run)
    is Some(ChildFundingUnavailable),
  )
  assert_eq(
    @resources.ledger_usage(root).live_reservations,
    before.live_reservations,
  )
  assert_eq(
    @resources.ledger_usage(root).reserved_retention_bytes,
    before.reserved_retention_bytes,
  )
  // Same automatic Owner retry; no second consumer return/permission/Run.
  @strategy.refresh_captured_retention(run)
  assert_eq(@resources.ledger_usage(root).live_reservations, 0)
  assert_eq(@resources.ledger_usage(root).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(root).reserved_execution_bytes, 0L)
  assert_true(@strategy.captured_task_control_state(run, hooks) is Err(Stopped))
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  assert_eq(@resources.ledger_usage(root).live_reservations, 0)
  assert_eq(control_prepare(host), Err(@strategy.Stopped))
  @resources.stop_imported_child_ledger(frame).unwrap()
}

///|
test "Core owner control a refused actual completion cannot spend step credit or fabricate settled success" {
  let host = compute_host(
    plan(
      prepared(@input.Program(boundary_single_operation_program)),
      "control-failed-completion",
    ),
  )
  let run = local_compute_run(host)
  control_prepare(host).unwrap()
  control_command(host, 0, @strategy.ResumeStep).unwrap()
  let hooks = @strategy.captured_task_boundary_hooks(run).unwrap()
  let operations = boundary_test_start(host)
  let available = Ref(true)
  assert_true(
    (operations.complete)(0, operations.storage_bytes, () => available.val)
    is Err(@managed.Configuration(InvalidLimits)),
  )
  assert_eq(control_state(host), (1, @strategy.Stepping(0)))
  assert_false(@strategy.captured_task_completed(run, 0))
  assert_true(
    @strategy.read_captured_task_boundary(run, hooks, Settled).unwrap() is None,
  )
  @strategy.stop_captured_dag(run)
  boundary_test_close(host, operations, available, settle_stopped=true)
  assert_true(@strategy.captured_task_control_state(run, hooks) is Err(Stopped))
}

///|
test "Core owner control pause during actual work parks after its output and terminal resume keeps the same remaining tasks" {
  let host = compute_host(
    plan(
      prepared(@input.Program(control_values_program)),
      "control-pause-pending",
    ),
  )
  let run = local_compute_run(host)
  control_prepare(host).unwrap()
  control_command(host, 0, @strategy.ResumeStep).unwrap()
  let current = account(Allow)
  let start = compute_start(host)
  let available = Ref(true)
  let retained : Array[@managed.LocalManagedDispatchOperations[Int]] = []
  let outputs : Map[Int, @execution.ManagedCompletedOutput[Int]] = Map([])
  let first = start_local_compute_task(
      host,
      start,
      [],
      permit(host.plan.input, current),
      current,
      tuple(),
      context_cid(),
    )
    .unwrap()
    .unwrap()
  control_command(host, 1, @strategy.Pause).unwrap()
  assert_eq(control_state(host), (2, @strategy.PausePending))
  assert_false(@strategy.captured_task_completed(run, 0))
  outputs[0] = control_finish(first, 0, available)
  retained.push(first)
  assert_eq(control_state(host), (3, @strategy.Paused))
  assert_true(@strategy.next_captured_task(run) is None)
  control_command(host, 3, @strategy.ResumeTerminal).unwrap()
  for task in 1..<3 {
    let indexes = local_compute_producers(host)
    let operations = start_local_compute_task(
        host,
        start,
        indexes.map(index => outputs.get(index).unwrap()),
        permit(host.plan.input, current),
        current,
        tuple(),
        context_cid(),
      )
      .unwrap()
      .unwrap()
    for index, transfer in operations.inputs {
      let previous = retained[indexes[index]]
      for row in 0..<(previous.output_rows)() {
        (transfer.append)((previous.output_row)(row).unwrap()).unwrap()
      }
      (transfer.finish)().unwrap()
    }
    outputs[task] = control_finish(operations, task, available)
    retained.push(operations)
    assert_eq(
      control_state(host),
      if task == 1 {
        (4, @strategy.Running)
      } else {
        (5, @strategy.Completed)
      },
    )
  }
  assert_eq((retained[2].output_row)(0).unwrap(), "{\"value\":2}")
  control_close(host, retained, available)
}

///|
test "Core owner control prepays all three original completion scans or refuses before state construction" {
  // Configuration has its own existing charged work. Measure that unchanged
  // baseline independently; the new three checks plus nine completion-slot
  // visits are a fixed authored expectation, not read from the product quote.
  let witness_root = capacity_boundary_root(100000L, 100000L)
  let witness = source_free_shared_host(
    plan(
      prepared(@input.Program(control_values_program)),
      "control-work-baseline",
    ),
    witness_root,
  ).unwrap()
  prepare_local_compute_task_boundaries(witness).unwrap() |> ignore
  let baseline = @resources.ledger_usage(witness_root).planning_work
  @strategy.stop_captured_dag(local_compute_run(witness))
  @strategy.refresh_captured_retention(local_compute_run(witness))
  for (work, succeeds) in [(baseline + 11, false), (baseline + 12, true)] {
    let root = @resources.create_ledger({
      planning_work: work,
      attempts: 10,
      holdings: 10,
      transfer_bytes: 0L,
      retained_bytes: 100000L,
      execution_bytes: 100000L,
    }).unwrap()
    let host = source_free_shared_host(
      plan(
        prepared(@input.Program(control_values_program)),
        "control-planning-cut",
      ),
      root,
    ).unwrap()
    let result = control_prepare(host)
    assert_eq(result is Ok(_), succeeds)
    if !succeeds {
      assert_eq(result, Err(@strategy.Resource(@resources.PlanningLimit)))
    }
    assert_eq(
      @resources.ledger_usage(root).planning_work,
      if succeeds {
        baseline + 12
      } else {
        baseline
      },
    )
    assert_eq(
      @resources.ledger_usage(root).live_reservations,
      if succeeds {
        2
      } else {
        1
      },
    )
    @strategy.stop_captured_dag(local_compute_run(host))
    @strategy.refresh_captured_retention(local_compute_run(host))
    assert_eq(@resources.ledger_usage(root).live_reservations, 0)
  }
}
