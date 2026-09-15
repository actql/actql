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

///|
fn captured_graph_fixture(
  count? : Bool = false,
  join? : Bool = false,
  self_join? : Bool = false,
) -> (@strategy.CapturedDAG, @planning.MockQueryIssuer) raise {
  let program = query_checked_program_fixture(
    dag=true,
    dag_count=count,
    dag_join=join,
    self_join~,
  )
  let sequence = query_checked_sequence(program)
  let owners = physical_graph_owners(program)
  owners[0] = @query.query_sequence_owner(sequence)
  let graph = @strategy.prepare_checked_dag(program, owners, 5, 1000).unwrap()
  let requirement = @planning.prepare_query_requirement(
    @planning.prepare_query_material(sequence, query_material_limits()).unwrap(),
    @program_check.source_identity(program),
    { max_rows: 10, max_value_bytes: 100, },
    query_material_limits(),
  ).unwrap()
  let (query_body, evidence_body) = query_evidence_test_bodies()
  let contracts = @planning.admit_query_evidence_contracts(
    query_body,
    evidence_body,
    query_capture_limits(),
  ).unwrap()
  let issuer = @planning.prepare_mock_query_issuer(
    contracts, requirement, "dag-test", 100,
  ).unwrap()
  let attempt = query_issuer_attempt(issuer, sequence, @planning.NativeQuery)
  query_issuer_run(attempt)
  let records = @planning.issue_mock_query_records(
    attempt,
    query_material_limits(),
  ).unwrap()
  let observation = @planning.capture_mock_query(
    issuer,
    attempt,
    records,
    query_capture_limits(),
  ).unwrap()
  let source = @planning.mock_captured_source(issuer, attempt, observation).unwrap()
  let ledger = @resources.create_ledger({
    planning_work: 10000,
    attempts: 10,
    holdings: 10,
    transfer_bytes: 300000L,
    retained_bytes: 32000000L,
    execution_bytes: 134217728L,
  }).unwrap()
  (@strategy.open_captured_dag(graph, source, ledger).unwrap(), issuer)
}

///|
fn captured_graph_local(
  run : @strategy.CapturedDAG,
  task : Int,
  limits? : @execution.SequenceExecutionLimits = compute_test_limits(),
  supplied_registry? : @planning.CapabilityRegistry? = None,
) -> Result[Unit, @strategy.RunIssue] raise {
  let owner = @strategy.graph_task_owner(
    @strategy.captured_dag_graph(run),
    task,
  ).unwrap()
  let input_count = @pipeline.input_count(
    @lower.pipeline(@lower.bound_preparation(owner)),
  )
  let inputs = Array::makei(input_count, port => {
    @strategy.captured_task_input(run, task, 100, 10000, input_index=port).unwrap()
  })
  let request = @planning.prepare_fixed_compute_request(inputs, {
    contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
    max_rows: 100,
    max_value_bytes: 10000,
    common_fragment: None,
  }).unwrap()
  let registry = match supplied_registry {
    Some(registry) => registry
    None =>
      @planning.prepare_capability_registry(
        [{ name: "local", acquisition: false, fixed_compute: true, }],
        1,
        100,
      ).unwrap()
  }
  let generated = if @pipeline.step_count(
      @lower.pipeline(@lower.bound_preparation(owner)),
    ) ==
    1 {
    compute_test_sequence(owner)
  } else {
    query_generated(owner)
  }
  let prepared = @planning.local_fixed_compute_candidate(
    @planning.capability_registration_at(registry, 0).unwrap(),
    request,
    generated,
    [{ work_slots: [0, 1, 2, 3, 4], milliseconds: Some(5L), }],
    { transfer_bytes: Some(0L), retained_bytes: None, money_units: None, },
    100,
  ).unwrap()
  guard @planning.choose_fixed_compute_candidate(
      registry,
      request,
      [@planning.prepared_compute_candidate(prepared)],
      None,
      100,
    ).unwrap()
    is Proposed(choice) else {
    abort("local candidate")
  }
  @strategy.execute_captured_local_task(run, task, choice, prepared, limits, {
    max_work: 10000,
    max_bytes: 10000,
    max_nodes: 10000,
    max_depth: 100,
  })
}

///|
test "captured checked DAG runs shared X A B C in checked control order" {
  let (run, issuer) = captured_graph_fixture()
  assert_eq(@strategy.next_captured_task(run), Some(1))
  assert_true(
    @strategy.captured_task_input(run, 2, 100, 10000) is Err(NotReady),
  )
  captured_graph_local(run, 1).unwrap()
  assert_eq(@strategy.next_captured_task(run), Some(2))
  captured_graph_local(run, 2).unwrap()
  // C consumes completed A, not the now closed original acquisition.
  @planning.close_mock_query_issuer(issuer)
  captured_graph_local(run, 3).unwrap()
  assert_true(@strategy.next_captured_task(run) is None)
  for (task, expected) in [(1, [3.0]), (2, [3.0, 2.0]), (3, [3.0])] {
    let output = @strategy.captured_task_output(run, task, Step(1)).unwrap()
    assert_eq(@execution.completed_row_count(output), expected.length())
    for i, value in expected {
      assert_true(
        @execution.completed_cell(output, i, 0) is Some(Number(actual)) &&
        actual == value,
      )
    }
  }
}

///|
test "captured count DAG binds its exact single step port and survives source close" {
  let (run, issuer) = captured_graph_fixture(count=true)
  assert_eq(@strategy.captured_task_target(run, 0), None)
  assert_eq(@strategy.captured_task_target(run, -1), None)
  assert_eq(@strategy.captured_task_target(run, 4), None)
  assert_eq(@strategy.captured_task_target(run, 1), Some(Step(0)))
  assert_eq(@strategy.captured_task_target(run, 3), Some(Step(1)))
  let edge = @strategy.graph_data_at(@strategy.captured_dag_graph(run), 2).unwrap()
  assert_eq((edge.producer, edge.consumer, edge.target), (1, 3, Step(0)))
  captured_graph_local(run, 1).unwrap()
  assert_true(@strategy.captured_task_output(run, 1, Step(1)) is None)
  let counted = @strategy.captured_task_output(run, 1, Step(0)).unwrap()
  assert_eq(@execution.completed_row_count(counted), 1)
  assert_true(@execution.completed_cell(counted, 0, 0) is Some(Number(2)))
  captured_graph_local(run, 2).unwrap()
  @planning.close_mock_query_issuer(issuer)
  captured_graph_local(run, 3).unwrap()
  let downstream = @strategy.captured_task_output(run, 3, Step(1)).unwrap()
  assert_true(@execution.completed_cell(downstream, 0, 0) is Some(Number(2)))
  @strategy.close_captured_task_output(run, 1)
  assert_true(@strategy.captured_task_output(run, 1, Step(0)) is None)
  assert_true(@execution.completed_cell(downstream, 0, 0) is Some(Number(2)))
}

///|
test "captured DAG cancellation stops new branches but keeps independent completed tasks" {
  let (run, issuer) = captured_graph_fixture()
  captured_graph_local(run, 1).unwrap()
  let pending = @strategy.captured_task_input(run, 2, 100, 10000).unwrap()
  @planning.close_mock_query_issuer(issuer)
  assert_false(@execution.producer_read_available(pending))
  assert_true(
    @strategy.captured_task_input(run, 2, 100, 10000)
    is Err(Read(ProducerUnavailable)),
  )
  @strategy.stop_captured_dag(run)
  assert_true(@strategy.captured_task_input(run, 2, 100, 10000) is Err(Stopped))
  assert_true(@strategy.next_captured_task(run) is None)
  let output = @strategy.captured_task_output(run, 1, Step(1)).unwrap()
  assert_eq(@execution.completed_row_count(output), 1)
  assert_true(@strategy.captured_task_output(run, 2, Step(1)) is None)
}

///|
test "captured DAG latches execution failure without revoking previous task success" {
  let (run, _issuer) = captured_graph_fixture()
  captured_graph_local(run, 1).unwrap()
  assert_true(
    captured_graph_local(run, 2, limits={
      ..compute_test_limits(),
      max_work: 0,
    })
    is Err(Compute(_)),
  )
  assert_true(@strategy.next_captured_task(run) is None)
  assert_true(@strategy.captured_task_input(run, 3, 100, 10000) is Err(Stopped))
  assert_true(@strategy.captured_task_output(run, 1, Step(1)) is Some(_))
  assert_true(@strategy.captured_task_output(run, 2, Step(1)) is None)
  assert_true(@strategy.captured_dag_failure(run) is Some((2, Compute(_))))
  @strategy.stop_captured_dag(run)
  assert_true(@strategy.captured_dag_failure(run) is Some((2, Compute(_))))
}
