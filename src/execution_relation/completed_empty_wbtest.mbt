///|
test "typed completion preserves nullable values all-null stable ties and empty input" {
  for
    (rows, count, last_null, last_b) in [
      ("[{\"a\":null,\"b\":7},{\"a\":null,\"b\":8}]", 2, true, 8),
      ("[{\"a\":null,\"b\":7},{\"a\":0,\"b\":8}]", 2, false, 8),
      ("[{\"a\":null,\"b\":7},{\"a\":null,\"b\":7}]", 2, true, 7),
      ("[]", 0, true, 0),
    ] {
    let owner = bound_pipeline(
      "[{\"values\":{\"schema\":{\"a\":{\"type\":\"number\",\"nullable\":true},\"b\":{\"type\":\"number\",\"nullable\":false}},\"rows\":" +
      rows +
      "},\"as\":\"seed\"},{\"derive\":[{\"a\":\"a + 1\"}]}]",
    )
    let sequence = prepared_sequence(owner)
    let generated = prepare_generated_sequence(
      registered_relation_contracts(),
      sequence,
      [ordered_sequence_fragment_context(sequence, 1000L)],
      ["derive_1"],
      100000,
      10000,
    ).unwrap()
    let source = completed_output(test_typed_completion(generated, 7), Step(1)).unwrap()
    let receiver = typed_receiver(
      owner, "[{\"select\":[\"b\",\"a\"]},{\"sort\":[{\"field\":\"a\",\"dir\":\"asc\",\"nulls\":\"first\"}]}]",
    )
    let consumer = prepare_generated_sequence(
      registered_relation_contracts(),
      prepared_sequence(receiver),
      [],
      ["sort_1"],
      100000,
      10000,
    ).unwrap()
    let binding = bind_completed_input(receiver, 0, owner, source).unwrap()
    let completion = execute_generated_sequence(
      consumer,
      [],
      { rows: run_limits(), max_work: 100000, max_frames: 100, },
      produced=[binding],
    ).unwrap()
    let output = completed_output(completion, Step(1)).unwrap()
    assert_true(output.table is NumberTable(_))
    assert_eq(completed_row_count(output), count)
    assert_eq(completed_column_count(output), 2)
    assert_eq(completed_column_name(output, 0), Some("b"))
    if count > 0 {
      assert_true(completed_cell(output, 0, 0) is Some(Number(7)))
      assert_true(
        completed_cell(output, 1, 0) is Some(Number(n)) &&
        n == last_b.to_double(),
      )
      assert_true(completed_cell(output, 0, 1) is Some(Null))
      if last_null {
        assert_true(completed_cell(output, 1, 1) is Some(Null))
      } else {
        assert_true(completed_cell(output, 1, 1) is Some(Number(1)))
      }
    } else {
      assert_true(completed_cell(output, 0, 0) is None)
    }
  }
}

///|
test "zero-column typed input crosses product completion and producer no-ops" {
  // Empty-schema author values are not accepted. Use the established lawful
  // explicit-input fixture rather than weakening author admission.
  let (generated, captured) = numeric_layout_fixture(ZeroColumns, 3)
  let sequence = generated.sequence
  let owner = @lower.sequence_owner(sequence)
  let contracts = registered_relation_contracts()
  let control = { remaining: 100000, max_frames: 100, }
  let limits = run_limits()
  let invocation = prepare_sequence_with_importers(
    contracts,
    sequence,
    [captured],
    ["sort_1"],
    limits,
    control,
    fn(captured) {
      if @schema.field_count(captured.schema) != 0 ||
        !spend_control(control, captured.rows.length()) {
        return Err(InvalidRows)
      }
      Ok(
        NumberTable({
          owner: captured.owner,
          id: @lower.input_id(@lower.bound_preparation(owner), 0).unwrap(),
          names: [],
          columns: [],
          count: captured.rows.length(),
          selection: None,
        }),
      )
    },
    fn(_, _, _) { Err(InvalidRows) },
    reserve_storage=Some(reserve_completed_storage),
    produced=[],
    fragments=Some(generated.contexts),
    ordered={ contexts: [], max_bytes: 0, max_nodes: 0, max_depth: 0, },
  ).unwrap()
  let producer = run_completed_sequence_backend(
    invocation,
    fn(_) { Err(InvalidRows) },
    (kernel, input, logical) => {
      evaluate_completed_rows(
        kernel,
        input,
        limits.max_rows,
        control,
        invocation.output_budget,
        { limit: limits.operation_entries, live: 0, peak: 0, },
        logical,
      )
    },
    store => PhysicalStore(store),
  ).unwrap()
  let source = completed_output(producer, Step(1)).unwrap()
  let receiver = typed_receiver(owner, "[{\"drop\":[]},{\"sort\":[]}]")
  let consumer = prepare_generated_sequence(
    contracts,
    prepared_sequence(receiver),
    [],
    ["sort_1"],
    100000,
    10000,
  ).unwrap()
  let binding = bind_completed_input(receiver, 0, owner, source).unwrap()
  let completion = execute_generated_sequence(
    consumer,
    [],
    { rows: limits, max_work: 100000, max_frames: 100, },
    produced=[binding],
  ).unwrap()
  let output = completed_output(completion, Step(1)).unwrap()
  assert_true(output.table is NumberTable(_))
  assert_eq(completed_row_count(output), 3)
  assert_eq(completed_column_count(output), 0)
  assert_true(completed_cell(output, 2, 0) is None)
}
