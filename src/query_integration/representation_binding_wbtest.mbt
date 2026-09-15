///|
test "physical representation binds the exact supplied completion and preserves its liveness" {
  let (run, _) = captured_graph_fixture()
  let (other, _) = captured_graph_fixture()
  captured_graph_local(run, 1).unwrap()
  captured_graph_local(other, 1).unwrap()
  let output = @strategy.captured_task_output(run, 1, Step(1)).unwrap()
  let same_port = @strategy.captured_task_output(run, 1, Step(1)).unwrap()
  let foreign = @strategy.captured_task_output(other, 1, Step(1)).unwrap()
  let storage = @execution.prepare_producer_storage(output, 100, 10000).unwrap()
  let imported = @duckdb.prepare_resident_import(
    storage, "bound_copy", 100, 10000,
  ).unwrap()
  assert_true(@execution.producer_storage_matches_output(storage, output))
  assert_true(@duckdb.resident_import_matches_output(imported, output))
  // A freshly restricted alias or an equal-valued other producer is not the
  // exact completion supplied to the representation builder.
  assert_false(@execution.producer_storage_matches_output(storage, same_port))
  assert_false(@duckdb.resident_import_matches_output(imported, foreign))
  @strategy.close_captured_task_output(run, 1)
  assert_false(@execution.producer_storage_matches_output(storage, output))
  assert_false(@duckdb.resident_import_matches_output(imported, output))
  assert_true(@strategy.captured_task_output(other, 1, Step(1)) is Some(_))
}
