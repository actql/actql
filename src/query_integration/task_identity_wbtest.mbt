///|
test "checked task identity uses adopted identities and preserves input ports" {
  let program = query_checked_program_fixture(dag=true, dag_join=true)
  let graph = @strategy.prepare_checked_dag(
    program,
    physical_graph_owners(program),
    5,
    10000,
  ).unwrap()
  let reference = @strategy.prepare_checked_task_reference(graph, 3, 20, 1000).unwrap()
  let value = @strategy.checked_task_identity(reference)
  let source = @program_check.source_identity(program)
  assert_eq(
    value.unit_definition_cid,
    @program_check.unit_definition_cid(program, 3).unwrap(),
  )
  assert_eq(
    value.unit_contracts_cid,
    @program_check.unit_contracts_cid(program, 3).unwrap(),
  )
  assert_eq(
    value.program_definition_cid,
    @context.program_identity_definition_cid(source),
  )
  assert_eq(
    value.program_parameters_cid,
    @context.program_identity_parameter_values_cid(source),
  )
  assert_eq(
    value.unit_parameters_cid,
    @context.stage_identity_parameter_values_cid(
      @context.program_identity_stage_at(source, 3).unwrap(),
    ),
  )
  assert_eq(value.task, 3)
  assert_eq(value.output_step, 0)
  assert_eq(value.inputs.length(), 2)
  assert_eq(value.inputs[0], {
    input: 0,
    producer: 1,
    producer_target_is_input: false,
    producer_target_index: 1,
  })
  assert_eq(value.inputs[1], {
    input: 1,
    producer: 2,
    producer_target_is_input: false,
    producer_target_index: 1,
  })
  let original = @strategy.checked_task_identity(reference)
  value.inputs.clear()
  value.controls.clear()
  assert_eq(@strategy.checked_task_identity(reference), original)
}

///|
test "task identity distinguishes changed Parameter values without inventing a new definition" {
  let first = query_checked_program_fixture(
    dag=true,
    compute_filter="id > $minimum",
  )
  let second = query_checked_program_fixture(
    dag=true,
    compute_filter="id > $minimum",
    parameter_json="{\"minimum\":2}",
  )
  let identities = [first, second].map(program => {
    let graph = @strategy.prepare_checked_dag(
      program,
      physical_graph_owners(program),
      4,
      10000,
    ).unwrap()
    @strategy.checked_task_identity(
      @strategy.prepare_checked_task_reference(graph, 1, 20, 1000).unwrap(),
    )
  })
  assert_eq(
    identities[0].unit_definition_cid,
    identities[1].unit_definition_cid,
  )
  assert_eq(
    identities[0].program_definition_cid,
    identities[1].program_definition_cid,
  )
  assert_true(
    identities[0].unit_parameters_cid != identities[1].unit_parameters_cid,
  )
  assert_true(
    identities[0].program_parameters_cid != identities[1].program_parameters_cid,
  )
}

///|
test "checked task reference rejects foreign equal-content execution and revoked output" {
  let (run, issuer) = captured_graph_fixture()
  let (other, other_issuer) = captured_graph_fixture()
  let graph = @strategy.captured_dag_graph(run)
  let reference = @strategy.prepare_checked_task_reference(graph, 1, 20, 1000).unwrap()
  captured_graph_local(run, 1).unwrap()
  captured_graph_local(other, 1).unwrap()
  let output = @strategy.captured_task_output(run, 1, Step(1)).unwrap()
  let foreign = @strategy.captured_task_output(other, 1, Step(1)).unwrap()
  assert_true(@strategy.checked_task_output_matches(reference, output))
  assert_false(@strategy.checked_task_output_matches(reference, foreign))
  let second = @strategy.prepare_checked_task_reference(graph, 2, 20, 1000).unwrap()
  assert_false(@strategy.checked_task_output_matches(second, output))
  @mock.close_mock_query_issuer(issuer)
  // Independent completed task remains usable after its acquisition closes.
  assert_true(@strategy.checked_task_output_matches(reference, output))
  @strategy.close_captured_task_output(run, 1)
  assert_false(@strategy.checked_task_output_matches(reference, output))
  @mock.close_mock_query_issuer(other_issuer)
}

///|
test "checked task projection rejects limits before copying references" {
  let (run, issuer) = captured_graph_fixture()
  let graph = @strategy.captured_dag_graph(run)
  for task in [-1, 0, 4] {
    assert_true(
      @strategy.prepare_checked_task_reference(graph, task, 10, 100)
      is Err(@strategy.InvalidTask),
    )
  }
  assert_true(
    @strategy.prepare_checked_task_reference(graph, 1, -1, 100)
    is Err(@strategy.InvalidLimits),
  )
  assert_true(
    @strategy.prepare_checked_task_reference(graph, 1, 10, 0)
    is Err(@strategy.WorkLimit),
  )
  assert_true(
    @strategy.prepare_checked_task_reference(graph, 1, 0, 100)
    is Err(@strategy.ReferenceLimit),
  )
  assert_eq(@strategy.next_captured_task(run), Some(1))
  @mock.close_mock_query_issuer(issuer)
}
