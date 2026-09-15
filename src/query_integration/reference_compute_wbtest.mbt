///|
test "independent numeric kernel uses checked shape and exact fixed input without engine execution" {
  let (run, issuer) = captured_graph_fixture()
  let owner = @strategy.graph_task_owner(@strategy.captured_dag_graph(run), 1).unwrap()
  let input = @strategy.captured_task_input(run, 1, 100, 10000).unwrap()
  let plan = @reference_compute.prepare_numeric_plan(
    owner,
    100,
    10000,
    native_compile_limits().expressions,
  ).unwrap()
  assert_true(
    physical_equal(@reference_compute.numeric_plan_owner(plan), owner),
  )
  // Authored source is [3,1,2]; acquisition keeps [3,2]. The independent
  // id > 2 specialization selects position zero, projecting the id column.
  assert_eq(
    @reference_compute.select_numeric_rows(plan, input, 100).unwrap(),
    ([0], [0]),
  )
  assert_true(
    @reference_compute.select_numeric_rows(plan, input, 0) is Err(Limit),
  )
  let (other, _) = captured_graph_fixture()
  let foreign = @strategy.captured_task_input(other, 1, 100, 10000).unwrap()
  assert_true(
    @reference_compute.select_numeric_rows(plan, foreign, 100)
    is Err(Unsupported),
  )
  let unsupported = @strategy.graph_task_owner(
    @strategy.captured_dag_graph(run),
    3,
  ).unwrap()
  assert_true(
    @reference_compute.prepare_numeric_plan(
      unsupported,
      100,
      10000,
      native_compile_limits().expressions,
    )
    is Err(Unsupported),
  )
  // Kernel data is not a completed output or a common task success.
  let values : @execution.ValueLimits = {
    max_nodes: 100,
    max_text_bytes: 100,
    max_depth: 10,
    max_work: 100,
  }
  let rows = @reference_compute.materialize_numeric_output(
    plan, input, 6, 10, values,
  ).unwrap()
  assert_eq(@execution.admitted_output_row_count(rows), 1)
  assert_true(@execution.admitted_output_cell(rows, 0, 0) is Some(Number(3.0)))
  assert_true(physical_equal(@execution.admitted_output_owner(rows), owner))
  // Selection and materialization share one work counter, rather than resetting
  // at the boundary: four selection units plus one row and one admitted cell.
  assert_true(
    @reference_compute.materialize_numeric_output(plan, input, 5, 10, values)
    is Err(Limit),
  )
  assert_true(
    @reference_compute.materialize_numeric_output(plan, input, 6, 0, values)
    is Err(Output(CaptureLimit)),
  )
  assert_false(@strategy.captured_task_completed(run, 1))
  @planning.close_mock_query_issuer(issuer)
  assert_true(
    @reference_compute.select_numeric_rows(plan, input, 100) is Err(Unsupported),
  )
}
