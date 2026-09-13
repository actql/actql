///|
fn physical_graph_owners(
  program : @program_check.CheckedProgram,
) -> Array[@lower.BoundPrepared] {
  let identity = @program_check.source_identity(program)
  Array::makei(@program_check.unit_count(program), stage => {
    let pipeline = @program_check.unit_pipeline(program, stage).unwrap()
    let prepared = @lower.prepare(pipeline, {
      max_nodes: 100,
      max_references: 100,
      max_work: 100000,
      max_identifier_bytes: 10000,
    }).unwrap()
    let values = @parameter_refs.bound_values(
      @context.stage_identity_parameter_values(
        @context.program_identity_stage_at(identity, stage).unwrap(),
      ),
    )
    @lower.bind_parameters(
      prepared,
      Some(values),
      max_parameters=100,
      max_name_bytes=10000,
    ).unwrap()
  })
}

///|
test "physical DAG reads checked data and control edges separately" {
  let program = query_checked_program_fixture(dag=true)
  let owners = physical_graph_owners(program)
  let graph = @strategy.prepare_checked_dag(program, owners, 4, 1000).unwrap()
  assert_eq(@strategy.graph_task_count(graph), 4)
  assert_eq(@strategy.graph_data_count(graph), 3)
  assert_eq(@strategy.graph_control_count(graph), 3)
  for (edge, producer, consumer) in [(0, 0, 1), (1, 0, 2), (2, 1, 3)] {
    let actual = @strategy.graph_data_at(graph, edge).unwrap()
    assert_eq(
      (actual.producer, actual.consumer, actual.input),
      (producer, consumer, 0),
    )
    assert_eq(actual.target, @pipeline.Step(1))
  }
  // B reads X, but must still wait for A's checked Stage-success barrier.
  for i in 0..<3 {
    let control = @strategy.graph_control_at(graph, i).unwrap()
    assert_eq((control.predecessor, control.consumer), (i, i + 1))
  }
  assert_true(
    @strategy.prepare_checked_dag(program, owners, 3, 1000) is Err(TaskLimit),
  )
  assert_true(
    @strategy.prepare_checked_dag(program, owners, 4, 0) is Err(WorkLimit),
  )
  let other = query_checked_program_fixture(dag=true)
  let foreign = physical_graph_owners(other)
  assert_true(
    @strategy.prepare_checked_dag(program, foreign, 4, 1000)
    is Err(ForeignPipeline(0)),
  )
  owners[1] = foreign[1]
  assert_false(
    physical_equal(@strategy.graph_task_owner(graph, 1).unwrap(), foreign[1]),
  )
  assert_true(
    @strategy.prepare_checked_dag(program, owners, 4, 1000)
    is Err(ForeignPipeline(1)),
  )
}
