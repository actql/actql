///|
// Existing checked compiler originals are explicit inputs to this resource
// component. Their first-capture/ACK and physical-parent funding are separate.
fn logical_capacity_fixture(
  root : @resources.Ledger,
  id : String,
  program? : String = boundary_single_operation_program,
) -> (
  LocalRunPlan,
  LocalComputeHost,
  @host.ClientStructuralExplanationOriginal,
  @strategy.CapturedTaskBoundary,
) raise {
  let original = plan(prepared(@input.Program(program)), id)
  let host = source_free_shared_host(original, root).unwrap()
  let run = local_compute_run(host)
  let facts = @host.capture_client_structural_explanation_original(
    original.compiled,
    original.prepared,
    1000000,
    100000,
    100,
  ).unwrap()
  let hooks = capacity_boundary_setup(run).unwrap()
  @strategy.authorize_captured_task_activation(
    run,
    0,
    @strategy.task_activation_covered(),
  ).unwrap()
  let observed = @strategy.read_captured_task_boundary(run, hooks, Before)
    .unwrap()
    .unwrap()
  (original, host, facts, observed)
}

///|
test "logical boundary cannot construct a higher wrapper without same-Run capacity" {
  let root = capacity_boundary_root(100000L, 100000L)
  let (original, host, facts, observed) = logical_capacity_fixture(
    root, "logical-no-bytes",
  )
  let run = local_compute_run(host)
  let used = @resources.ledger_usage(root)
  let occupied = @resources.reserve_capacity(
    root,
    100000L - used.reserved_retention_bytes,
    100000L - used.reserved_execution_bytes,
  ).unwrap()
  assert_true(
    @host.bind_client_logical_task_boundary(
      facts,
      original.compiled,
      original.prepared,
      run,
      observed,
      1000,
    )
    is Err(_),
  )
  assert_true(@strategy.captured_task_boundary_current(run, observed))
  assert_eq(@resources.ledger_usage(root).live_reservations, 3)
  @resources.settle_capacity(root, occupied).unwrap()
  @strategy.return_captured_task_boundary(observed).unwrap()
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  assert_eq(@resources.ledger_usage(root).live_reservations, 0)
}

///|
fn logical_capacity_bind(
  original : LocalRunPlan,
  host : LocalComputeHost,
  facts : @host.ClientStructuralExplanationOriginal,
  observed : @strategy.CapturedTaskBoundary,
) -> @host.ClientLogicalTaskBoundary raise {
  guard @host.bind_client_logical_task_boundary(
      facts,
      original.compiled,
      original.prepared,
      local_compute_run(host),
      observed,
      1000,
    ).unwrap()
    is Projected(value) else {
    fail("missing actual original boundary")
  }
  value
}

///|
test "logical forks retain individual SAME Run debt after source return and stop" {
  let root = capacity_boundary_root(100000L, 100000L)
  let (original, host, facts, source) = logical_capacity_fixture(
    root, "logical-independent",
  )
  let run = local_compute_run(host)
  let before = @resources.ledger_usage(root)
  let first = logical_capacity_bind(original, host, facts, source)
  let one = @resources.ledger_usage(root).reserved_retention_bytes -
    before.reserved_retention_bytes
  assert_true(one > 0L)
  let second = logical_capacity_bind(original, host, facts, source)
  assert_eq(
    @resources.ledger_usage(root).reserved_retention_bytes,
    before.reserved_retention_bytes + 2L * one,
  )
  assert_eq(
    @resources.ledger_usage(root).reserved_execution_bytes,
    before.reserved_execution_bytes + 2L * one,
  )
  assert_eq(@resources.ledger_usage(root).live_reservations, 4)
  let step = @host.client_logical_task_boundary_step_id(
    first,
    original.compiled,
    original.prepared,
  ).unwrap()
  @strategy.return_captured_task_boundary(source).unwrap()
  assert_true(
    @host.client_logical_task_boundary_current(
      first,
      original.compiled,
      original.prepared,
    ),
  )
  assert_eq(
    @host.client_logical_task_boundary_step_id(
      second,
      original.compiled,
      original.prepared,
    ).unwrap(),
    step,
  )
  @host.return_client_logical_task_boundary(first).unwrap()
  assert_false(
    @host.client_logical_task_boundary_current(
      first,
      original.compiled,
      original.prepared,
    ),
  )
  @host.return_client_logical_task_boundary(first).unwrap()
  assert_true(
    @host.client_logical_task_boundary_current(
      second,
      original.compiled,
      original.prepared,
    ),
  )
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  assert_true(@strategy.captured_task_boundary_cleanup_pending(run))
  assert_eq(@resources.ledger_usage(root).live_reservations, 2)
  assert_false(
    @host.client_logical_task_boundary_current(
      second,
      original.compiled,
      original.prepared,
    ),
  )
  @host.return_client_logical_task_boundary(second).unwrap()
  @strategy.refresh_captured_retention(run)
  assert_eq(@resources.ledger_usage(root).live_reservations, 0)
}

///|
test "logical construction admits exact fixed peak and rejects one-short retention or execution" {
  // Independent H16/R8/W8 owner inventory: physical fork H10/R13/W19=416;
  // higher wrapper H5/R9/W3=176; fixed lookup H154/R128/W188=4992.
  let debit = 5584L
  for
    (retained, execution, succeeds) in [
      (debit, debit, true),
      (debit - 1L, debit, false),
      (debit, debit - 1L, false),
    ] {
    let root = capacity_boundary_root(100000L, 100000L)
    let (original, host, facts, source) = logical_capacity_fixture(
      root, "logical-exact",
    )
    let run = local_compute_run(host)
    let before = @resources.ledger_usage(root)
    let occupied = @resources.reserve_capacity(
      root,
      100000L - before.reserved_retention_bytes - retained,
      100000L - before.reserved_execution_bytes - execution,
    ).unwrap()
    let base = @resources.ledger_usage(root)
    let result = @host.bind_client_logical_task_boundary(
      facts,
      original.compiled,
      original.prepared,
      run,
      source,
      1000,
    )
    if succeeds {
      guard result is Ok(Projected(value)) else { fail("exact quote refused") }
      assert_eq(
        @resources.ledger_usage(root).reserved_retention_bytes,
        base.reserved_retention_bytes + debit,
      )
      assert_eq(
        @resources.ledger_usage(root).reserved_execution_bytes,
        base.reserved_execution_bytes + debit,
      )
      @host.return_client_logical_task_boundary(value).unwrap()
    } else if retained < debit {
      assert_true(
        result is Err(Boundary(@strategy.Resource(@resources.RetentionLimit))),
      )
    } else {
      assert_true(
        result is Err(Boundary(@strategy.Resource(@resources.ExecutionLimit))),
      )
    }
    assert_eq(
      @resources.ledger_usage(root).live_reservations,
      base.live_reservations,
    )
    assert_eq(
      @resources.ledger_usage(root).reserved_retention_bytes,
      base.reserved_retention_bytes,
    )
    assert_eq(
      @resources.ledger_usage(root).reserved_execution_bytes,
      base.reserved_execution_bytes,
    )
    assert_true(@strategy.captured_task_boundary_current(run, source))
    @resources.settle_capacity(root, occupied).unwrap()
    @strategy.return_captured_task_boundary(source).unwrap()
    @strategy.stop_captured_dag(run)
    @strategy.refresh_captured_retention(run)
    assert_eq(@resources.ledger_usage(root).live_reservations, 0)
  }
}

///|
test "logical regrant invalidates owned forks without consuming the caller observation" {
  let root = capacity_boundary_root(100000L, 100000L)
  let (original, host, facts, source) = logical_capacity_fixture(
    root, "logical-failed-lookup",
  )
  let run = local_compute_run(host)
  let value = logical_capacity_bind(original, host, facts, source)
  @strategy.authorize_captured_task_activation(
    run,
    0,
    @strategy.task_activation_covered(),
  ).unwrap()
  assert_false(
    @host.client_logical_task_boundary_current(
      value,
      original.compiled,
      original.prepared,
    ),
  )
  assert_true(
    @host.bind_client_logical_task_boundary(
      facts,
      original.compiled,
      original.prepared,
      run,
      source,
      1000,
    )
    is Err(StaleBoundary),
  )
  @host.return_client_logical_task_boundary(value).unwrap()
  @strategy.return_captured_task_boundary(source).unwrap()
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  assert_eq(@resources.ledger_usage(root).live_reservations, 0)
}

///|
test "failed logical map bound returns only its own unused construction fork" {
  let program =
    #|{"version":"actql/0.1","id":"logical.bound.limit","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"n":{"type":"number","nullable":false}},"rows":[{"n":1}]},"as":"data"},{"from":"data","filter":"n > 0","as":"filtered"},{"from":"filtered","select":["n"],"as":"out"}],"results":{"rows":{"from":"out","fields":["n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  let root = capacity_boundary_root(100000L, 100000L)
  let (original, host, facts, source) = logical_capacity_fixture(
    root,
    "logical-map-bound",
    program~,
  )
  let run = local_compute_run(host)
  let before = @resources.ledger_usage(root)
  // This actual compiler map has three original operations, so max_nodes=1
  // fails AFTER the complete construction fork is acquired, before fusion.
  assert_true(
    @host.bind_client_logical_task_boundary(
      facts,
      original.compiled,
      original.prepared,
      run,
      source,
      1,
    )
    is Err(InvalidReadLimits),
  )
  assert_eq(
    @resources.ledger_usage(root).live_reservations,
    before.live_reservations,
  )
  assert_eq(
    @resources.ledger_usage(root).reserved_retention_bytes,
    before.reserved_retention_bytes,
  )
  assert_true(@strategy.captured_task_boundary_current(run, source))
  assert_true(
    @host.bind_client_logical_task_boundary(
      facts,
      original.compiled,
      original.prepared,
      run,
      source,
      1000,
    ).unwrap()
    is NotProjected(FusedPhysicalTask),
  )
  assert_eq(
    @resources.ledger_usage(root).live_reservations,
    before.live_reservations,
  )
  assert_eq(
    @resources.ledger_usage(root).reserved_execution_bytes,
    before.reserved_execution_bytes,
  )
  @strategy.return_captured_task_boundary(source).unwrap()
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  assert_eq(@resources.ledger_usage(root).live_reservations, 0)
}

///|
// Existing nominal Resource child issuance, with an explicit acquisition port.
// This component does not allocate a VM/OS pool or acknowledge physical return.
fn logical_callback_ledger(
  callback : () -> Unit,
) -> (@resources.Ledger, @resources.ImportedChildLedger) {
  let parent = capacity_boundary_root(100000L, 200000L)
  let capacity = @resources.reserve_shared_capacity(parent, 4096L).unwrap()
  let allocation = @resources.allocate_shared_capacity(capacity, 4096L).unwrap()
  let provider = Ref(1)
  let region : @resources.BackedExecutionRegion[Ref[Int], Ref[Int]] = @resources.issue_backed_execution_region(
    capacity, allocation, provider,
  ).unwrap()
  let child = Ref(2)
  let ticket = @resources.reserve_backed_execution_delegation(
    region,
    provider,
    child,
    { offset: 0L, length: 4096L, payload_offset: 8L, payload_length: 4088L, },
    @resources.ExclusiveWrite,
    {
      planning_work: 500,
      attempts: 4,
      holdings: 4,
      transfer_bytes: 0L,
      retained_bytes: 100000L,
      execution_bytes: 100000L,
    },
    5L,
    7L,
    initial_window=Some(4088L),
  ).unwrap()
  let read = @resources.borrow_backed_execution_read_use(
    region, provider, child, ticket,
  ).unwrap()
  let runtime = Ref(3)
  let access = @resources.issue_backed_execution_live_access(
    region, provider, child, ticket, read, runtime,
  ).unwrap()
  let projection = @resources.admit_backed_execution_live_child(access, runtime).unwrap()
  let initialization = @resources.prepare_backed_initialization_admission(
    projection,
    runtime,
    acquire_window=Some((_, _) => {
      callback()
      Err(@resources.ChildFundingUnavailable)
    }),
  ).unwrap()
  let frame = @resources.backed_initialization_original_frame(
    initialization, runtime,
  ).unwrap()
  @resources.start_imported_child_ledger(frame).unwrap()
  (@resources.take_imported_original_child_ledger(frame).unwrap(), frame)
}

///|
test "logical admission callback cannot return its pinned source or reenter fork issuance" {
  let action : Ref[(() -> Unit)?] = Ref(None)
  let (root, frame) = logical_callback_ledger(() => {
    if action.val is Some(callback) {
      callback()
    }
  })
  let (original, host, facts, source) = logical_capacity_fixture(
    root, "logical-admission-reentry",
  )
  let run = local_compute_run(host)
  let before = @resources.ledger_usage(root)
  let calls = Ref(0)
  let source_return : Ref[Result[Unit, @strategy.CapturedTaskBoundaryIssue]?] = Ref(
    None,
  )
  let nested : Ref[
    Result[@strategy.CapturedTaskBoundary, @strategy.CapturedTaskBoundaryIssue]?,
  ] = Ref(None)
  action.val = Some(() => {
    calls.val += 1
    source_return.val = Some(@strategy.return_captured_task_boundary(source))
    nested.val = Some(
      @strategy.fork_captured_task_boundary_for_logical_projection(run, source),
    )
  })
  assert_true(
    @host.bind_client_logical_task_boundary(
      facts,
      original.compiled,
      original.prepared,
      run,
      source,
      1000,
    )
    is Err(Boundary(@strategy.Resource(@resources.ChildFundingUnavailable))),
  )
  action.val = None
  assert_eq(calls.val, 1)
  assert_true(source_return.val is Some(Err(@strategy.ReadInProgress)))
  assert_true(nested.val is Some(Err(@strategy.ReadInProgress)))
  assert_true(@strategy.captured_task_boundary_current(run, source))
  assert_eq(
    @resources.ledger_usage(root).live_reservations,
    before.live_reservations,
  )
  assert_eq(
    @resources.ledger_usage(root).reserved_retention_bytes,
    before.reserved_retention_bytes,
  )
  assert_eq(
    @resources.ledger_usage(root).reserved_execution_bytes,
    before.reserved_execution_bytes,
  )
  @strategy.return_captured_task_boundary(source).unwrap()
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  assert_eq(@resources.ledger_usage(root).live_reservations, 0)
  // Logical child stop is not the physical parent/region retirement ACK.
  @resources.stop_imported_child_ledger(frame).unwrap()
}

///|
test "logical fork rejects foreign Run and returned source before acquiring another token" {
  let root = capacity_boundary_root(100000L, 100000L)
  let other_root = capacity_boundary_root(100000L, 100000L)
  let (original, host, facts, source) = logical_capacity_fixture(
    root, "logical-owner-a",
  )
  let (_, other, _, other_source) = logical_capacity_fixture(
    other_root, "logical-owner-b",
  )
  let run = local_compute_run(host)
  let other_run = local_compute_run(other)
  let before = @resources.ledger_usage(root)
  let other_before = @resources.ledger_usage(other_root)
  assert_true(
    @strategy.fork_captured_task_boundary_for_logical_projection(
      other_run, source,
    )
    is Err(StaleBoundary),
  )
  assert_true(
    @host.bind_client_logical_task_boundary(
      facts,
      original.compiled,
      original.prepared,
      run,
      source,
      0,
    )
    is Err(InvalidReadLimits),
  )
  assert_eq(@resources.ledger_usage(root), before)
  assert_eq(@resources.ledger_usage(other_root), other_before)
  @strategy.return_captured_task_boundary(source).unwrap()
  assert_true(
    @strategy.fork_captured_task_boundary_for_logical_projection(run, source)
    is Err(ReadReturned),
  )
  assert_eq(@resources.ledger_usage(root).live_reservations, 1)
  @strategy.return_captured_task_boundary(other_source).unwrap()
  @strategy.stop_captured_dag(run)
  @strategy.stop_captured_dag(other_run)
  @strategy.refresh_captured_retention(run)
  @strategy.refresh_captured_retention(other_run)
  assert_eq(@resources.ledger_usage(root).live_reservations, 0)
  assert_eq(@resources.ledger_usage(other_root).live_reservations, 0)
}
