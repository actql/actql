///|
test "Compute diagnostics collect fixed registrations without provider interpretation or execution" {
  let (run, _) = captured_graph_fixture()
  let registry = search_registry()
  let driver = @host_driver.open_dispatch_driver(run)
  let first = @connector.capability_registration_at(registry, 0).unwrap()
  let second = @connector.capability_registration_at(registry, 1).unwrap()
  let mode = Ref(0)
  let calls = Ref(0)
  let diagnostic : (Int) -> Array[(Int, String, String)]? = fn(_maximum) {
    calls.val += 1
    match mode.val {
      1 => Some([(0, "opaque", "not-a-compute")])
      2 => Some([(4, "opaque", "outside-graph")])
      3 => None
      4 => {
        @connector.close_capability_registry(registry)
        Some([])
      }
      _ => Some([(1, "same-display-name", "implementation-specific-reason")])
    }
  }
  let entry : @host_driver.ComputeContribution[Unit, String] = {
    exclusions: diagnostic,
    prepare: fn(_, _, _, _) { Err("must-not-prepare") },
    propose: fn(_, _, _) { Err("must-not-propose") },
  }
  let other : @host_driver.ComputeContribution[Unit, String] = {
    ..entry,
    exclusions: _ => Some([(2, "same-display-name", "another-reason")]),
  }
  let installation = @connector.install_capability_implementations(
    registry,
    [(second, other), (first, entry)],
    2,
    registry_order=true,
  ).unwrap()
  let limits = dispatch_test_limits()
  let host = @host_driver.open_compute_host(
    driver,
    registry,
    installation,
    limits.capacity,
    100,
    10000,
    2,
  ).unwrap()
  let before = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_true(
    @host_driver.compute_host_exclusions(host, -1) is Err(InvalidLimits),
  )
  assert_true(@host_driver.compute_host_exclusions(host, 1) is Err(Unavailable))
  assert_eq(calls.val, 0)
  assert_eq(@host_driver.compute_host_exclusions(host, 4).unwrap(), [
    (1, "same-display-name", "implementation-specific-reason"),
    (2, "same-display-name", "another-reason"),
  ])
  assert_true(@host_driver.compute_host_exclusions(host, 3) is Err(Limit))
  for value in [1, 2] {
    mode.val = value
    assert_true(
      @host_driver.compute_host_exclusions(host, 10) is Err(InvalidTask),
    )
  }
  mode.val = 3
  assert_true(@host_driver.compute_host_exclusions(host, 10) is Err(Limit))
  mode.val = 4
  assert_true(
    @host_driver.compute_host_exclusions(host, 10) is Err(Unavailable),
  )
  assert_eq(@resources.ledger_usage(@strategy.captured_dag_ledger(run)), before)
  assert_eq(@strategy.strategy_history_count(run), 0)
}
