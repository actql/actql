///|
fn supplied_parameter_preparation() -> (
  @lower.Prepared,
  @parameter.Declarations,
) {
  let seed = capture_values(
    capture_fixture(),
    0,
    max_rows=2,
    run_limits().input_values,
  ).unwrap()
  let key = @evidence.declare_primary_key(
    input_cursor("[\"n\"]"),
    @carrier.relation(@carrier.typed_rows(captured_schema(seed))),
    { max_fields: 2, max_name_bytes: 100, },
  ).unwrap()
  let declarations = @parameter.read_declarations(
    Some(input_cursor("{\"n\":{\"type\":\"number\",\"nullable\":false}}")),
    { max_parameters: 10, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"derive\":{\"v\":\"n + $n\"}},{\"filter\":\"v > 0\"},{\"select\":[\"v\",\"s\"]}]",
    ),
    [("rows", @pipeline.KeyedInput(key))],
    Some(declarations),
    Some(input_cursor("\"rows\"")),
    {
      max_steps: 100,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  (
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    declarations,
  )
}

///|
test "checked fragment sequence accepts supplied keyed rows and bound parameters together" {
  let (prepared, declarations) = supplied_parameter_preparation()
  let owner = bind_number(prepared, declarations, 10)
  let sequence = prepared_sequence(owner)
  let contexts = [
    sequence_fragment_context(sequence, 0, 2L),
    sequence_fragment_context(sequence, 1, 2L),
  ]
  let source = [
    input_cursor("{\"n\":3,\"s\":\"é\"}"),
    input_cursor("{\"n\":-20,\"s\":\"drop\"}"),
  ]
  let captured = capture_input(
    owner,
    0,
    source,
    max_rows=2,
    run_limits().input_values,
  ).unwrap()
  source.clear()
  let result = evaluate_sequence_components(
    registered_relation_contracts(),
    sequence,
    [captured],
    ["select_2"],
    run_limits(),
    { remaining: 100000, max_frames: 100, },
    fragments=Some(contexts),
  ).unwrap()
  // Store slots include the supplied input before the three operation outputs.
  let table = result.store.tables[3].unwrap().table
  assert_eq(table.names, ["v", "s"])
  assert_eq(table.rows.length(), 1)
  assert_true(table.rows[0][0] is Number(13.0))
  assert_true(
    table.rows[0][1] is Text("é") ||
    table.rows[0][1] is Captured(@admitted.Text("é")),
  )
  let other_owner = bind_number(prepared, declarations, 11)
  let other_input = capture_input(
    other_owner,
    0,
    [input_cursor("{\"n\":3,\"s\":\"é\"}")],
    max_rows=1,
    run_limits().input_values,
  ).unwrap()
  assert_true(
    evaluate_sequence_components(
      registered_relation_contracts(),
      sequence,
      [other_input],
      ["select_2"],
      run_limits(),
      { remaining: 100000, max_frames: 100, },
      fragments=Some(contexts),
    )
    is Err(InputOwnership),
  )
}

///|
test "fragment admission does not replace actual supplied input key validation" {
  let (prepared, declarations) = supplied_parameter_preparation()
  let owner = bind_number(prepared, declarations, -100)
  let sequence = prepared_sequence(owner)
  let contexts = [
    sequence_fragment_context(sequence, 0, 2L),
    sequence_fragment_context(sequence, 1, 2L),
  ]
  let row = input_cursor("{\"n\":3,\"s\":\"same\"}")
  let input = capture_input(
    owner,
    0,
    [row, row],
    max_rows=2,
    run_limits().input_values,
  ).unwrap()
  // Both rows would be filtered out. The input promise still has to hold.
  assert_true(
    evaluate_sequence_components(
      registered_relation_contracts(),
      sequence,
      [input],
      ["select_2"],
      run_limits(),
      { remaining: 100000, max_frames: 100, },
      fragments=Some(contexts),
    )
    is Err(InputKey(0, DuplicateKey(_, _))),
  )
}
