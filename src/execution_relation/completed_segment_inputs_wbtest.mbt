///|
test "completed segment inventory keeps both original JOIN ports and rejects substitutions" {
  let (_, initial, reads) = bounded_join_fixture()
  let owner = reads[0].bound.receiver
  let sequence = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["join_0"],
    100000,
    10000,
  ).unwrap()
  // The selected execution really consumes both reads retained below.
  let execution = start_bounded_join(
    @bounded.control(),
    sequence,
    trusted_output_relation_input(reads[0]),
    trusted_output_relation_input(reads[1]),
    100,
    run_limits().input_values,
    run_limits().output_values,
    100000,
    100,
    1000,
    10000,
  ).unwrap()
  let live = Ref(true)
  let output = restrict_completed_output(
    finish_bounded_join_test(execution).unwrap(),
    () => live.val,
  )
  let inputs = [(0, 0, reads[0]), (0, 1, reads[1])]
  let value = retain_completed_segment_inputs(output, sequence, inputs, 100).unwrap()
  let borrowed = completed_segment_inputs_output(value, sequence, inputs).unwrap()
  assert_true(physical_equal(borrowed, output))
  assert_eq(completed_row_count(borrowed), 1)
  assert_true(completed_cell(borrowed, 0, 0) is Some(Number(1)))
  assert_true(completed_cell(borrowed, 0, 1) is Some(Number(10)))
  assert_true(completed_cell(borrowed, 0, 2) is Some(Number(20)))
  for
    invalid in [
      [],
      [inputs[0]],
      [inputs[1]],
      [inputs[1], inputs[0]],
      [inputs[0], inputs[0]],
      [(0, 0, reads[0]), (0, 1, reads[0])],
      [(1, 0, reads[0]), (1, 1, reads[1])],
    ] {
    assert_true(
      retain_completed_segment_inputs(output, sequence, invalid, 100) is None,
    )
    assert_true(
      completed_segment_inputs_output(value, sequence, invalid) is None,
    )
  }
  let rebound = prepare_producer_read(owner, reads[0].bound, 100, 10000).unwrap()
  assert_true(
    completed_segment_inputs_output(value, sequence, [
      (0, 0, rebound),
      inputs[1],
    ])
    is None,
  )
  let (_, foreign_execution, foreign_reads) = bounded_join_fixture()
  assert_true(
    retain_completed_segment_inputs(
      output,
      sequence,
      [(0, 0, foreign_reads[0]), (0, 1, foreign_reads[1])],
      100,
    )
    is None,
  )
  assert_true(
    retain_completed_segment_inputs(output, sequence, inputs, 0) is None,
  )
  assert_true(
    retain_completed_segment_inputs(output, sequence, inputs, 1) is None,
  )
  inputs.clear()
  assert_true(
    completed_segment_inputs_output(value, sequence, [
      (0, 0, reads[0]),
      (0, 1, reads[1]),
    ])
    is Some(_),
  )
  assert_true(cleanup_bounded_join(execution).unwrap())
  // The acknowledged output's owning scope, not provider cleanup alone,
  // determines its borrowed lifetime.
  live.val = false
  assert_true(
    completed_segment_inputs_output(value, sequence, [
      (0, 0, reads[0]),
      (0, 1, reads[1]),
    ])
    is None,
  )
  ignore(finish_bounded_join_test(initial).unwrap())
  assert_true(cleanup_bounded_join(initial).unwrap())
  ignore(finish_bounded_join_test(foreign_execution).unwrap())
  assert_true(cleanup_bounded_join(foreign_execution).unwrap())
}

///|
test "completed segment view preserves readmission and the exact terminal representation" {
  let (_, execution, reads) = bounded_join_fixture()
  let live = Ref(true)
  let output = restrict_completed_output(
    finish_bounded_join_test(execution).unwrap(),
    () => live.val,
  )
  let sequence = prepare_generated_sequence(
    registered_relation_contracts(),
    output.completion.sequence,
    [],
    ["join_0"],
    100000,
    10000,
  ).unwrap()
  let readmitted = {
    ..output,
    completion: { ..output.completion, readmitted: true, },
  }
  let inputs = [(0, 0, reads[0]), (0, 1, reads[1])]
  let value = retain_completed_segment_inputs(readmitted, sequence, inputs, 100).unwrap()
  let borrowed = completed_segment_inputs_output(value, sequence, inputs).unwrap()
  assert_true(borrowed.completion.readmitted)
  assert_true(
    physical_equal(
      borrowed.completion.result_identity,
      output.completion.result_identity,
    ),
  )
  assert_true(
    physical_equal(
      borrowed.completion.input_bindings,
      output.completion.input_bindings,
    ),
  )
  assert_true(physical_equal(borrowed.table, output.table))
  assert_true(cleanup_bounded_join(execution).unwrap())
  live.val = false
  assert_true(completed_segment_inputs_output(value, sequence, inputs) is None)
  assert_true(completed_segment_inputs_construction_inventory(-1) is None)
  assert_eq(
    completed_segment_inputs_construction_inventory(2).unwrap().reference_slots,
    6L,
  )
}

///|
test "completed segment inventory includes pinned copied array backing" {
  let value = completed_segment_inputs_construction_inventory(2).unwrap()
  assert_eq(value.record_headers, 3L)
  assert_eq(value.reference_slots, 6L)
  assert_eq(value.scalar_words, 2L)
  assert_eq(value.owned_wire_bytes, 0L)
  assert_eq(value.owned_utf16_units, 0L)
}
