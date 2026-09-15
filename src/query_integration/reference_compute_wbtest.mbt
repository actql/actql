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
  let physical : @execution.FixedInputGuardMeasureLimits = {
    max_work: 100,
    max_bytes: 100,
    max_nodes: 100,
    max_depth: 10,
  }
  let measured = @reference_compute.measure_numeric_output(
    plan,
    input,
    6,
    2,
    100,
    values,
    physical,
    root_limits=physical,
  ).unwrap()
  assert_eq(
    @execution.admitted_output_row_count(
      @reference_compute.measured_numeric_rows(measured),
    ),
    1,
  )
  assert_true(
    @reference_compute.measure_numeric_output(
      plan,
      input,
      6,
      1,
      100,
      values,
      physical,
      root_limits=physical,
    )
    is Err(Guard(InputRows)),
  )
  assert_true(
    @reference_compute.measure_numeric_output(
      plan,
      input,
      6,
      2,
      0,
      values,
      physical,
      root_limits=physical,
    )
    is Err(Guard(ValueBytes(InputValues, 0, 0))),
  )
  assert_true(
    @reference_compute.measure_numeric_output(
      plan,
      input,
      6,
      2,
      100,
      values,
      { ..physical, max_work: 0, },
      root_limits=physical,
    )
    is Err(Guard(MeasurementWork)),
  )
  assert_eq(
    @reference_compute.measured_numeric_root_usage(measured),
    (6, 13, 6),
  )
  assert_true(
    @reference_compute.measure_numeric_output(
      plan,
      input,
      6,
      2,
      4,
      values,
      physical,
      root_limits=physical,
    )
    is Err(RootValueBytes(1, 2)),
  )
  assert_true(
    @reference_compute.measure_numeric_output(
      plan,
      input,
      6,
      2,
      100,
      values,
      physical,
      root_limits={ ..physical, max_work: 5, },
    )
    is Err(RootWorkLimit(1, 2)),
  )
  let pending = @reference_compute.measure_numeric_output(
    plan,
    input,
    6,
    2,
    100,
    values,
    physical,
    root_limits=physical,
  ).unwrap()
  let generated = query_generated(owner, retained=[
    @lower.node_id(@lower.node_at(@lower.bound_preparation(owner), 1).unwrap()),
  ])
  let foreign_owner = @execution.producer_read_receiver(foreign)
  let foreign_generated = query_generated(foreign_owner, retained=[
    @lower.node_id(
      @lower.node_at(@lower.bound_preparation(foreign_owner), 1).unwrap(),
    ),
  ])
  assert_true(
    @reference_compute.complete_numeric_output(
      foreign_generated, measured, 100, 10000,
    )
    is Err(Completion(ForeignInputs)),
  )
  let completed = @reference_compute.complete_numeric_output(
    generated, measured, 100, 10000,
  ).unwrap()
  assert_true(
    @reference_compute.complete_numeric_output(generated, measured, 100, 10000)
    is Err(Unsupported),
  )
  let output = @reference_compute.numeric_completed_output(completed)
  let next = typed_receiver(owner, "[{\"select\":[\"id\"]}]", target=Step(1))
  let bound = @execution.bind_completed_input(next, 0, owner, output).unwrap()
  let downstream = @execution.execute_generated_sequence(
    compute_test_sequence(next),
    [],
    compute_test_limits(),
    produced=[bound],
  ).unwrap()
  @planning.close_mock_query_issuer(issuer)
  // A pending completion cannot seal after upstream revocation. A successful
  // independent result can still supply a new consumer until its own close.
  assert_true(
    @reference_compute.complete_numeric_output(generated, pending, 100, 10000)
    is Err(Unsupported),
  )
  assert_true(
    @execution.execute_generated_sequence(
      compute_test_sequence(next),
      [],
      compute_test_limits(),
      produced=[bound],
    )
    is Ok(_),
  )
  assert_eq(@execution.completed_row_count(output), 1)
  @reference_compute.close_numeric_output(completed)
  assert_true(
    @execution.execute_generated_sequence(
      compute_test_sequence(next),
      [],
      compute_test_limits(),
      produced=[bound],
    )
    is Err(_),
  )
  assert_eq(
    @execution.completed_row_count(
      @execution.completed_output(downstream, Step(0)).unwrap(),
    ),
    1,
  )
  assert_false(@strategy.captured_task_completed(run, 1))
  assert_true(
    @reference_compute.select_numeric_rows(plan, input, 100) is Err(Unsupported),
  )
}
