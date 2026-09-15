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
  assert_false(@strategy.captured_task_completed(run, 1))
  @planning.close_mock_query_issuer(issuer)
  assert_true(
    @reference_compute.select_numeric_rows(plan, input, 100) is Err(Unsupported),
  )
}
