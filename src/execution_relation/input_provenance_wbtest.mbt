///|
test "raw capture cannot stand in for a successful producer execution" {
  let upstream = row_owner("")
  let producer = @pipeline.produced_input(
    @lower.pipeline(@lower.bound_preparation(upstream)),
    Step(0),
  ).unwrap()
  let checked = @pipeline.check_with_evidence(
    input_cursor("[{\"select\":[\"a\",\"b\"]}]"),
    [("prior", @pipeline.ProducedInput(producer))],
    None,
    Some(input_cursor("\"prior\"")),
    {
      max_steps: 100,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  let owner = @lower.bind_parameters(
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
  assert_true(@pipeline.logical_order(checked, Input(0)) is Some(_))
  // Even the genuine expected values, or a same-count reordering, do not prove
  // upstream completion merely by passing value admission.
  let first = input_cursor("{\"a\":1,\"b\":0}")
  let second = input_cursor("{\"a\":0,\"b\":1}")
  for rows in [[first, second], [second, first], []] {
    let captured = capture_input(
      owner,
      0,
      rows,
      max_rows=2,
      run_limits().input_values,
    ).unwrap()
    assert_true(
      evaluate_sequence_components(
        registered_relation_contracts(),
        prepared_sequence(owner),
        [captured],
        ["select_0"],
        run_limits(),
        { remaining: 10000, max_frames: 100, },
      )
      is Err(InputExecutionEvidencePending(0)),
    )
  }
}
