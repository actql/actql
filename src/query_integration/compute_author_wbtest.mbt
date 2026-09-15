///|
test "Compute author context retains exact task owners without exposing mutable DAG state" {
  let (run, _) = captured_graph_fixture()
  let driver = @host_driver.open_dispatch_driver(run)
  let sequences = dispatch_test_generated(run)
  let first = sequences[0]
  let context = @host_driver.prepare_compute_author_context(driver, sequences).unwrap()
  sequences.clear()
  assert_true(
    physical_equal(
      @host_driver.compute_author_sequence(context, 1).unwrap(),
      first,
    ),
  )
  assert_true(@host_driver.compute_author_sequence(context, 0) is None)
  assert_true(@host_driver.compute_author_sequence(context, 4) is None)
  assert_true(
    @host_driver.prepare_compute_author_context(driver, [])
    is Err(ForeignPreparation),
  )
  let (other, _) = captured_graph_fixture()
  assert_true(
    @host_driver.prepare_compute_author_context(
      driver,
      dispatch_test_generated(other),
    )
    is Err(ForeignPreparation),
  )
  let ledger = @strategy.captured_dag_ledger(run)
  let before = @resources.ledger_usage(ledger)
  @host_driver.charge_compute_author_planning(context, 7).unwrap()
  assert_eq(
    @resources.ledger_usage(ledger).planning_work,
    before.planning_work + 7,
  )
  assert_true(
    @host_driver.charge_compute_author_planning(context, -1) is Err(_),
  )
  assert_eq(
    @resources.ledger_usage(ledger).planning_work,
    before.planning_work + 7,
  )
}
