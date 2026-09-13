///|
test "null parameters retain declaration typing without inventing literal null contexts" {
  let declarations = @parameter.read_declarations(
    Some(input_cursor("{\"n\":{\"type\":\"number\",\"nullable\":true}}")),
    { max_parameters: 10, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let pipeline = @pipeline.check(
    input_cursor(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1}]},\"as\":\"seed\"},{\"derive\":{\"v\":{\"$param\":\"n\"}}}]",
    ),
    [],
    Some(declarations),
    None,
    {
      max_steps: 100,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  let prepared = @lower.prepare(pipeline, {
    max_nodes: 100,
    max_references: 100,
    max_work: 1000,
    max_identifier_bytes: 1000,
  }).unwrap()
  guard @parameter.bind(declarations, Some(input_cursor("{\"n\":null}")), {
      max_nodes: 100,
      max_depth: 10,
      max_text_bytes: 1000,
    }).unwrap()
    is @parameter.Ready(values) else {
    fail("complete binding")
  }
  let owner = @lower.bind_parameters(
    prepared,
    Some(values),
    max_parameters=1,
    max_name_bytes=1,
  ).unwrap()
  let sequence = prepared_sequence(owner)
  let context = sequence_fragment_context(sequence, 1, 1L)
  let request = context.fragment.candidate.material.request.artifact
  let text = @identity.stringify_value(request.value, 10000, 1000, 100)
  assert_false(text.contains("null_contexts"))
  assert_true(text.contains("\"$param\":\"n\""))
  assert_true(text.contains("\"nullable\":true"))
  assert_true(text.contains("\"value\":null"))
  let machine = @identity.stringify_value(
    context.fragment.candidate.material.graph.value,
    10000,
    1000,
    100,
  )
  assert_true(machine.contains("\"op\":\"typed_null\""))
  let result = evaluate_sequence_components(
    registered_relation_contracts(),
    sequence,
    [],
    ["derive_1"],
    run_limits(),
    { remaining: 100000, max_frames: 100, },
    fragments=Some([context]),
  ).unwrap()
  let output = completed_output(result, Step(1)).unwrap()
  assert_true(
    test_row_output(output).rows[0][1] is Null ||
    test_row_output(output).rows[0][1] is Captured(@admitted.Null),
  )
}
