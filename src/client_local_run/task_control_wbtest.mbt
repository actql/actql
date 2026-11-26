///|
// Real checked compiler graph and registered Local kernels. Each Stage has
// one original logical operation; no fake task completion or graph replacement.
// This is Core control coverage, not durable/public pause/step acceptance.
let control_values_program : String =
  #|{"version":"actql/0.1","id":"control.values","stages":[{"id":"seed","inputs":{},"steps":[{"values":{"schema":{"n":{"type":"number","nullable":false}},"rows":[{"n":1}]},"as":"data"}],"results":{"rows":{"from":"data","fields":["n"]}}},{"id":"compute","inputs":{"seed":{"result":{"stage":"seed","result":"rows"}}},"steps":[{"derive":{"value":"n + 1"},"as":"derived"}],"results":{"rows":{"from":"derived","fields":["value"]}}},{"id":"finish","inputs":{"data":{"result":{"stage":"compute","result":"rows"}}},"steps":[{"select":["value"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["value"]}}}],"results":{"answer":{"from":{"stage":"finish","result":"rows"}}}}

///|
fn control_account(
  outcome? : @authorization.ConfiguredOutcome = Allow,
) -> @authorization.AdmittedAccountConfiguration {
  @authorization.admit_account_configuration({
    account_id: "local-account",
    entries: [
      {
        entry_id: "explicit-control",
        outcome,
        scope: {
          principal: AnyOf(["local-user"]),
          connection: AnyOf(["python.local"]),
          resource: AnyOf(["runs"]),
          operation: AnyOf(["pause", "resume"]),
        },
        exclusions: [],
      },
    ],
    bootstrap: None,
  }).unwrap()
}

///|
fn control_tuple(operation : String) -> @authorization.AccessTuple {
  { ..tuple(), operation, }
}

///|
fn control_permit(
  host : LocalComputeHost,
  operation : String,
) -> @authorization.DispatchAuthorization {
  @authorization.bind_dispatch_authorization(
    control_account(),
    control_tuple(operation),
    Activation,
    @publication.publication_contract_identity(host.plan.definition),
    host.plan.execution_context_cid,
  ).unwrap()
}

///|
fn control_prepare(
  host : LocalComputeHost,
) -> Result[Unit, @strategy.CapturedTaskControlIssue] {
  prepare_local_compute_task_control(
    host,
    control_permit(host, "pause"),
    control_account(),
    control_tuple("pause"),
  )
}

///|
fn control_command(
  host : LocalComputeHost,
  revision : Int,
  command : @strategy.CapturedTaskControlCommand,
) -> Result[Unit, @strategy.CapturedTaskControlIssue] {
  let operation = if command == @strategy.Pause { "pause" } else { "resume" }
  command_local_compute_task_control(
    host,
    revision,
    command,
    control_permit(host, operation),
    control_account(),
    control_tuple(operation),
  )
}

///|
fn control_state(
  host : LocalComputeHost,
) -> (Int, @strategy.CapturedTaskControlPhase) {
  let run = local_compute_run(host)
  @strategy.captured_task_control_state(
    run,
    @strategy.captured_task_boundary_hooks(run).unwrap(),
  ).unwrap()
}

///|
fn control_finish(
  operations : @managed.LocalManagedDispatchOperations[Int],
  task : Int,
  available : Ref[Bool],
) -> @execution.ManagedCompletedOutput[Int] raise {
  let mut done = false
  for _ in 0..<1000 {
    if (operations.advance)(1).unwrap().complete {
      done = true
      break
    }
  }
  assert_true(done)
  (operations.prepare_finalization)(task, operations.storage_bytes, () => {
    available.val
  }).unwrap()
  done = false
  for _ in 0..<1000 {
    if (operations.advance_finalization)(1).unwrap().complete {
      done = true
      break
    }
  }
  assert_true(done)
  (operations.settle)().unwrap()
  (operations.complete)(task, operations.storage_bytes, () => available.val).unwrap()
}

///|
fn control_close(
  host : LocalComputeHost,
  operations : Array[@managed.LocalManagedDispatchOperations[Int]],
  available : Ref[Bool],
) -> Unit raise {
  let run = local_compute_run(host)
  available.val = false
  for offset in 0..<operations.length() {
    let task = operations.length() - offset - 1
    let operation = operations[task]
    (operation.close)()
    @strategy.close_captured_task_output(run, task)
    assert_true((operation.cleanup_refresh)())
  }
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  assert_false(@strategy.captured_task_boundary_cleanup_pending(run))
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.live_reservations, 0)
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
}

///|
test "Core step spends one credit only at the actual original operation output commit" {
  let host = compute_host(
    plan(prepared(@input.Program(control_values_program)), "step-original"),
  )
  let run = local_compute_run(host)
  assert_eq(@strategy.graph_task_count(@strategy.captured_dag_graph(run)), 3)
  control_prepare(host).unwrap()
  let hooks = @strategy.captured_task_boundary_hooks(run).unwrap()
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(control_prepare(host), Err(@strategy.AlreadyStarted))
  assert_true(
    physical_equal(prepare_local_compute_task_boundaries(host).unwrap(), hooks),
  )
  assert_eq(@resources.ledger_usage(@strategy.captured_dag_ledger(run)), usage)
  assert_eq(control_state(host), (0, @strategy.Paused))
  let start = compute_start(host)
  let available = Ref(true)
  let outputs : Map[Int, @execution.ManagedCompletedOutput[Int]] = Map([])
  let retained : Array[@managed.LocalManagedDispatchOperations[Int]] = []
  for task in 0..<3 {
    assert_true(@strategy.next_captured_task(run) is None)
    assert_true(
      @strategy.authorize_captured_task_activation(
        run,
        task,
        @strategy.task_activation_covered(),
      )
      is Err(NotReady),
    )
    control_command(host, task * 2, @strategy.ResumeStep).unwrap()
    assert_eq(control_state(host), (task * 2 + 1, @strategy.Stepping(task)))
    assert_eq(@strategy.next_captured_task(run), Some(task))
    assert_eq(
      control_command(host, task * 2, @strategy.ResumeTerminal),
      Err(@strategy.StaleRevision),
    )
    // The SAME original granted before record remains just the first phase,
    // not a second operation credit or a fabricated completed step.
    @strategy.authorize_captured_task_activation(
      run,
      task,
      @strategy.task_activation_covered(),
    ).unwrap()
    let before = @strategy.read_captured_task_boundary(run, hooks, Before)
      .unwrap()
      .unwrap()
    assert_eq(@strategy.captured_task_boundary_task(before), task)
    let indexes = local_compute_producers(host)
    let inputs = indexes.map(index => outputs.get(index).unwrap())
    let operations = start_local_compute_task(
        host,
        start,
        inputs,
        permit(host.plan.input, account(Allow)),
        account(Allow),
        tuple(),
        context_cid(),
      )
      .unwrap()
      .unwrap()
    assert_eq(control_state(host), (task * 2 + 1, @strategy.Stepping(task)))
    for index, transfer in operations.inputs {
      let source = retained[indexes[index]]
      for row in 0..<(source.output_rows)() {
        (transfer.append)((source.output_row)(row).unwrap()).unwrap()
      }
      (transfer.finish)().unwrap()
    }
    outputs[task] = control_finish(operations, task, available)
    retained.push(operations)
    assert_true(@strategy.captured_task_completed(run, task))
    assert_eq(
      control_state(host),
      (
        task * 2 + 2,
        if task == 2 {
          @strategy.Completed
        } else {
          @strategy.Paused
        },
      ),
    )
    let settled = @strategy.read_captured_task_boundary(run, hooks, Settled)
      .unwrap()
      .unwrap()
    assert_eq(@strategy.captured_task_boundary_task(settled), task)
    assert_false(@strategy.captured_task_boundary_current(run, before))
    @strategy.return_captured_task_boundary(before).unwrap()
    @strategy.return_captured_task_boundary(settled).unwrap()
  }
  assert_eq((retained[2].output_row)(0).unwrap(), "{\"value\":2}")
  assert_true(@strategy.next_captured_task(run) is None)
  assert_eq(
    control_command(host, 6, @strategy.ResumeStep),
    Err(@strategy.InvalidTransition),
  )
  control_close(host, retained, available)
}

///|
test "Core control authorization stays bound to the original configured Run and current Account" {
  let first = compute_host(
    plan(prepared(@input.Program(control_values_program)), "control-first"),
  )
  let other = compute_host(
    plan(prepared(@input.Program(control_values_program)), "control-other"),
  )
  let run = local_compute_run(first)
  assert_true(
    prepare_local_compute_task_control(
      first,
      control_permit(other, "pause"),
      control_account(),
      control_tuple("pause"),
    )
    is Err(AuthorizationMismatch),
  )
  assert_true(@strategy.captured_task_boundary_hooks(run) is None)
  assert_true(
    prepare_local_compute_task_control(
      first,
      control_permit(first, "pause"),
      control_account(outcome=Deny),
      control_tuple("pause"),
    )
    is Err(AuthorizationMismatch),
  )
  assert_true(@strategy.captured_task_boundary_hooks(run) is None)
  assert_eq(control_prepare(first), Ok(()))
  let before = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_true(
    command_local_compute_task_control(
      first,
      0,
      @strategy.ResumeStep,
      control_permit(other, "resume"),
      control_account(),
      control_tuple("resume"),
    )
    is Err(AuthorizationMismatch),
  )
  assert_eq(control_state(first), (0, @strategy.Paused))
  assert_eq(@resources.ledger_usage(@strategy.captured_dag_ledger(run)), before)
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  @strategy.stop_captured_dag(local_compute_run(other))
  @strategy.refresh_captured_retention(local_compute_run(other))
  assert_eq(
    @resources.ledger_usage(@strategy.captured_dag_ledger(run)).live_reservations,
    0,
  )
}

///|
test "Core control capacity admits exact original state and rejects either one short before construction" {
  let witness_root = capacity_boundary_root(100000L, 100000L)
  let witness = source_free_shared_host(
    plan(
      prepared(@input.Program(control_values_program)),
      "control-capacity-witness",
    ),
    witness_root,
  ).unwrap()
  prepare_local_compute_task_boundaries(witness).unwrap() |> ignore
  let base = @resources.ledger_usage(witness_root).reserved_retention_bytes
  assert_eq(control_prepare(witness), Ok(()))
  let debit = @strategy.captured_task_control_construction_bytes(
    @strategy.graph_task_count(
      @strategy.captured_dag_graph(local_compute_run(witness)),
    ),
  )
  assert_eq(
    @resources.ledger_usage(witness_root).reserved_retention_bytes,
    base + debit,
  )
  assert_eq(@resources.ledger_usage(witness_root).live_reservations, 2)
  @strategy.stop_captured_dag(local_compute_run(witness))
  @strategy.refresh_captured_retention(local_compute_run(witness))
  assert_eq(@resources.ledger_usage(witness_root).live_reservations, 0)
  for
    (retained, execution, expected) in [
      (base + debit, base + debit, true),
      (base + debit - 1L, base + debit, false),
      (base + debit, base + debit - 1L, false),
    ] {
    let root = capacity_boundary_root(retained, execution)
    let host = source_free_shared_host(
      plan(prepared(@input.Program(control_values_program)), "control-capacity"),
      root,
    ).unwrap()
    let result = control_prepare(host)
    assert_eq(result is Ok(_), expected)
    if !expected {
      assert_true(result is Err(Resource(_)))
      assert_true(
        @strategy.next_captured_task(local_compute_run(host)) is Some(0),
      )
      let hooks = @strategy.captured_task_boundary_hooks(
        local_compute_run(host),
      ).unwrap()
      assert_true(
        @strategy.captured_task_control_state(local_compute_run(host), hooks)
        is Err(NotPrepared),
      )
    }
    @strategy.stop_captured_dag(local_compute_run(host))
    @strategy.refresh_captured_retention(local_compute_run(host))
    assert_eq(@resources.ledger_usage(root).live_reservations, 0)
  }
}

///|
test "Core control refuses a genuine fused task before work rather than inventing a logical stop" {
  let host = compute_host(
    plan(prepared(@input.Aql("SELECT 1 AS n")), "control-fused"),
  )
  let run = local_compute_run(host)
  assert_eq(control_prepare(host), Err(@strategy.BoundaryUnavailable(0)))
  assert_eq(
    @resources.ledger_usage(@strategy.captured_dag_ledger(run)).attempts,
    0,
  )
  let hooks = @strategy.captured_task_boundary_hooks(run).unwrap()
  assert_true(
    @strategy.captured_task_control_state(run, hooks) is Err(NotPrepared),
  )
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  assert_eq(
    @resources.ledger_usage(@strategy.captured_dag_ledger(run)).live_reservations,
    0,
  )
}
