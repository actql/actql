///|
// Existing checked Local plan and actual same Run Ledger; this is a Core
// resource/control component, not installed Host/Account or whole-VM backing.
fn capacity_boundary_setup(
  run : @strategy.CapturedDAG,
) -> Result[
  @strategy.CapturedTaskBoundaryHooks,
  @strategy.CapturedTaskBoundaryIssue,
] {
  @strategy.prepare_captured_task_boundary_hooks(
    run,
    @strategy.captured_dag_graph(run),
    @strategy.captured_dag_strategy_revision(run),
  )
}

///|
test "Debug setup refuses before constructing a holder when its SAME Run has no bytes" {
  let original = plan(prepared(@input.Aql("SELECT 1 AS n")), "debug-no-bytes")
  let root = @resources.create_ledger({
    planning_work: 1000,
    attempts: 10,
    holdings: 10,
    transfer_bytes: 0L,
    retained_bytes: 0L,
    execution_bytes: 0L,
  }).unwrap()
  let host = source_free_shared_host(original, root).unwrap()
  let run = local_compute_run(host)
  assert_true(capacity_boundary_setup(run) is Err(_))
  assert_true(@strategy.captured_task_boundary_hooks(run) is None)
  let usage = @resources.ledger_usage(root)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.live_reservations, 0)
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
}

///|
fn capacity_boundary_root(
  retained : Int64,
  execution : Int64,
) -> @resources.Ledger {
  @resources.create_ledger({
    planning_work: 1000,
    attempts: 10,
    holdings: 10,
    transfer_bytes: 0L,
    retained_bytes: retained,
    execution_bytes: execution,
  }).unwrap()
}

///|
fn capacity_boundary_host(
  id : String,
  root : @resources.Ledger,
) -> LocalComputeHost raise {
  source_free_shared_host(plan(prepared(@input.Aql("SELECT 1 AS n")), id), root).unwrap()
}

///|
test "Debug same-owner setup enforces exact and one-short original Ledger capacity" {
  let witness_root = capacity_boundary_root(100000L, 100000L)
  let witness = local_compute_run(
    capacity_boundary_host("debug-witness", witness_root),
  )
  let hooks = capacity_boundary_setup(witness).unwrap()
  let debit = @resources.ledger_usage(witness_root).reserved_retention_bytes
  assert_true(debit > 0L)
  assert_eq(
    @resources.ledger_usage(witness_root).reserved_execution_bytes,
    debit,
  )
  assert_eq(@resources.ledger_usage(witness_root).live_reservations, 1)
  assert_true(physical_equal(capacity_boundary_setup(witness).unwrap(), hooks))
  assert_eq(@resources.ledger_usage(witness_root).live_reservations, 1)
  @strategy.stop_captured_dag(witness)
  @strategy.refresh_captured_retention(witness)
  assert_eq(@resources.ledger_usage(witness_root).live_reservations, 0)
  for
    (retained, execution, succeeds) in [
      (debit, debit, true),
      (debit - 1L, debit, false),
      (debit, debit - 1L, false),
    ] {
    let root = capacity_boundary_root(retained, execution)
    let run = local_compute_run(
      capacity_boundary_host("debug-capacity-cut", root),
    )
    let result = capacity_boundary_setup(run)
    assert_eq(result is Ok(_), succeeds)
    if retained < debit {
      assert_true(result is Err(Resource(@resources.RetentionLimit)))
    } else if execution < debit {
      assert_true(result is Err(Resource(@resources.ExecutionLimit)))
    }
    assert_eq(
      @resources.ledger_usage(root).live_reservations,
      if succeeds {
        1
      } else {
        0
      },
    )
    @strategy.stop_captured_dag(run)
    @strategy.refresh_captured_retention(run)
    assert_false(@strategy.captured_task_boundary_cleanup_pending(run))
    assert_eq(@resources.ledger_usage(root).reserved_retention_bytes, 0L)
    assert_eq(@resources.ledger_usage(root).reserved_execution_bytes, 0L)
  }
}

///|
test "Debug read loans debit simultaneous overlap and stop cannot acknowledge their return" {
  let root = capacity_boundary_root(100000L, 100000L)
  let run = local_compute_run(
    capacity_boundary_host("debug-loan-overlap", root),
  )
  let hooks = capacity_boundary_setup(run).unwrap()
  let base = @resources.ledger_usage(root).reserved_retention_bytes
  @strategy.authorize_captured_task_activation(
    run,
    0,
    @strategy.task_activation_covered(),
  ).unwrap()
  let first = @strategy.read_captured_task_boundary(run, hooks, Before)
    .unwrap()
    .unwrap()
  let one = @resources.ledger_usage(root).reserved_retention_bytes - base
  assert_true(one > 0L)
  let second = @strategy.read_captured_task_boundary(run, hooks, Before)
    .unwrap()
    .unwrap()
  let third = @strategy.read_captured_task_boundary(run, hooks, Before)
    .unwrap()
    .unwrap()
  assert_true(@strategy.captured_task_boundary_current(run, first))
  assert_eq(
    @resources.ledger_usage(root).reserved_retention_bytes,
    base + 3L * one,
  )
  assert_eq(@resources.ledger_usage(root).live_reservations, 4)
  // Replacing the latest emitted fact creates no accumulated record history.
  for _ in 0..<10 {
    @strategy.authorize_captured_task_activation(
      run,
      0,
      @strategy.task_activation_covered(),
    ).unwrap()
  }
  assert_eq(
    @resources.ledger_usage(root).reserved_retention_bytes,
    base + 3L * one,
  )
  // Reissued equal scalar facts are still a different original observation.
  assert_false(@strategy.captured_task_boundary_current(run, first))
  @strategy.return_captured_task_boundary(second).unwrap()
  assert_false(@strategy.captured_task_boundary_current(run, second))
  assert_true(
    @strategy.return_captured_task_boundary(second) is Err(ReadReturned),
  )
  assert_eq(
    @resources.ledger_usage(root).reserved_retention_bytes,
    base + 2L * one,
  )
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  assert_true(@strategy.captured_task_boundary_cleanup_pending(run))
  assert_false(@strategy.captured_task_boundary_current(run, first))
  assert_eq(
    @resources.ledger_usage(root).reserved_retention_bytes,
    base + 2L * one,
  )
  @strategy.return_captured_task_boundary(first).unwrap()
  @strategy.refresh_captured_retention(run)
  assert_true(@strategy.captured_task_boundary_cleanup_pending(run))
  assert_eq(@resources.ledger_usage(root).reserved_retention_bytes, base + one)
  @strategy.return_captured_task_boundary(third).unwrap()
  @strategy.refresh_captured_retention(run)
  assert_false(@strategy.captured_task_boundary_cleanup_pending(run))
  assert_true(@strategy.captured_task_boundary_hooks(run) is None)
  assert_eq(@resources.ledger_usage(root).live_reservations, 0)
  assert_eq(@resources.ledger_usage(root).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(root).reserved_execution_bytes, 0L)
  assert_false(
    @strategy.captured_task_boundary_matches_graph(
      first,
      @strategy.captured_dag_graph(run),
    ),
  )
}

///|
test "Debug read refusal leaves original grant and ledger custody unchanged" {
  let root = capacity_boundary_root(100000L, 100000L)
  let run = local_compute_run(
    capacity_boundary_host("debug-read-refusal", root),
  )
  let hooks = capacity_boundary_setup(run).unwrap()
  let base = @resources.ledger_usage(root).reserved_retention_bytes
  @strategy.authorize_captured_task_activation(
    run,
    0,
    @strategy.task_activation_covered(),
  ).unwrap()
  let occupied = @resources.reserve_capacity(
    root,
    100000L - base,
    100000L - base,
  ).unwrap()
  assert_true(
    @strategy.read_captured_task_boundary(run, hooks, Before)
    is Err(Resource(@resources.RetentionLimit)),
  )
  assert_true(@strategy.captured_task_activation_granted(run, 0))
  assert_eq(@resources.ledger_usage(root).live_reservations, 2)
  @resources.settle_capacity(root, occupied).unwrap()
  let read = @strategy.read_captured_task_boundary(run, hooks, Before)
    .unwrap()
    .unwrap()
  assert_true(@strategy.captured_task_boundary_current(run, read))
  @strategy.return_captured_task_boundary(read).unwrap()
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  assert_eq(@resources.ledger_usage(root).live_reservations, 0)
}

///|
test "Debug setup rejects foreign graph and strategy before reserving or installing" {
  let first = compute_host(
    plan(prepared(@input.Aql("SELECT 1 AS n")), "debug-graph-a"),
  )
  let second = compute_host(
    plan(prepared(@input.Aql("SELECT 1 AS n")), "debug-graph-b"),
  )
  let run = local_compute_run(first)
  let other = local_compute_run(second)
  let before = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_true(
    @strategy.prepare_captured_task_boundary_hooks(
      run,
      @strategy.captured_dag_graph(other),
      0,
    )
    is Err(ForeignGraph),
  )
  assert_true(
    @strategy.prepare_captured_task_boundary_hooks(
      run,
      @strategy.captured_dag_graph(run),
      1,
    )
    is Err(ForeignStrategy),
  )
  assert_true(@strategy.captured_task_boundary_hooks(run) is None)
  assert_eq(@resources.ledger_usage(@strategy.captured_dag_ledger(run)), before)
  @strategy.stop_captured_dag(run)
  @strategy.stop_captured_dag(other)
  @strategy.refresh_captured_retention(run)
  @strategy.refresh_captured_retention(other)
}
