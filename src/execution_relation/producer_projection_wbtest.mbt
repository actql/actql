///|
fn projected_consumer(
  owner : @lower.BoundPrepared,
  fields : String,
  steps : String,
) -> @lower.BoundPrepared {
  let producer = @lower.pipeline(@lower.bound_preparation(owner))
  let checked = @relation.check(
    Select,
    input_cursor(fields),
    @pipeline.schema_at(producer, Step(0)).unwrap(),
    None,
    {
      max_work: 10000,
      max_nodes: 10000,
      max_text_bytes: 10000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  let limits : @pipeline.Limits = {
    max_steps: 100,
    max_work: 10000,
    max_text_bytes: 10000,
    max_nodes: 1000,
    max_tokens: 1000,
    max_depth: 100,
  }
  let projected = @pipeline.project_produced_input(
    producer,
    Step(0),
    checked,
    limits,
  ).unwrap()
  let pipeline = @pipeline.check_with_evidence(
    input_cursor(steps),
    [("prior", @pipeline.ProducedInput(@pipeline.projected_input(projected)))],
    None,
    Some(input_cursor("\"prior\"")),
    limits,
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(pipeline, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
test "empty completed projection retains checked column order and charges layout workspace" {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"a\":{\"type\":\"number\",\"nullable\":false},\"b\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[]},\"as\":\"seed\"}]",
  )
  let upstream = evaluate_sequence_components(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["values_0"],
    run_limits(),
    { remaining: 10000, max_frames: 100, },
  ).unwrap()
  let receiver = projected_consumer(
    owner, "[\"b\",{\"renamed\":\"a\"}]", "[{\"select\":[\"b\",\"renamed\"]}]",
  )
  let bound = bind_completed_input(
    receiver,
    0,
    owner,
    completed_output(upstream, Step(0)).unwrap(),
  ).unwrap()
  let exact = { ..run_limits(), max_rows: 0, operation_entries: 10, }
  let result = evaluate_sequence_components(
    registered_relation_contracts(),
    prepared_sequence(receiver),
    [],
    ["select_0"],
    exact,
    { remaining: 10000, max_frames: 100, },
    produced=[bound],
  ).unwrap()
  let table = test_row_output(completed_output(result, Step(0)).unwrap())
  assert_eq(table.names, ["b", "renamed"])
  assert_eq(table.rows.length(), 0)
  assert_true(
    evaluate_sequence_components(
      registered_relation_contracts(),
      prepared_sequence(receiver),
      [],
      ["select_0"],
      { ..exact, operation_entries: 9, },
      { remaining: 10000, max_frames: 100, },
      produced=[bound],
    )
    is Err(Rows(0, RowLimit)),
  )
}

///|
test "completed producer projection reorders aliases and preserves upstream rows" {
  let owner = row_owner("")
  let upstream = evaluate_sequence_components(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["values_0"],
    run_limits(),
    { remaining: 10000, max_frames: 100, },
  ).unwrap()
  let output = completed_output(upstream, Step(0)).unwrap()
  let receiver = projected_consumer(
    owner, "[{\"renamed\":\"b\"},\"a\"]", "[{\"select\":[\"renamed\",\"a\"]}]",
  )
  let bound = bind_completed_input(receiver, 0, owner, output).unwrap()
  let result = evaluate_sequence_components(
    registered_relation_contracts(),
    prepared_sequence(receiver),
    [],
    ["input_0", "select_0"],
    run_limits(),
    { remaining: 10000, max_frames: 100, },
    produced=[bound],
  ).unwrap()
  for target in [@pipeline.Input(0), @pipeline.Step(0)] {
    let table = test_row_output(completed_output(result, target).unwrap())
    assert_eq(table.names, ["renamed", "a"])
    assert_true(table.rows[0][0] is Number(0.0))
    assert_true(table.rows[0][1] is Number(1.0))
    assert_true(table.rows[1][0] is Number(1.0))
    assert_true(table.rows[1][1] is Number(0.0))
    assert_true(physical_equal(table.owner, receiver))
  }
  assert_eq(test_row_output(output).names, ["a", "b"])
  assert_true(test_row_output(output).rows[0][0] is Number(1.0))
  assert_true(physical_equal(test_row_output(output).owner, owner))
}

///|
test "projection charges full input and shares output budget with downstream operations" {
  let owner = row_owner("")
  let upstream = evaluate_sequence_components(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["values_0"],
    run_limits(),
    { remaining: 10000, max_frames: 100, },
  ).unwrap()
  let receiver = projected_consumer(owner, "[\"a\"]", "[{\"select\":[\"a\"]}]")
  let bound = bind_completed_input(
    receiver,
    0,
    owner,
    completed_output(upstream, Step(0)).unwrap(),
  ).unwrap()
  let exact = {
    ..run_limits(),
    input_values: {
      max_nodes: 6,
      max_text_bytes: 4,
      max_depth: 2,
      max_work: 10,
    },
    // Two rows at projection, two more at authored select. Neither is erased.
    output_values: {
      max_nodes: 8,
      max_text_bytes: 4,
      max_depth: 2,
      max_work: 12,
    },
  }
  assert_true(
    evaluate_sequence_components(
      registered_relation_contracts(),
      prepared_sequence(receiver),
      [],
      ["select_0"],
      { ..exact, input_values: { ..exact.input_values, max_nodes: 5, }, },
      { remaining: 10000, max_frames: 100, },
      produced=[bound],
    )
    is Err(InputLimit),
  )
  for
    limited in [
      { ..exact, output_values: { ..exact.output_values, max_nodes: 7, }, },
      { ..exact, output_values: { ..exact.output_values, max_text_bytes: 3, }, },
      { ..exact, output_values: { ..exact.output_values, max_work: 11, }, },
      { ..exact, operation_entries: 0, },
    ] {
    assert_true(
      evaluate_sequence_components(
        registered_relation_contracts(),
        prepared_sequence(receiver),
        [],
        ["select_0"],
        limited,
        { remaining: 10000, max_frames: 100, },
        produced=[bound],
      )
      is Err(Rows(0, RowLimit)),
    )
  }
  // Failed receiver attempts neither consume nor alter the upstream completion.
  assert_true(
    evaluate_sequence_components(
      registered_relation_contracts(),
      prepared_sequence(receiver),
      [],
      ["select_0"],
      exact,
      { remaining: 10000, max_frames: 100, },
      produced=[bound],
    )
    is Ok(_),
  )
}
