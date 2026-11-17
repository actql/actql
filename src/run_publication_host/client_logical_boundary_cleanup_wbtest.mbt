///|
// Existing nominal Resource originals and acquisition callback. These are
// logical-owner components, not VM acquisition or physical-parent ACK evidence.
fn logical_cleanup_ledger(
  callback : () -> Unit,
  initial_payload? : Int64 = 20000L,
  acquired_payload? : Int64 = 0L,
) -> (@resources.Ledger, @resources.ImportedChildLedger) {
  let parent = @resources.create_ledger({
    planning_work: 1000,
    attempts: 10,
    holdings: 10,
    transfer_bytes: 0L,
    retained_bytes: 100000L,
    execution_bytes: 200000L,
  }).unwrap()
  let capacity = @resources.reserve_shared_capacity(
    parent,
    initial_payload + 520L,
  ).unwrap()
  let allocation = @resources.allocate_shared_capacity(
    capacity,
    initial_payload + 8L,
  ).unwrap()
  let control = @resources.allocate_shared_capacity(capacity, 512L).unwrap()
  let provider = Ref(1)
  let region : @resources.BackedExecutionRegion[Ref[Int], Ref[Int]] = @resources.issue_backed_execution_region(
    capacity, allocation, provider,
  ).unwrap()
  let child = Ref(2)
  let ticket = @resources.reserve_backed_execution_delegation(
    region,
    provider,
    child,
    {
      offset: 0L,
      length: initial_payload + 8L,
      payload_offset: 8L,
      payload_length: initial_payload,
    },
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
    initial_window=Some(initial_payload),
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
      if acquired_payload == 0L {
        return Err(@resources.ChildFundingUnavailable)
      }
      // Explicit component acquisition receipt through the existing Owner.
      // No VM/OS allocation or physical ACK is inferred from this fixture.
      let growth = match
        @resources.begin_shared_capacity_growth(
          capacity,
          control,
          initial_payload + 520L + acquired_payload,
          acquired_payload,
        ) {
        Err(issue) => return Err(issue)
        Ok(value) => value
      }
      @resources.complete_backed_original_child_window_after_acquisition(
        projection, runtime, growth, acquired_payload,
      ).map_err(_ => @resources.ChildFundingUnavailable)
    }),
  ).unwrap()
  let frame = @resources.backed_initialization_original_frame(
    initialization, runtime,
  ).unwrap()
  @resources.start_imported_child_ledger(frame).unwrap()
  (@resources.take_imported_original_child_ledger(frame).unwrap(), frame)
}

///|
test "declined logical return disposes higher context before autonomous original token refund" {
  let action : Ref[(() -> Unit)?] = Ref(None)
  let (ledger, frame) = logical_cleanup_ledger(() => {
    if action.val is Some(callback) {
      callback()
    }
  })
  let (prepared, compiled, _) = local_values_invocation_fixture(false)
  let graph = prepared_client_graph(prepared)
  let run = @strategy.open_source_free_dag(graph, ledger).unwrap()
  let hooks = @strategy.prepare_captured_task_boundary_hooks(run, graph, 0).unwrap()
  @strategy.authorize_captured_task_activation(
    run,
    0,
    @strategy.task_activation_covered(),
  ).unwrap()
  let source = @strategy.read_captured_task_boundary(run, hooks, Before)
    .unwrap()
    .unwrap()
  let facts = capture_client_structural_explanation_original(
    compiled, prepared, 1000000, 100000, 100,
  ).unwrap()
  guard bind_client_logical_task_boundary(
      facts, compiled, prepared, run, source, 1000,
    ).unwrap()
    is Projected(value) else {
    fail("missing genuine original logical boundary")
  }
  let before = @resources.ledger_usage(ledger)
  let returned : Ref[Result[Unit, ClientLogicalTaskBoundaryIssue]?] = Ref(None)
  let calls = Ref(0)
  action.val = Some(() => {
    calls.val += 1
    // SAME Resource owner is inside actual acquisition. Its existing mutation
    // fence declines this settlement; no injected return result is supplied.
    returned.val = Some(return_client_logical_task_boundary(value))
  })
  assert_true(
    bind_client_logical_task_boundary(
      facts, compiled, prepared, run, source, 1000,
    )
    is Err(Boundary(@strategy.Resource(@resources.ChildFundingUnavailable))),
  )
  action.val = None
  assert_eq(calls.val, 1)
  assert_true(
    returned.val
    is Some(
      Err(Boundary(@strategy.Resource(@resources.ChildFundingUnavailable)))
    ),
  )
  assert_eq(
    @resources.ledger_usage(ledger).live_reservations,
    before.live_reservations,
  )
  assert_eq(
    @resources.ledger_usage(ledger).reserved_retention_bytes,
    before.reserved_retention_bytes,
  )
  assert_true(@strategy.captured_task_boundary_cleanup_pending(run))
  assert_true(@strategy.captured_task_boundary_current(run, source))
  @strategy.refresh_captured_retention(run)
  assert_eq(
    @resources.ledger_usage(ledger).live_reservations,
    before.live_reservations - 1,
  )
  assert_true(
    @resources.ledger_usage(ledger).reserved_retention_bytes <
    before.reserved_retention_bytes,
  )
  // Keep the higher handle alive WITHOUT another logical return. Its actual
  // newly allocated context must no longer hold facts/Run/step after refund.
  assert_true(value.original is None)
  assert_false(client_logical_task_boundary_current(value, compiled, prepared))
  return_client_logical_task_boundary(value).unwrap()
  return_client_logical_task_boundary(value).unwrap()
  assert_eq(
    @resources.ledger_usage(ledger).live_reservations,
    before.live_reservations - 1,
  )
  @strategy.return_captured_task_boundary(source).unwrap()
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  @resources.stop_imported_child_ledger(frame).unwrap()
}

///|
test "successful original acquisition invalidating the latest fact returns only the undelivered fork" {
  let action : Ref[(() -> Unit)?] = Ref(None)
  let (ledger, frame) = logical_cleanup_ledger(
    () => if action.val is Some(callback) { callback() },
    initial_payload=4000L,
    acquired_payload=30000L,
  )
  let (prepared, compiled, _) = local_values_invocation_fixture(false)
  let graph = prepared_client_graph(prepared)
  let run = @strategy.open_source_free_dag(graph, ledger).unwrap()
  let hooks = @strategy.prepare_captured_task_boundary_hooks(run, graph, 0).unwrap()
  @strategy.authorize_captured_task_activation(
    run,
    0,
    @strategy.task_activation_covered(),
  ).unwrap()
  let source = @strategy.read_captured_task_boundary(run, hooks, Before)
    .unwrap()
    .unwrap()
  let facts = capture_client_structural_explanation_original(
    compiled, prepared, 1000000, 100000, 100,
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  let calls = Ref(0)
  let regrant : Ref[Result[Unit, @strategy.RunIssue]?] = Ref(None)
  action.val = Some(() => {
    calls.val += 1
    regrant.val = Some(
      @strategy.authorize_captured_task_activation(
        run,
        0,
        @strategy.task_activation_covered(),
      ),
    )
  })
  assert_true(
    bind_client_logical_task_boundary(
      facts, compiled, prepared, run, source, 1000,
    )
    is Err(Boundary(@strategy.StaleBoundary)),
  )
  action.val = None
  assert_eq(calls.val, 1)
  assert_true(regrant.val is Some(Ok(_)))
  let after = @resources.ledger_usage(ledger)
  // A real new fork debit existed after the nominal acquisition; the same
  // original Owner returned it after the latest-record identity changed.
  assert_true(after.peak_retention_bytes > before.peak_retention_bytes)
  assert_eq(after.live_reservations, before.live_reservations)
  assert_eq(after.reserved_retention_bytes, before.reserved_retention_bytes)
  assert_eq(after.reserved_execution_bytes, before.reserved_execution_bytes)
  assert_false(@strategy.captured_task_boundary_current(run, source))
  let current = @strategy.read_captured_task_boundary(run, hooks, Before)
    .unwrap()
    .unwrap()
  guard bind_client_logical_task_boundary(
      facts, compiled, prepared, run, current, 1000,
    ).unwrap()
    is Projected(value) else {
    fail("new latest original must remain usable")
  }
  assert_eq(calls.val, 1)
  return_client_logical_task_boundary(value).unwrap()
  @strategy.return_captured_task_boundary(source).unwrap()
  @strategy.return_captured_task_boundary(current).unwrap()
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  @resources.stop_imported_child_ledger(frame).unwrap()
}

///|
test "pending logical cleanup retries keep exact token and leave sibling original forks current" {
  let action : Ref[(() -> Unit)?] = Ref(None)
  let (ledger, frame) = logical_cleanup_ledger(
    () => if action.val is Some(callback) { callback() },
    initial_payload=30000L,
  )
  let (prepared, compiled, _) = local_values_invocation_fixture(false)
  let graph = prepared_client_graph(prepared)
  let run = @strategy.open_source_free_dag(graph, ledger).unwrap()
  let hooks = @strategy.prepare_captured_task_boundary_hooks(run, graph, 0).unwrap()
  @strategy.authorize_captured_task_activation(
    run,
    0,
    @strategy.task_activation_covered(),
  ).unwrap()
  let source = @strategy.read_captured_task_boundary(run, hooks, Before)
    .unwrap()
    .unwrap()
  let facts = capture_client_structural_explanation_original(
    compiled, prepared, 1000000, 100000, 100,
  ).unwrap()
  guard bind_client_logical_task_boundary(
      facts, compiled, prepared, run, source, 1000,
    ).unwrap()
    is Projected(sibling) else {
    fail("missing original sibling")
  }
  guard bind_client_logical_task_boundary(
      facts, compiled, prepared, run, source, 1000,
    ).unwrap()
    is Projected(value) else {
    fail("missing original target")
  }
  let original_token = value.cleanup
  let before = @resources.ledger_usage(ledger)
  let first : Ref[Result[Unit, ClientLogicalTaskBoundaryIssue]?] = Ref(None)
  let retry : Ref[Result[Unit, ClientLogicalTaskBoundaryIssue]?] = Ref(None)
  action.val = Some(() => {
    first.val = Some(return_client_logical_task_boundary(value))
    retry.val = Some(return_client_logical_task_boundary(value))
  })
  assert_true(
    bind_client_logical_task_boundary(
      facts, compiled, prepared, run, source, 1000,
    )
    is Err(Boundary(@strategy.Resource(@resources.ChildFundingUnavailable))),
  )
  action.val = None
  assert_true(
    first.val
    is Some(
      Err(Boundary(@strategy.Resource(@resources.ChildFundingUnavailable)))
    ),
  )
  assert_true(
    retry.val
    is Some(
      Err(Boundary(@strategy.Resource(@resources.ChildFundingUnavailable)))
    ),
  )
  assert_true(value.original is None)
  assert_true(physical_equal(value.cleanup, original_token))
  assert_eq(
    @resources.ledger_usage(ledger).live_reservations,
    before.live_reservations,
  )
  assert_true(client_logical_task_boundary_current(sibling, compiled, prepared))
  @strategy.refresh_captured_retention(run)
  assert_eq(
    @resources.ledger_usage(ledger).live_reservations,
    before.live_reservations - 1,
  )
  assert_true(physical_equal(value.cleanup, original_token))
  assert_true(
    @strategy.return_captured_task_boundary(original_token) is Err(ReadReturned),
  )
  assert_true(value.original is None)
  return_client_logical_task_boundary(value).unwrap()
  return_client_logical_task_boundary(value).unwrap()
  assert_true(client_logical_task_boundary_current(sibling, compiled, prepared))
  assert_true(@strategy.captured_task_boundary_current(run, source))
  return_client_logical_task_boundary(sibling).unwrap()
  @strategy.return_captured_task_boundary(source).unwrap()
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  @resources.stop_imported_child_ledger(frame).unwrap()
}
