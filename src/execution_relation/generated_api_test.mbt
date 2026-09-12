///|
fn consumer_fixture(
  total : String,
) -> (
  @execution_relation.GeneratedSequence,
  @execution_relation.SequenceExecutionLimits,
) raise {
  let syntax = @decode.admit(
    @source.parse_json(
      "[{\"values\":{\"schema\":{\"a\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"a\":1},{\"a\":0}]},\"as\":\"seed\"},{\"derive\":[{\"old\":\"a\"},{\"a\":\"old + 1\"},{\"total\":\"" +
      total +
      "\"}]},{\"filter\":\"total > 1\"},{\"select\":[\"total\",\"a\"]}]",
      { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
    ).unwrap(),
    {
      max_nodes: 1000,
      max_depth: 100,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
  ).unwrap()
  let checked = @pipeline.check(syntax, [], None, None, {
    max_steps: 100,
    max_work: 100000,
    max_text_bytes: 10000,
    max_nodes: 1000,
    max_tokens: 1000,
    max_depth: 100,
  }).unwrap()
  let prepared = @lower.prepare(checked, {
    max_nodes: 100,
    max_references: 100,
    max_work: 10000,
    max_identifier_bytes: 10000,
  }).unwrap()
  let owner = @lower.bind_parameters(
    prepared,
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let sequence = @lower.prepare_sequence(owner, {
    max_steps: 100,
    max_rows: 100,
    max_cells: 10000,
    max_bindings: 100,
    max_name_bytes: 10000,
    expressions: {
      max_nodes: 10000,
      max_work: 100000,
      max_depth: 100,
      max_literal_nodes: 10000,
      max_literal_text_bytes: 10000,
    },
  }).unwrap()
  let physical : @execution_relation.RegistryLimits = {
    max_body_bytes: 100000,
    max_body_nodes: 10000,
    max_body_depth: 100,
  }
  let relations = @execution_relation.admit_relation_registry(
    registered_body(),
    registered_values(),
    physical,
  ).unwrap()
  let contract = @execution_relation.admit_fragment_contract(
    relations,
    registered_fragment(),
    physical,
  ).unwrap()
  let ordered = @execution_relation.admit_ordered_contract(
    relations,
    registered_ordered(),
    physical,
  ).unwrap()
  let logical : @lower.FragmentRowLimits = {
    max_input_rows: 2L,
    max_value_bytes: 1000L,
    max_live_value_bytes: 10000L,
    max_work: 100000L,
  }
  let contexts : Array[@execution_relation.FragmentRuntimeContext] = []
  for step in [1, 2] {
    let pipeline = @lower.prepare_fragment_pipeline(sequence, step, {
      max_roots: 100,
      max_pointer_bytes: 10000,
      max_work: 100000,
    }).unwrap()
    let request = @lower.prepare_fragment_request(
      pipeline,
      10L,
      1000L,
      row_limits=if step == 1 { Some(logical) } else { None },
    ).unwrap()
    contexts.push(
      @execution_relation.prepare_runtime_fragment(
        request,
        contract,
        {
          max_roots: 100,
          max_nodes: 10000,
          max_work: 100000,
          max_text_bytes: 10000,
          max_links: 10000,
        },
        physical,
        logical,
        ordered=if step == 1 { Some(ordered) } else { None },
      ).unwrap(),
    )
  }
  let generated = @execution_relation.prepare_generated_sequence(
    relations,
    sequence,
    contexts,
    ["select_3"],
    100000,
    10000,
  ).unwrap()
  contexts.clear()
  let values : @execution_relation.ValueLimits = {
    max_nodes: 10000,
    max_text_bytes: 10000,
    max_depth: 100,
    max_work: 100000,
  }
  let limits : @execution_relation.SequenceExecutionLimits = {
    rows: {
      max_rows: 100,
      metadata_entries: 10000,
      retained_entries: 10000,
      operation_entries: 10000,
      input_values: values,
      output_values: values,
    },
    max_work: 100000,
    max_frames: 100,
  }
  (generated, limits)
}

///|
test "package consumer runs values ordered derive filter select without private constructors" {
  let (generated, limits) = consumer_fixture("old + a")
  let completed = @execution_relation.execute_generated_sequence(
    generated,
    [],
    limits,
  ).unwrap()
  let output = @execution_relation.completed_output(
    completed,
    @pipeline.Step(3),
  ).unwrap()
  assert_eq(@execution_relation.completed_row_count(output), 1)
  assert_eq(@execution_relation.completed_column_count(output), 2)
  assert_eq(@execution_relation.completed_column_name(output, 0), Some("total"))
  assert_eq(@execution_relation.completed_column_name(output, 1), Some("a"))
  assert_true(
    @execution_relation.completed_cell(output, 0, 0) is Some(Number(3.0)),
  )
  assert_true(
    @execution_relation.completed_cell(output, 0, 1) is Some(Number(2.0)),
  )
  assert_true(@execution_relation.completed_cell(output, -1, 0) is None)
  assert_true(@execution_relation.completed_cell(output, 0, 2) is None)
  assert_true(@execution_relation.completed_column_name(output, -1) is None)
  guard @execution_relation.execute_generated_sequence(generated, [], {
      ..limits,
      max_work: -1,
    })
    is Err(issue) else {
    fail("negative budget")
  }
  assert_true(@execution_relation.sequence_failure_kind(issue) is InvalidLimits)
}

///|
test "package diagnostics retain row slot expression source and distinguish arithmetic from budget" {
  let (generated, limits) = consumer_fixture("1 / 0")
  guard @execution_relation.execute_generated_sequence(generated, [], limits)
    is Err(Rows(1, Evaluation(0, 2, evaluation))) else {
    fail("expected row zero slot two failure")
  }
  assert_true(evaluation.kind is Scalar(ArithmeticFailure))
  assert_eq(
    @decode.text(@lower.expression_location(evaluation.expression).source).unwrap(),
    "1 / 0",
  )
  assert_true(
    @lower.expression_location(evaluation.expression).range is Some(_),
  )
  guard @execution_relation.execute_generated_sequence(generated, [], {
      ..limits,
      max_work: 0,
    })
    is Err(issue) else {
    fail("expected control budget failure")
  }
  assert_true(issue is Wiring(Limit))
}
