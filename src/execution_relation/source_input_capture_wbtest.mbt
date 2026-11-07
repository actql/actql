///|
test "whole Source input capture borrows original rows before Select without completing Compute" {
  let owner = input_owner()
  let rows = capture_input(
    owner,
    0,
    [input_cursor("{\"n\":3,\"s\":\"original\"}")],
    max_rows=1,
    run_limits().input_values,
  ).unwrap()
  let live = Ref(true)
  let read = prepare_supplied_relation_read(owner, 0, rows, () => live.val).unwrap()
  let output = capture_supplied_source_input(
    registered_relation_contracts(),
    prepared_sequence(owner),
    read,
    2,
    2,
  ).unwrap()
  assert_true(
    output.table is Some(AdmittedTable(table)) &&
    physical_equal(table.rows, rows.rows),
  )
  assert_eq(output.target, @pipeline.Input(0))
  assert_true(completed_source_input_matches_read(output, read))
  // No local Step ran and no pending task may be completed by this input fact.
  assert_true(output.completion.readmitted)
  assert_false(completed_output_matches_supplied_inputs(output, [read]))
  let bound = bind_completed_source_input_operation(owner, 0, 0, output, read).unwrap()
  let consumer = prepare_producer_read(owner, bound, 10, 100).unwrap()
  assert_true(producer_read_matches_operation_input(consumer, owner, 0, 0))
  assert_true(producer_read_cell(consumer, 0, 0) is Some(Number(3.0)))
  assert_true(producer_read_cell(consumer, 0, 1) is Some(Text("original")))
  live.val = false
  assert_false(completed_source_input_matches_read(output, read))
  assert_false(producer_read_available(consumer))
  assert_true(producer_read_cell(consumer, 0, 0) is None)
}

///|
test "whole Source capture refuses equal replacement reads foreign owners and short metadata" {
  let owner = input_owner()
  let rows = capture_input(
    owner,
    0,
    [input_cursor("{\"n\":1,\"s\":\"x\"}")],
    max_rows=1,
    run_limits().input_values,
  ).unwrap()
  let read = prepare_supplied_relation_read(owner, 0, rows, () => true).unwrap()
  let contracts = registered_relation_contracts()
  let sequence = prepared_sequence(owner)
  assert_true(
    capture_supplied_source_input(contracts, sequence, read, 1, 2) is Err(Limit),
  )
  assert_true(
    capture_supplied_source_input(contracts, sequence, read, 2, 1) is Err(Limit),
  )
  assert_true(
    capture_supplied_source_input(contracts, sequence, read, -1, 2)
    is Err(InvalidLimits),
  )
  assert_true(
    capture_supplied_source_input(
      contracts,
      prepared_sequence(input_owner()),
      read,
      2,
      2,
    )
    is Err(ForeignInputs),
  )
  let output = capture_supplied_source_input(contracts, sequence, read, 2, 2).unwrap()
  let replacement = prepare_supplied_relation_read(owner, 0, rows, () => true).unwrap()
  assert_false(completed_source_input_matches_read(output, replacement))
  assert_true(
    bind_completed_source_input_operation(owner, 0, 0, output, replacement)
    is Err(ProducerUnavailable),
  )
  assert_true(
    bind_completed_source_input_operation(owner, 1, 0, output, read)
    is Err(ProducerBindingMismatch),
  )
}

///|
test "whole Source input capture retains conditional omission and NULL in same original array" {
  let owner = presence_input_owner()
  let input = prepare_admitted_input(owner, 0, 2, stream_value_limits()).unwrap()
  for wire in ["{\"id\":1}", "{\"id\":2,\"p\":null}"] {
    append_admitted_input_presence(
      input,
      read_retained_relation_row(
        input.buffer.schema,
        wire,
        retained_row_test_limits(),
        stream_value_limits(),
      ).unwrap(),
    ).unwrap()
  }
  let rows = finish_admitted_input(input).unwrap()
  let read = prepare_supplied_relation_read(owner, 0, rows, () => true).unwrap()
  let output = capture_supplied_source_input(
    registered_relation_contracts(),
    prepared_sequence(owner),
    read,
    2,
    3,
  ).unwrap()
  assert_true(
    output.table is Some(PresenceTable(table)) &&
    physical_equal(table.rows, rows.presence_rows),
  )
  assert_true(completed_presence_cell(output, 0, 1) is Ok(Absent))
  assert_true(
    completed_presence_cell(output, 1, 1) is Ok(Present(@admitted.Null)),
  )
}
