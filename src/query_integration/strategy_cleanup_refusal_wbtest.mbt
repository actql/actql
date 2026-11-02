///|
// Actual Common
// park/refusal, actual Strategy task; the installed payload is deterministic.
test "real Common park preserves disposed Strategy cleanup custody" {
  let (run, _) = captured_graph_fixture()
  let ledger = @strategy.captured_dag_ledger(run)
  let bootstrap = @resources.reserve_capacity(ledger, 1024L, 1024L).unwrap()
  let identity = @resources.begin_original_ledger_inventory(
    ledger, bootstrap, 16, 16, 0,
  ).unwrap()
  let (_, choice, candidate) = synchronous_test_choice(run)
  let cleaned = Ref(false)
  let releases = Ref(0)
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
    fn(payload) {
      let operations : @connector.ExecutionLifecycleOperations[
        @strategy.RunIssue,
      ] = {
        cancel: fn() {  },
        dispose: fn() {  },
        settled: fn() {  },
        scratch_released: fn() { cleaned.val },
        retention_released: fn() { cleaned.val },
        released: fn() { releases.val += 1 },
        ready: fn() { Ok(()) },
      }
      Ok((payload, operations))
    },
    retained_bytes=fn() { Ok(40L) },
  ).unwrap()
  let (_, execution) = @strategy.start_captured_materializing_execution(
    run, 1, prepared,
  ).unwrap()
  @strategy.settle_task_execution(run, execution, true).unwrap()
  assert_true(
    @strategy.complete_deferred_materializing_task_execution(run, execution, fn() {
      Err(MissingOutput)
    })
    is Err(MissingOutput),
  )
  @strategy.close_task_execution(run, execution)
  assert_false(
    @strategy.refresh_task_execution_cleanup(run, execution).unwrap(),
  )
  let origin = Ref(7)
  let descriptor = @resources.issue_recorded_original_ledger_descriptor(
    identity, origin,
  ).unwrap()
  let claim = @resources.fund_original_read(ledger, origin, descriptor, 7L, 5L).unwrap()
  let consumer = @resources.claim_funded_read_preparation(claim, origin, 7L, 5L).unwrap()
  @resources.enter_funded_read_consumer(consumer, origin, 7L, 5L).unwrap()
  let park = @resources.park_original_resource_consumer(consumer, origin).unwrap()
  assert_true(
    @resources.original_resource_park_current_for_ledger(park, ledger)
    is Some(_),
  )
  let before = @resources.ledger_usage(ledger)
  assert_true(before.held_bytes > 0L)
  cleaned.val = true
  let acknowledged = @strategy.refresh_task_execution_cleanup(run, execution)
  let after = @resources.ledger_usage(ledger)
  assert_eq(after, before)
  assert_eq(releases.val, 0)
  assert_true(
    @strategy.refresh_task_execution_cleanup(run, execution)
    is Err(ResourceParked),
  )
  assert_true(acknowledged is Err(ResourceParked))
}

///|
test "Strategy retention refuses only its own holding and does not repeat a released sibling" {
  let (first, _) = captured_graph_fixture()
  let ledger = @strategy.captured_dag_ledger(first)
  let bootstrap = @resources.reserve_capacity(ledger, 1024L, 1024L).unwrap()
  let identity = @resources.begin_original_ledger_inventory(
    ledger, bootstrap, 16, 16, 0,
  ).unwrap()
  let (second, _) = captured_graph_fixture(original_ledger=Some(ledger))
  let (live, _) = captured_graph_fixture(original_ledger=Some(ledger))
  let first_checks = Ref(0)
  let second_checks = Ref(0)
  for
    (run, checks, bytes) in [
      (first, first_checks, 10L),
      (second, second_checks, 20L),
      (live, Ref(0), 30L),
    ] {
    let token = @resources.reserve_attempt(ledger, 0L, bytes, 0L).unwrap()
    let holding = @resources.retain_allocation(ledger, token, bytes).unwrap()
    @resources.settle_reservation(ledger, token).unwrap()
    @strategy.retain_captured_task_allocation(run, 0, holding, release_confirmed=() => {
      checks.val += 1
      true
    }).unwrap()
  }
  @strategy.close_captured_task_output(first, 0)
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 50L)
  let first_completed_checks = first_checks.val
  let origin = Ref(7)
  let descriptor = @resources.issue_recorded_original_ledger_descriptor(
    identity, origin,
  ).unwrap()
  let claim = @resources.fund_original_read(ledger, origin, descriptor, 7L, 5L).unwrap()
  let consumer = @resources.claim_funded_read_preparation(claim, origin, 7L, 5L).unwrap()
  @resources.enter_funded_read_consumer(consumer, origin, 7L, 5L).unwrap()
  @resources.park_original_resource_consumer(consumer, origin).unwrap()
  |> ignore
  @strategy.close_captured_task_output(second, 0)
  let failed_checks = second_checks.val
  assert_true(failed_checks > 0)
  @strategy.refresh_captured_retention(first)
  @strategy.refresh_captured_retention(second)
  assert_eq(first_checks.val, first_completed_checks)
  assert_true(
    second_checks.val > failed_checks,
    msg="the refused original must remain reachable for later observation",
  )
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 50L)
  assert_eq(@resources.ledger_usage(ledger).holdings, 2)
  assert_true(@strategy.captured_task_input(live, 1, 100, 10000) is Ok(_))
}

///|
test "Strategy cleanup releases once with reentrant predicates and completion observation" {
  let (run, _) = captured_graph_fixture()
  let ledger = @strategy.captured_dag_ledger(run)
  let (_, choice, candidate) = synchronous_test_choice(run)
  let cleaned = Ref(false)
  let releases = Ref(0)
  let original : Ref[@strategy.TaskExecution?] = Ref(None)
  let nested_pending = Ref(false)
  let released_current = Ref(false)
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
    fn(payload) {
      let operations : @connector.ExecutionLifecycleOperations[
        @strategy.RunIssue,
      ] = {
        cancel: fn() {  },
        dispose: fn() {  },
        settled: fn() {  },
        scratch_released: () => {
          if cleaned.val && original.val is Some(execution) {
            nested_pending.val = @strategy.refresh_task_execution_cleanup(
                run, execution,
              )
              is Ok(false)
          }
          cleaned.val
        },
        retention_released: () => cleaned.val,
        released: () => {
          releases.val += 1
          released_current.val = @strategy.refresh_task_execution_cleanup(
              run,
              original.val.unwrap(),
            )
            is Ok(true)
        },
        ready: () => Ok(()),
      }
      Ok((payload, operations))
    },
    retained_bytes=() => Ok(40L),
  ).unwrap()
  let (_, execution) = @strategy.start_captured_materializing_execution(
    run, 1, prepared,
  ).unwrap()
  original.val = Some(execution)
  @strategy.charge_task_execution_transfer(run, execution, 23L).unwrap()
  @strategy.settle_task_execution(run, execution, true).unwrap()
  assert_true(
    @strategy.complete_deferred_materializing_task_execution(run, execution, () => {
      Err(MissingOutput)
    })
    is Err(MissingOutput),
  )
  @strategy.close_task_execution(run, execution)
  assert_false(
    @strategy.refresh_task_execution_cleanup(run, execution).unwrap(),
  )
  cleaned.val = true
  assert_true(@strategy.refresh_task_execution_cleanup(run, execution).unwrap())
  assert_true(nested_pending.val)
  assert_true(released_current.val)
  assert_eq(releases.val, 1)
  let completed = @resources.ledger_usage(ledger)
  assert_eq(completed.holdings, 0)
  assert_eq(completed.live_reservations, 0)
  assert_eq(completed.transferred_bytes, 23L)
  assert_true(@strategy.refresh_task_execution_cleanup(run, execution).unwrap())
  @strategy.refresh_captured_retention(run)
  assert_eq(releases.val, 1)
  assert_eq(@resources.ledger_usage(ledger), completed)
}

///|
test "Strategy Unit close preserves accounting refusal beside original execution failure" {
  let (run, _) = captured_graph_fixture()
  let ledger = @strategy.captured_dag_ledger(run)
  let bootstrap = @resources.reserve_capacity(ledger, 1024L, 1024L).unwrap()
  let identity = @resources.begin_original_ledger_inventory(
    ledger, bootstrap, 16, 16, 0,
  ).unwrap()
  let (_, choice, candidate) = synchronous_test_choice(run)
  let cleaned = Ref(false)
  let releases = Ref(0)
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
    fn(payload) {
      let operations : @connector.ExecutionLifecycleOperations[
        @strategy.RunIssue,
      ] = {
        cancel: fn() {  },
        dispose: fn() {  },
        settled: fn() {  },
        scratch_released: fn() { cleaned.val },
        retention_released: fn() { cleaned.val },
        released: fn() { releases.val += 1 },
        ready: fn() { Ok(()) },
      }
      Ok((payload, operations))
    },
    retained_bytes=fn() { Ok(40L) },
  ).unwrap()
  let (_, execution) = @strategy.start_captured_materializing_execution(
    run, 1, prepared,
  ).unwrap()
  @strategy.settle_task_execution(run, execution, true).unwrap()
  assert_true(
    @strategy.complete_deferred_materializing_task_execution(run, execution, fn() {
      Err(MissingOutput)
    })
    is Err(MissingOutput),
  )
  let origin = Ref(7)
  let descriptor = @resources.issue_recorded_original_ledger_descriptor(
    identity, origin,
  ).unwrap()
  let claim = @resources.fund_original_read(ledger, origin, descriptor, 7L, 5L).unwrap()
  let consumer = @resources.claim_funded_read_preparation(claim, origin, 7L, 5L).unwrap()
  @resources.enter_funded_read_consumer(consumer, origin, 7L, 5L).unwrap()
  let park = @resources.park_original_resource_consumer(consumer, origin).unwrap()
  assert_true(
    @resources.original_resource_park_current_for_ledger(park, ledger)
    is Some(_),
  )
  let before = @resources.ledger_usage(ledger)
  assert_true(before.held_bytes > 0L)
  cleaned.val = true
  @strategy.close_task_execution(run, execution)
  // Unit close cannot return this refusal. The same owner retains it even if
  // the next physical observation is pending rather than another ledger call.
  cleaned.val = false
  let acknowledged = @strategy.refresh_task_execution_cleanup(run, execution)
  let after = @resources.ledger_usage(ledger)
  assert_eq(after, before)
  assert_true(@strategy.captured_dag_failure(run) is Some((1, MissingOutput)))
  assert_eq(releases.val, 0)
  assert_true(
    @strategy.refresh_task_execution_cleanup(run, execution)
    is Err(ResourceParked),
  )
  assert_true(acknowledged is Err(ResourceParked))
}
