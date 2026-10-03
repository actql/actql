///|
test "confirmed retention is bounded and never substitutes for completion or cleanup" {
  for amount in [-1L, 101L, 40L] {
    let (run, _) = captured_graph_fixture()
    let (_, choice, candidate) = synchronous_test_choice(run)
    let ledger = @strategy.captured_dag_ledger(run)
    let cleaned = Ref(false)
    let finishes = Ref(0)
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
          released: fn() {  },
          ready: fn() { Ok(()) },
        }
        Ok((payload, operations))
      },
      retained_bytes=fn() { Ok(amount) },
    ).unwrap()
    assert_true(
      @connector.prepared_execution_retained_bytes(prepared)
      is Err(Candidate(NotSelected)),
    )
    let (_, execution) = @strategy.start_captured_materializing_execution(
      run, 1, prepared,
    ).unwrap()
    @strategy.charge_task_execution_transfer(run, execution, 23L).unwrap()
    @strategy.settle_task_execution(run, execution, true).unwrap()
    let result = @strategy.complete_deferred_materializing_task_execution(
      run,
      execution,
      fn() {
        finishes.val += 1
        Err(MissingOutput)
      },
    )
    if amount == 40L {
      assert_true(result is Err(MissingOutput))
      assert_eq(finishes.val, 1)
      assert_eq(@resources.ledger_usage(ledger).held_bytes, 40L)
      assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 60L)
    } else {
      assert_true(result is Err(Compute(InvalidLimits)))
      assert_eq(finishes.val, 0)
      assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
      assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 100L)
    }
    assert_false(@strategy.captured_task_completed(run, 1))
    @strategy.close_task_execution(run, execution)
    let pending = @resources.ledger_usage(ledger)
    assert_eq(pending.held_bytes + pending.reserved_retention_bytes, 100L)
    assert_eq(pending.reserved_execution_bytes, 10L)
    @strategy.refresh_captured_retention(run)
    assert_eq(@resources.ledger_usage(ledger), pending)
    cleaned.val = true
    // The Host's late storage-refresh boundary must discharge the original
    // disposed execution too, without running its finisher or cleanup again.
    @strategy.refresh_captured_retention(run)
    let released = @resources.ledger_usage(ledger)
    assert_eq(released.reserved_execution_bytes, 0L)
    assert_true(
      @strategy.refresh_task_execution_cleanup(run, execution).unwrap(),
    )
    assert_eq(@resources.ledger_usage(ledger), released)
    @strategy.refresh_captured_retention(run)
    assert_eq(@resources.ledger_usage(ledger), released)
    assert_eq(finishes.val, if amount == 40L { 1 } else { 0 })
    assert_eq(released.held_bytes, 0L)
    assert_eq(released.reserved_retention_bytes, 0L)
    assert_eq(released.transferred_bytes, 23L)
  }
}

///|
test "prepared asynchronous execution reserves before calling installed payload" {
  let (run, _) = captured_graph_fixture()
  let (_, choice, candidate) = synchronous_test_choice(run)
  let ledger = @strategy.captured_dag_ledger(run)
  let calls = Ref(0)
  let cancelled = Ref(0)
  let disposed = Ref(0)
  let settled = Ref(0)
  let released = Ref(0)
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
      calls.val += 1
      let operations : @connector.ExecutionLifecycleOperations[
        @strategy.RunIssue,
      ] = {
        cancel: fn() { cancelled.val += 1 },
        dispose: fn() { disposed.val += 1 },
        settled: fn() { settled.val += 1 },
        scratch_released: fn() { true },
        retention_released: fn() { true },
        released: fn() { released.val += 1 },
        ready: fn() { Ok(()) },
      }
      Ok((payload, operations))
    },
  ).unwrap()
  let saturation = @resources.reserve_attempt(
    ledger, 300000L, 32000000L, 134217728L,
  ).unwrap()
  let full = @resources.ledger_usage(ledger)
  assert_true(
    @strategy.start_captured_materializing_execution(run, 1, prepared)
    is Err(Physical(_)),
  )
  assert_eq(@resources.ledger_usage(ledger), full)
  assert_eq(calls.val, 0)
  assert_true(@connector.prepared_execution_available(prepared))
  @resources.settle_reservation(ledger, saturation).unwrap()
  let (payload, execution) = @strategy.start_captured_materializing_execution(
    run, 1, prepared,
  ).unwrap()
  assert_eq(payload, 17)
  assert_eq(calls.val, 1)
  assert_false(@connector.prepared_execution_available(prepared))
  assert_true(
    @connector.start_prepared_execution_lifecycle(prepared)
    is Err(Candidate(NotSelected)),
  )
  @strategy.charge_task_execution_transfer(run, execution, 23L).unwrap()
  assert_true(
    @strategy.complete_deferred_materializing_task_execution(run, execution, fn() {
      Err(MissingOutput)
    })
    is Err(Physical(InvalidCharge)),
  )
  @strategy.close_task_execution(run, execution)
  @strategy.close_task_execution(run, execution)
  assert_eq(cancelled.val, 1)
  assert_eq(disposed.val, 1)
  assert_eq(released.val, 0)
  @strategy.settle_task_execution(run, execution, false).unwrap()
  let pending = @resources.ledger_usage(ledger)
  assert_eq(pending.reserved_execution_bytes, 100L)
  assert_eq(pending.reserved_retention_bytes, 100L)
  assert_eq(pending.transferred_bytes, 23L)
  @strategy.settle_task_execution(run, execution, true).unwrap()
  assert_eq(settled.val, 1)
  assert_eq(released.val, 1)
  let after = @resources.ledger_usage(ledger)
  assert_eq(after.reserved_execution_bytes, 0L)
  assert_eq(after.reserved_retention_bytes, 0L)
  assert_eq(after.transferred_bytes, 23L)
  assert_false(@strategy.captured_task_completed(run, 1))
}

///|
test "prepared execution rejects foreign task and revoked input without preparation" {
  let (run, issuer) = captured_graph_fixture()
  let (other, _) = captured_graph_fixture()
  let (_, choice, candidate) = synchronous_test_choice(run)
  let (_, foreign_choice, _) = synchronous_test_choice(other)
  let calls = Ref(0)
  let prepare = fn(
    _payload : Int,
  ) -> Result[
    (Int, @connector.ExecutionLifecycleOperations[@strategy.RunIssue]),
    @strategy.RunIssue,
  ] {
    calls.val += 1
    Err(MissingOutput)
  }
  let capacity : @connector.ExecutionCapacity = {
    transfer_bytes: 100L,
    retained_bytes: 100L,
    scratch_bytes: 10L,
    execution_bytes: 100L,
  }
  assert_true(
    @connector.bind_prepared_materializing_execution(
      foreign_choice,
      candidate,
      capacity,
      [],
      prepare,
    )
    is Err(NotSelected),
  )
  let prepared = @connector.bind_prepared_materializing_execution(
    choice,
    candidate,
    capacity,
    [],
    prepare,
  ).unwrap()
  let ledger = @strategy.captured_dag_ledger(other)
  let before = @resources.ledger_usage(ledger)
  assert_true(
    @strategy.start_captured_materializing_execution(other, 1, prepared)
    is Err(ForeignCandidate),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(@connector.prepared_execution_available(prepared))
  @mock.close_mock_query_issuer(issuer)
  assert_true(
    @strategy.start_captured_materializing_execution(run, 1, prepared)
    is Err(Compute(InputUnavailable)),
  )
  assert_eq(calls.val, 0)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_false(@connector.prepared_execution_available(prepared))
  assert_true(@strategy.next_captured_task(run) is None)
}

///|
test "prepared execution still rejects foreign completed output and keeps holding until close" {
  let (run, _) = captured_graph_fixture()
  let (other, _) = captured_graph_fixture()
  captured_graph_local(other, 1).unwrap()
  let foreign = @strategy.captured_task_output(other, 1, Step(1)).unwrap()
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
    fn(payload) {
      let operations : @connector.ExecutionLifecycleOperations[
        @strategy.RunIssue,
      ] = {
        cancel: fn() {  },
        dispose: fn() {  },
        settled: fn() {  },
        scratch_released: fn() { true },
        retention_released: fn() { true },
        released: fn() {  },
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
    @strategy.complete_materializing_task_execution(run, execution, foreign)
    is Err(ForeignCandidate),
  )
  assert_true(@strategy.captured_task_output(run, 1, Step(1)) is None)
  let ledger = @strategy.captured_dag_ledger(run)
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 40L)
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 60L)
  @strategy.close_task_execution(run, execution)
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
  assert_true(@strategy.captured_task_output(other, 1, Step(1)) is Some(_))
}
