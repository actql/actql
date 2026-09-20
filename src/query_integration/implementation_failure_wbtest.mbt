///|
suberror IndependentPreparationFailure {
  Refused(Int)
}

///|
test "common execution preserves independent connector errors and releases unstarted reservations" {
  let (run, _) = captured_graph_fixture()
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
    fn(
      _payload,
    ) -> Result[
      (Unit, @connector.ExecutionLifecycleOperations[@strategy.RunIssue]),
      @strategy.RunIssue,
    ] {
      Err(Implementation(IndependentPreparationFailure::Refused(37)))
    },
  ).unwrap()
  let ledger = @strategy.captured_dag_ledger(run)
  let before = @resources.ledger_usage(ledger)
  guard @strategy.start_captured_materializing_execution(run, 1, prepared)
    is Err(Implementation(error)) else {
    fail("expected the independent implementation failure")
  }
  let code = try {
    raise error
  } catch {
    IndependentPreparationFailure::Refused(code) => code
    _ => -1
  }
  assert_eq(code, 37)
  guard @strategy.captured_dag_failure(run)
    is Some((1, Implementation(recorded))) else {
    fail("missing task failure")
  }
  assert_true(physical_equal(error, recorded))
  assert_true(@strategy.next_captured_task(run) is None)
  assert_false(@strategy.captured_task_completed(run, 1))
  let after = @resources.ledger_usage(ledger)
  assert_eq(after.attempts, before.attempts + 1)
  assert_eq(after.transferred_bytes, before.transferred_bytes)
  assert_eq(after.reserved_transfer_bytes, before.reserved_transfer_bytes)
  assert_eq(after.reserved_retention_bytes, before.reserved_retention_bytes)
  assert_eq(after.reserved_execution_bytes, before.reserved_execution_bytes)
}
