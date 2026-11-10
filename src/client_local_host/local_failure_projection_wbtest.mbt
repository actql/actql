///|
priv suberror LocalProjectionTestFailure {
  Marker(Ref[Int])
}

///|
test "Local projection retains the same original execution and physical failure" {
  let payload = Ref(17)
  let originals : Array[@strategy.RunIssue] = [
    Physical(ExecutionLimit),
    Physical(RetentionLimit),
    Read(ProducerUnavailable),
    Implementation(LocalProjectionTestFailure::Marker(payload)),
  ]
  for original in originals {
    let projected = client_local_dispatch_run_issue(Execution(original))
    assert_true(physical_equal(projected, original))
  }
  match client_local_dispatch_run_issue(Execution(originals[3])) {
    Implementation(LocalProjectionTestFailure::Marker(actual)) => {
      assert_true(physical_equal(actual, payload))
      actual.val = 23
    }
    _ => fail("the original implementation failure was replaced")
  }
  assert_eq(payload.val, 23)
}

///|
test "actual configured Local rejection preserves its configuration family" {
  let assets = @publication_host.client_local_product_assets()
  let contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let host = open_source_free_local_host(
    single_source_free_capacity_prepared(),
    contracts,
    assets.values,
    1L,
    0L,
    0L,
    0L,
    fragment_body=Some(assets.fragment),
    ordered_body=assets.ordered,
  ).unwrap()
  let run = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(host),
  )
  let ledger = @strategy.captured_dag_ledger(run)
  let owner = @strategy.graph_task_owner(@strategy.captured_dag_graph(run), 0).unwrap()
  let before = @resources.ledger_usage(ledger)
  // The real selected zero-input task rejects an extra input before Compute.
  // Exercise the installed projector, not a reserving-success mock callback.
  let inputs : Array[@local_driver.LocalManagedAvailableOutput[Int]] = [
    @local_driver.local_managed_supplied_relation_input(),
  ]
  match
    @builtin.dispatch_managed_local_outputs(
      @builtin.configured_host_modules(host),
      inputs,
      @execution.process_managed_obligations(owner),
      0L,
    ) {
    Err(
      Implementation(
        Implementation(
          ClientLocalImplementationFailure::Dispatch(
            Configuration(InputUnavailable)
          )
        )
      )
    ) => ()
    _ =>
      fail("the actual Local configuration failure was flattened or admitted")
  }
  let after = @resources.ledger_usage(ledger)
  assert_eq(after.attempts, before.attempts)
  assert_eq(after.held_bytes, before.held_bytes)
  assert_eq(after.reserved_retention_bytes, before.reserved_retention_bytes)
  assert_eq(after.reserved_execution_bytes, before.reserved_execution_bytes)
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  let closed = @resources.ledger_usage(ledger)
  assert_eq(closed.held_bytes, 0L)
  assert_eq(closed.reserved_retention_bytes, 0L)
  assert_eq(closed.reserved_execution_bytes, 0L)
}

///|
test "Local estimate projection delegates dispatch and retains the original rate issue" {
  let physical : @strategy.RunIssue = Physical(TransferLimit)
  assert_true(
    physical_equal(
      client_local_estimate_run_issue(Dispatch(Execution(physical))),
      physical,
    ),
  )
  let original_rate = match @cost.prepare_rate_schedule(1, [], 0) {
    Err(issue) => issue
    Ok(_) => fail("the actual rate owner must reject the one-over work limit")
  }
  let original : @local_driver.LocalEstimateIssue = Rate(original_rate)
  match client_local_estimate_run_issue(original) {
    Implementation(ClientLocalImplementationFailure::Estimate(actual)) => {
      assert_true(physical_equal(actual, original))
      guard actual is Rate(Coverage(PlanningLimit)) else {
        fail("the original rate payload was replaced")
      }
    }
    _ => fail("the original rate issue was flattened")
  }
  match client_local_estimate_run_issue(InvalidConfiguration) {
    Implementation(
      ClientLocalImplementationFailure::Estimate(InvalidConfiguration)
    ) => ()
    _ => fail("the original estimate configuration was flattened")
  }
}
