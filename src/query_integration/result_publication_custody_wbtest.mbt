///|
test "Result publication export matches only its live original captured Run" {
  let (run, issuer) = captured_graph_fixture()
  let (foreign, foreign_issuer) = captured_graph_fixture()
  let graph = @strategy.captured_dag_graph(run)
  for task in 1..<@strategy.graph_task_count(graph) {
    captured_graph_local(run, task).unwrap()
  }
  let output = @publication_host.prepare_captured_result_publication_export(
    run,
    0,
    native_publication_export_limits(),
    max_pins=2,
  ).unwrap()
  assert_true(output.matches_captured_run(run))
  assert_false(output.matches_captured_run(foreign))
  let task = @strategy.graph_result_task(graph, 0).unwrap()
  let occurrence = @strategy.graph_result_occurrence(graph, 0).unwrap()
  let borrow = @strategy.borrow_captured_result_output(run, task, occurrence, 2).unwrap()
  assert_true(@strategy.captured_result_borrow_matches_run(borrow, run))
  assert_false(@strategy.captured_result_borrow_matches_run(borrow, foreign))
  for task in 0..<@strategy.graph_task_count(graph) {
    @strategy.close_captured_task_output(run, task)
  }
  // Ordinary port close keeps each original consumer's responsibility live.
  assert_true(output.matches_captured_run(run))
  assert_true(@strategy.captured_result_borrow_matches_run(borrow, run))
  assert_true(@strategy.release_captured_result_borrow(borrow))
  assert_false(@strategy.captured_result_borrow_matches_run(borrow, run))
  assert_true(output.matches_captured_run(run))
  output.cancel()
  assert_false(output.matches_captured_run(run))
  assert_eq(
    @resources.ledger_usage(@strategy.captured_dag_ledger(run)).held_bytes,
    0L,
  )
  @mock.close_mock_query_issuer(issuer)
  @mock.close_mock_query_issuer(foreign_issuer)
  @strategy.stop_captured_dag(foreign)
  @strategy.close_captured_task_output(foreign, 0)
}

///|
test "Source Result publication keeps exact acquisition custody through port close" {
  let (run, issuer) = resident_source_captured_fixture()
  let (foreign, foreign_issuer) = resident_source_captured_fixture()
  let graph = @strategy.captured_dag_graph(run)
  let occurrence = @strategy.graph_result_occurrence(graph, 0).unwrap()
  let borrow = @strategy.borrow_captured_any_result_output(
    run, 0, occurrence, 2,
  ).unwrap()
  let output = @publication_host.prepare_captured_result_publication_export(
    run,
    0,
    native_publication_export_limits(),
    max_pins=2,
  ).unwrap()
  assert_true(@strategy.captured_any_result_borrow_matches_run(borrow, run))
  assert_false(
    @strategy.captured_any_result_borrow_matches_run(borrow, foreign),
  )
  assert_true(output.matches_captured_run(run))
  assert_false(output.matches_captured_run(foreign))
  @strategy.close_captured_task_output(run, 0)
  assert_true(output.matches_captured_run(run))
  assert_true(@strategy.captured_any_result_borrow_matches_run(borrow, run))
  assert_true(@strategy.release_captured_any_result_borrow(borrow))
  assert_false(@strategy.captured_any_result_borrow_matches_run(borrow, run))
  output.cancel()
  assert_false(output.matches_captured_run(run))
  @strategy.stop_captured_dag(run)
  @strategy.stop_captured_dag(foreign)
  @strategy.close_captured_task_output(foreign, 0)
  @mock.close_mock_query_issuer(issuer)
  @mock.close_mock_query_issuer(foreign_issuer)
  assert_eq(
    @resources.ledger_usage(@strategy.captured_dag_ledger(run)).held_bytes,
    0L,
  )
}

///|
test "captured consumer retirement retains original Result pins through same retry" {
  let (run, issuer) = captured_graph_fixture()
  let graph = @strategy.captured_dag_graph(run)
  for task in 1..<@strategy.graph_task_count(graph) {
    captured_graph_local(run, task).unwrap()
  }
  let task = @strategy.graph_result_task(graph, 0).unwrap()
  let occurrence = @strategy.graph_result_occurrence(graph, 0).unwrap()
  let held = @strategy.borrow_captured_result_output(run, task, occurrence, 2).unwrap()
  assert_false(@strategy.retire_captured_task_outputs(run))
  assert_false(@strategy.retire_captured_task_outputs(run))
  assert_true(@strategy.captured_result_borrow_matches_run(held, run))
  assert_true(@strategy.release_captured_result_borrow(held))
  assert_true(@strategy.retire_captured_task_outputs(run))
  assert_true(@strategy.retire_captured_task_outputs(run))
  @mock.close_mock_query_issuer(issuer)
}
