///|
fn materializing_funded_growth_fixture(
  cleaned : Ref[Bool],
  ledger? : @resources.Ledger? = None,
) -> (
  @strategy.CapturedDAG,
  @connector.PreparedExecution[Int, @strategy.RunIssue],
  @strategy.TaskExecution,
) raise {
  let (run, _) = captured_graph_fixture(original_ledger=ledger)
  let (_, choice, candidate) = synchronous_test_choice(run)
  let prepared = @connector.bind_prepared_materializing_execution(
    choice,
    candidate,
    {
      transfer_bytes: 100L,
      retained_bytes: 100L,
      scratch_bytes: 10L,
      execution_bytes: 100L,
    },
    [],
    payload => {
      Ok(
        (
          payload,
          {
            cancel: () => (),
            dispose: () => (),
            settled: () => (),
            scratch_released: () => cleaned.val,
            retention_released: () => cleaned.val,
            released: () => (),
            ready: () => Ok(()),
          },
        ),
      )
    },
  ).unwrap()
  let (_, ticket) = @strategy.start_captured_materializing_execution(
    run, 1, prepared,
  ).unwrap()
  (run, prepared, ticket)
}

///|
test "materializing output keeps only its same physically funded retention through completion" {
  let cleaned = Ref(false)
  let (run, prepared, ticket) = materializing_funded_growth_fixture(cleaned)
  let (foreign, _) = captured_graph_fixture()
  let ledger = @strategy.captured_dag_ledger(run)
  let before = @resources.ledger_usage(ledger)
  assert_true(
    @strategy.retain_materializing_task_execution_capacity(foreign, ticket)
    is Err(ForeignOwner),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  @strategy.retain_materializing_task_execution_capacity(run, ticket).unwrap()
  @strategy.retain_materializing_task_execution_capacity(run, ticket).unwrap()
  assert_eq(@resources.ledger_usage(ledger), before)
  @strategy.grow_task_execution_workspace(
    run,
    ticket,
    100L,
    retained=Some(180L),
  ).unwrap()
  // The generic prepared-constructor guard is unchanged. Only this exact
  // physical task's completion observes its own successfully grown backing.
  assert_eq(
    @connector.prepared_execution_retained_bytes(prepared).unwrap(),
    100L,
  )
  @strategy.settle_task_execution(run, ticket, true).unwrap()
  assert_true(
    @strategy.complete_deferred_materializing_task_execution(run, ticket, () => {
      Err(MissingOutput)
    })
    is Err(MissingOutput),
  )
  let held = @resources.ledger_usage(ledger)
  assert_eq(held.held_bytes, 180L)
  assert_eq(held.reserved_retention_bytes, 0L)
  @strategy.close_task_execution(run, ticket)
  assert_true(
    @strategy.retain_materializing_task_execution_capacity(run, ticket)
    is Err(ClosedReservation),
  )
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 180L)
  cleaned.val = true
  assert_true(@strategy.refresh_task_execution_cleanup(run, ticket).unwrap())
  @strategy.refresh_captured_retention(run)
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
test "refused materializing growth cannot become retained output or erase its initial prefix" {
  let cleaned = Ref(false)
  let (run, _, ticket) = materializing_funded_growth_fixture(cleaned)
  let ledger = @strategy.captured_dag_ledger(run)
  @strategy.retain_materializing_task_execution_capacity(run, ticket).unwrap()
  let limits = @resources.ledger_admission_limits(ledger)
  let usage = @resources.ledger_usage(ledger)
  let pressure = @resources.reserve_capacity(
    ledger,
    0L,
    limits.execution_bytes - usage.reserved_execution_bytes - 50L,
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    @strategy.grow_task_execution_workspace(
      run,
      ticket,
      100L,
      retained=Some(180L),
    )
    is Err(ExecutionLimit),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  @resources.settle_capacity(ledger, pressure).unwrap()
  @strategy.settle_task_execution(run, ticket, true).unwrap()
  assert_true(
    @strategy.complete_deferred_materializing_task_execution(run, ticket, () => {
      Err(MissingOutput)
    })
    is Err(MissingOutput),
  )
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 100L)
  @strategy.close_task_execution(run, ticket)
  cleaned.val = true
  assert_true(@strategy.refresh_task_execution_cleanup(run, ticket).unwrap())
  @strategy.refresh_captured_retention(run)
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
#cfg(target="js")
test "materializing growth keeps the original current callback and cancellation prefix" {
  let current : Ref[(() -> Unit)?] = Ref(None)
  let original = Ref(1)
  let root = cleanup_original_root(
    cleanup_create_loader(cleanup_test_url()),
    original,
    () => if current.val is Some(action) { action() },
  )
  let ledger = @resources.start_node_managed_run_admission(
    @resources.prepare_node_managed_run_admission(root, original).unwrap(),
  ).unwrap()
  let cleaned = Ref(false)
  let (run, _, ticket) = materializing_funded_growth_fixture(
    cleaned,
    ledger=Some(ledger),
  )
  @strategy.retain_materializing_task_execution_capacity(run, ticket).unwrap()
  let reentered = Ref(false)
  current.val = Some(() => {
    current.val = None
    reentered.val = @strategy.retain_materializing_task_execution_capacity(
        run, ticket,
      )
      is Ok(_)
    @strategy.stop_captured_dag(run)
  })
  assert_true(
    @strategy.grow_task_execution_workspace(
      run,
      ticket,
      100L,
      retained=Some(180L),
    )
    is Err(ClosedReservation),
  )
  assert_true(reentered.val)
  assert_true(
    @strategy.retain_materializing_task_execution_capacity(run, ticket)
    is Err(ClosedReservation),
  )
  let prefix = @resources.ledger_usage(ledger)
  assert_true(prefix.reserved_retention_bytes >= 100L)
  assert_true(prefix.reserved_execution_bytes >= 100L)
  cleaned.val = true
  @strategy.settle_task_execution(run, ticket, true).unwrap()
  @strategy.close_task_execution(run, ticket)
  @strategy.refresh_captured_retention(run)
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}
