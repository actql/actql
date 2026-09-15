///|
fn synchronous_test_choice(
  run : @strategy.CapturedDAG,
) -> (
  @connector.CapabilityRegistry,
  @connector.FixedComputeChoice,
  @connector.PreparedCompute[Int],
) {
  let input = @strategy.captured_task_input(run, 1, 100, 10000).unwrap()
  let request = @connector.prepare_fixed_compute_request([input], {
    contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
    max_rows: 100,
    max_value_bytes: 10000,
    common_fragment: None,
  }).unwrap()
  let registry = @connector.prepare_capability_registry(
    [{ name: "synchronous-test", acquisition: false, fixed_compute: true, }],
    1,
    100,
  ).unwrap()
  let prepared = @connector.bind_compute_candidate(
    @connector.capability_registration_at(registry, 0).unwrap(),
    request,
    17,
    1,
    [{ work_slots: [0], milliseconds: Some(1L), }],
    { transfer_bytes: Some(0L), retained_bytes: None, money_units: None, },
    100,
  ).unwrap()
  guard @connector.choose_fixed_compute_candidate(
      registry,
      request,
      [@connector.prepared_compute_candidate(prepared)],
      None,
      100,
    ).unwrap()
    is Proposed(choice) else {
    abort("expected finite synchronous choice")
  }
  (registry, choice, prepared)
}

///|
test "synchronous wiring binds exact payload and runs only after common reservation" {
  let (run, _) = captured_graph_fixture()
  let (_, choice, prepared) = synchronous_test_choice(run)
  let ledger = @strategy.captured_dag_ledger(run)
  let calls = Ref(0)
  let received = Ref(0)
  let compute = @connector.bind_synchronous_compute(
    choice,
    prepared,
    { retained_bytes: 100L, execution_bytes: 100L, },
    None,
    fn(payload) {
      calls.val += 1
      received.val = payload
      Err(Compute(ComputeUnsupported))
    },
  ).unwrap()
  assert_eq(calls.val, 0)
  let saturation = @resources.reserve_attempt(ledger, 0L, 32000000L, 134217728L).unwrap()
  let full = @resources.ledger_usage(ledger)
  assert_true(
    @strategy.execute_captured_synchronous_task(run, 1, compute)
    is Err(Physical(_)),
  )
  assert_eq(@resources.ledger_usage(ledger), full)
  assert_eq(calls.val, 0)
  assert_true(@connector.synchronous_compute_available(compute))
  @resources.settle_reservation(ledger, saturation).unwrap()
  assert_true(
    @strategy.execute_captured_synchronous_task(run, 1, compute)
    is Err(Compute(ComputeUnsupported)),
  )
  assert_eq(calls.val, 1)
  assert_eq(received.val, 17)
  assert_false(@connector.synchronous_compute_available(compute))
  assert_true(
    @connector.execute_synchronous_compute(compute) is Err(Compute(NotSelected)),
  )
  assert_eq(calls.val, 1)
  let after = @resources.ledger_usage(ledger)
  assert_eq(after.held_bytes, 0L)
  assert_eq(after.reserved_execution_bytes, 0L)
  assert_eq(after.reserved_retention_bytes, 0L)
  assert_eq(after.transferred_bytes, 0L)
  assert_false(@strategy.captured_task_completed(run, 1))
}

///|
test "synchronous connector cannot publish another owner's completed output" {
  let (run, _) = captured_graph_fixture()
  let (other, _) = captured_graph_fixture()
  captured_graph_local(other, 1).unwrap()
  let foreign = @strategy.captured_task_output(other, 1, Step(1)).unwrap()
  let (_, choice, prepared) = synchronous_test_choice(run)
  let compute = @connector.bind_synchronous_compute(
    choice,
    prepared,
    { retained_bytes: 100L, execution_bytes: 100L, },
    None,
    _ => Ok(foreign),
  ).unwrap()
  assert_true(
    @strategy.execute_captured_synchronous_task(run, 1, compute)
    is Err(MissingOutput),
  )
  assert_true(@strategy.captured_task_output(run, 1, Step(1)) is None)
  assert_false(@strategy.captured_task_completed(run, 1))
  assert_true(@strategy.captured_task_output(other, 1, Step(1)) is Some(_))
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
}

///|
test "synchronous start rejects input revoked after preparation without invoking implementation" {
  let (run, issuer) = captured_graph_fixture()
  let (_, choice, prepared) = synchronous_test_choice(run)
  let calls = Ref(0)
  let compute = @connector.bind_synchronous_compute(
    choice,
    prepared,
    { retained_bytes: 100L, execution_bytes: 100L, },
    None,
    fn(_payload) {
      calls.val += 1
      Err(MissingOutput)
    },
  ).unwrap()
  @planning.close_mock_query_issuer(issuer)
  assert_true(
    @strategy.execute_captured_synchronous_task(run, 1, compute)
    is Err(Compute(InputUnavailable)),
  )
  assert_eq(calls.val, 0)
  assert_false(@connector.synchronous_compute_available(compute))
  assert_true(@strategy.captured_task_output(run, 1, Step(1)) is None)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.attempts, 1)
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
}

///|
test "synchronous preparations reject exchanged choice and closed implementation" {
  let (run, _) = captured_graph_fixture()
  let (other, _) = captured_graph_fixture()
  let (registry, choice, prepared) = synchronous_test_choice(run)
  let (_, foreign_choice, _) = synchronous_test_choice(other)
  let calls = Ref(0)
  let invoke = fn(_payload) {
    calls.val += 1
    Err(@connector.SynchronousComputeFailure::MissingOutput)
  }
  let capacity : @connector.SynchronousComputeCapacity = {
    retained_bytes: 1L,
    execution_bytes: 1L,
  }
  assert_true(
    @connector.bind_synchronous_compute(
      foreign_choice,
      prepared,
      capacity,
      None,
      invoke,
    )
    is Err(NotSelected),
  )
  assert_true(
    @connector.bind_synchronous_compute(
      choice,
      prepared,
      { retained_bytes: -1L, execution_bytes: 1L, },
      None,
      invoke,
    )
    is Err(InvalidLimits),
  )
  let compute = @connector.bind_synchronous_compute(
    choice,
    prepared,
    capacity,
    None,
    invoke,
  ).unwrap()
  let before = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  @connector.close_capability_registry(registry)
  assert_true(
    @strategy.execute_captured_synchronous_task(run, 1, compute)
    is Err(Compute(NotSelected)),
  )
  assert_eq(@resources.ledger_usage(@strategy.captured_dag_ledger(run)), before)
  assert_eq(calls.val, 0)
}
