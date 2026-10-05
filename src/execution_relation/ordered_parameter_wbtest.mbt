///|
fn ordered_parameter_preparation() -> (@lower.Prepared, @parameter.Declarations) {
  let declarations = @parameter.read_declarations(
    Some(input_cursor("{\"n\":{\"type\":\"number\",\"nullable\":false}}")),
    { max_parameters: 10, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let pipeline = @pipeline.check(
    input_cursor(
      "[{\"values\":{\"schema\":{\"n\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"n\":2}]},\"as\":\"seed\"},{\"derive\":[{\"saved\":\"n\"},{\"n\":\"saved + $n\"}]},{\"filter\":\"n > 4\"},{\"select\":[\"n\",\"saved\"]}]",
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
  (
    @lower.prepare(pipeline, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    declarations,
  )
}

///|
test "ordered parameter source machine and result preserve distinct field slot and binding identities" {
  let (prepared, declarations) = ordered_parameter_preparation()
  let sequence = prepared_sequence(bind_number(prepared, declarations, 3))
  let context = ordered_sequence_fragment_context(sequence, 10000L)
  let binding = context.fragment.candidate.material.ordered.unwrap()
  let source = @identity.stringify_value(
    binding.node.source.value,
    10000,
    1000,
    100,
  )
  assert_eq(
    source, "{\"id\":\"derive_1\",\"in\":[\"input\"],\"op\":\"REL.derive\",\"params\":{\"bindings\":[{\"expr\":{\"field\":\"n\"},\"name\":\"saved\"},{\"expr\":{\"add\":[{\"field\":\"saved\"},{\"$param\":\"n\"}]},\"name\":\"n\"}]}}",
  )
  let machine = @identity.stringify_value(
    binding.node.graph.value,
    10000,
    1000,
    100,
  )
  assert_eq(
    machine, "{\"id\":\"derive_1\",\"in\":[\"input\"],\"op\":\"REL.derive\",\"params\":{\"bindings\":[{\"expr\":{\"body\":\"n\",\"op\":\"field\"},\"name\":\"saved\"},{\"expr\":{\"body\":[{\"body\":\"saved\",\"op\":\"field\"},{\"body\":3,\"op\":\"literal\"}],\"op\":\"add\"},\"name\":\"n\"}],\"references\":[{\"at\":\"/bindings/0/expr\",\"target\":{\"input_field\":\"n\"}},{\"at\":\"/bindings/1/expr/body/0\",\"target\":{\"prior_slot\":0}}],\"row_kernel_contract_cid\":\"sha256:18c717048b5ca41eca1be358683b26fba7f9c19ca70abe7ee1051aaa84bf6c62\"}}",
  )
  let contracts = registered_relation_contracts()
  let generated = prepare_generated_sequence(
    contracts,
    sequence,
    [context, sequence_fragment_context(sequence, 2, 1L)],
    ["select_3"],
    100000,
    10000,
  ).unwrap()
  let limits : SequenceExecutionLimits = {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }
  let result = execute_generated_sequence(generated, [], limits).unwrap()
  let output = completed_output(result, Step(3)).unwrap()
  assert_eq(completed_row_count(output), 1)
  assert_eq(completed_column_name(output, 0), Some("n"))
  assert_eq(completed_column_name(output, 1), Some("saved"))
  assert_true(completed_cell(output, 0, 0) is Some(Number(5.0)))
  assert_true(completed_cell(output, 0, 1) is Some(Number(2.0)))
  let other = prepared_sequence(bind_number(prepared, declarations, 4))
  let other_context = ordered_sequence_fragment_context(other, 10000L)
  assert_eq(
    @identity.stringify_value(
      other_context.fragment.candidate.material.ordered.unwrap().node.source.value,
      10000,
      1000,
      100,
    ),
    source,
  )
  assert_true(
    other_context.fragment.candidate.material.ordered.unwrap().node.graph.cid !=
    binding.node.graph.cid,
  )
  assert_true(
    prepare_generated_sequence(
      contracts,
      sequence,
      [other_context, sequence_fragment_context(sequence, 2, 1L)],
      ["select_3"],
      100000,
      10000,
    )
    is Err(FragmentContext(1, KernelMismatch)),
  )
  assert_true(execute_generated_sequence(generated, [], limits) is Ok(_))
}
