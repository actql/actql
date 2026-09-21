///|
fn bounded_binding_rows_source(
  rows : String,
) -> (@lower.BoundPrepared, CompletedOutput) raise {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"left\":{\"type\":\"vector\",\"dimensions\":2,\"nullable\":false},\"right\":{\"type\":\"vector\",\"dimensions\":2,\"nullable\":false}},\"rows\":" +
    rows +
    "},\"as\":\"seed\"}]",
  )
  let sequence = prepared_sequence(owner)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    ["values_0"],
    100000,
    10000,
  ).unwrap()
  let completed = execute_generated_sequence(
    generated,
    [],
    compute_test_limits(),
  ).unwrap()
  (owner, completed_output(completed, @pipeline.Step(0)).unwrap())
}

///|
fn bounded_binding_rows_receiver(
  source_owner : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  let producer = @pipeline.produced_input(
    @lower.pipeline(@lower.bound_preparation(source_owner)),
    @pipeline.Step(0),
  ).unwrap()
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"derive\":{\"score\":{\"vector_score\":{\"left\":{\"field\":\"left\"},\"right\":{\"field\":\"right\"},\"metric\":\"dot\"}},\"joined\":{\"vector_concat\":[{\"field\":\"right\"},{\"field\":\"left\"}]}},\"from\":\"rows\"}]",
    ),
    [("rows", @pipeline.ProducedInput(producer))],
    None,
    None,
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
    expression_profiles={ text_time: false, veca: true, },
  ).unwrap()
}

///|
fn bounded_binding_rows_fixture(
  rows : String,
) -> (@bounded.Control, BoundedBindingRowsExecution, ProducerRead) raise {
  let (source_owner, source) = bounded_binding_rows_source(rows)
  let receiver = bounded_binding_rows_receiver(source_owner)
  let sequence = prepared_sequence(receiver)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [sequence_fragment_context(sequence, 0, 2L)],
    ["derive_0"],
    100000,
    10000,
  ).unwrap()
  let bound = bind_completed_input(receiver, 0, source_owner, source).unwrap()
  let input = prepare_producer_read(receiver, bound, 100, 10000).unwrap()
  let control = @bounded.control()
  let execution = start_bounded_binding_rows(
    control,
    generated,
    input,
    100,
    run_limits().output_values,
    100000,
    100,
    10000,
    10000,
  ).unwrap()
  (control, execution, input)
}

///|
fn bounded_binding_rows_ordered_context(
  sequence : @lower.PreparedSequence,
) -> FragmentRuntimeContext raise {
  guard @lower.sequence_step(sequence, 0) is Some(@lower.RowStep(kernel)) else {
    fail("ordered row kernel")
  }
  let references = @lower.prepare_ordered_references(kernel, {
    max_references: 100,
    max_pointer_bytes: 10000,
    max_work: 100000,
    max_frames: 100,
  }).unwrap()
  let contract = admit_ordered_contract(
    registered_relation_contracts(),
    registered_ordered(),
    registry_limits(),
  ).unwrap()
  let params = prepare_ordered_params(contract, references)
  let ordered = prepare_ordered_limits(
    params,
    {
      max_input_rows: 2L,
      max_value_bytes: 1000L,
      max_live_value_bytes: 10000L,
      max_work: 100000L,
    },
    10L,
    1000L,
  ).unwrap()
  let pipeline = @lower.prepare_fragment_pipeline(sequence, 0, {
    max_roots: 100,
    max_pointer_bytes: 10000,
    max_work: 100000,
  }).unwrap()
  let request = @lower.prepare_fragment_request(
    pipeline,
    10L,
    1000L,
    row_limits=Some(ordered.limits),
  ).unwrap()
  prepare_runtime_fragment(
    request,
    test_fragment_contract(),
    material_demands(),
    registry_limits(),
    ordered.limits,
    ordered=Some(ordered.params.contract),
  ).unwrap()
}

///|
fn bounded_binding_rows_ordered_fixture() -> (
  BoundedBindingRowsExecution,
  ProducerRead,
) raise {
  let source_owner = row_owner("")
  let source_sequence = prepared_sequence(source_owner)
  let source_generated = prepare_generated_sequence(
    registered_relation_contracts(),
    source_sequence,
    [],
    ["values_0"],
    100000,
    10000,
  ).unwrap()
  let source = completed_output(
    execute_generated_sequence(source_generated, [], compute_test_limits()).unwrap(),
    @pipeline.Step(0),
  ).unwrap()
  let producer = @pipeline.produced_input(
    @lower.pipeline(@lower.bound_preparation(source_owner)),
    @pipeline.Step(0),
  ).unwrap()
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"derive\":[{\"old\":\"a\"},{\"next\":\"old + b\"}],\"from\":\"rows\"}]",
    ),
    [("rows", @pipeline.ProducedInput(producer))],
    None,
    None,
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  let receiver = @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let sequence = prepared_sequence(receiver)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [bounded_binding_rows_ordered_context(sequence)],
    ["derive_0"],
    100000,
    10000,
  ).unwrap()
  let bound = bind_completed_input(receiver, 0, source_owner, source).unwrap()
  let input = prepare_producer_read(receiver, bound, 100, 10000).unwrap()
  let execution = start_bounded_binding_rows(
    @bounded.control(),
    generated,
    input,
    100,
    run_limits().output_values,
    100000,
    100,
    10000,
    10000,
  ).unwrap()
  (execution, input)
}

///|
test "bounded binding rows resume vector expressions and complete exactly" {
  let (_, execution, input) = bounded_binding_rows_fixture(
    "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{\"id\":2,\"left\":[2,1],\"right\":[4,3]}]",
  )
  let mut advances = 0
  let mut completed : CompletedOutput? = None
  while completed is None {
    advances += 1
    match advance_bounded_binding_rows(execution, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsComplete(output, ..) => completed = Some(output)
      BoundedBindingRowsFailed(_, ..) => fail("unexpected failure")
      BoundedBindingRowsStopped(_, ..) => fail("unexpected stop")
    }
  }
  assert_true(advances > 10)
  let output = completed.unwrap()
  assert_eq(completed_row_count(output), 2)
  assert_eq(completed_column_count(output), 5)
  assert_eq(
    Array::makei(5, column => completed_column_name(output, column).unwrap()),
    ["id", "joined", "left", "right", "score"],
  )
  assert_true(completed_cell(output, 0, 4) is Some(Number(11.0)))
  assert_true(completed_cell(output, 1, 4) is Some(Number(11.0)))
  guard completed_cell(output, 0, 1) is Some(Captured(@admitted.Vector(joined))) else {
    fail("expected joined vector")
  }
  assert_eq(@admitted.elements(joined), [3.0, 4.0, 1.0, 2.0])
  assert_true(producer_read_available(input))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_false(bounded_binding_rows_cleanup_pending(execution))
}

///|
test "bounded binding rows cancel without publishing partial output" {
  let (control, execution, input) = bounded_binding_rows_fixture(
    "[{\"id\":1,\"left\":[1,2],\"right\":[3,4]},{\"id\":2,\"left\":[2,1],\"right\":[4,3]}]",
  )
  for i = 0; i < 8; i = i + 1 {
    assert_true(
      advance_bounded_binding_rows(execution, 1)
      is Ok(BoundedBindingRowsContinue(..)),
    )
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_binding_rows(execution, 1)
    is Ok(BoundedBindingRowsStopped(@bounded.Cancelled, ..)),
  )
  assert_true(producer_read_available(input))
  assert_true(bounded_binding_rows_cleanup_pending(execution))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_false(bounded_binding_rows_cleanup_pending(execution))
  assert_true(producer_read_available(input))
}

///|
test "bounded binding rows preserve authored binding dependencies" {
  let (execution, input) = bounded_binding_rows_ordered_fixture()
  let mut completed : CompletedOutput? = None
  while completed is None {
    match advance_bounded_binding_rows(execution, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsComplete(output, ..) => completed = Some(output)
      BoundedBindingRowsFailed(_, ..) => fail("unexpected failure")
      BoundedBindingRowsStopped(_, ..) => fail("unexpected stop")
    }
  }
  let output = completed.unwrap()
  assert_eq(completed_row_count(output), 2)
  assert_eq(
    Array::makei(4, column => completed_column_name(output, column).unwrap()),
    ["a", "b", "next", "old"],
  )
  assert_true(completed_cell(output, 0, 2) is Some(Number(1.0)))
  assert_true(completed_cell(output, 1, 2) is Some(Number(1.0)))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_true(producer_read_available(input))
}
