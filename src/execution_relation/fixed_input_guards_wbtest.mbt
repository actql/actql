///|
fn fixed_input_generated(
  owner : @lower.BoundPrepared,
) -> GeneratedSequence raise {
  let sequence = prepared_sequence(owner)
  prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [sequence_fragment_context(sequence, 0, 10L)],
    ["select_1"],
    100000,
    10000,
  ).unwrap()
}

///|
fn fixed_input_material(owner : @lower.BoundPrepared) -> CapturedRows {
  capture_input(
    owner,
    0,
    [
      input_cursor("{\"id\":3}"),
      input_cursor("{\"id\":1}"),
      input_cursor("{\"id\":2}"),
    ],
    max_rows=3,
    run_limits().input_values,
  ).unwrap()
}

///|
test "fixed input boundaries retain exact owners without exposing mutable preparation" {
  let owner = wire_input_owner()
  let generated = fixed_input_generated(owner)
  assert_true(physical_equal(generated_sequence_owner(generated), owner))
  assert_eq(generated_retained_count(generated), 1)
  assert_eq(generated_retained_at(generated, -1), None)
  assert_eq(generated_retained_at(generated, 0), Some("select_1"))
  assert_eq(generated_retained_at(generated, 1), None)
  let input = fixed_input_material(owner)
  let equal_input = fixed_input_material(owner)
  let wire = identify_captured_rows(input, row_wire_limits()).unwrap()
  let equal_wire = identify_captured_rows(equal_input, row_wire_limits()).unwrap()
  assert_eq(row_wire_cid(wire), row_wire_cid(equal_wire))
  assert_true(row_wire_matches_captured(wire, input))
  assert_false(row_wire_matches_captured(wire, equal_input))
  let physical : FixedInputGuardMeasureLimits = {
    max_work: 11,
    max_bytes: 5,
    max_nodes: 5,
    max_depth: 100,
  }
  let foreign = fixed_input_material(wire_input_owner())
  assert_true(
    execute_fixed_input_guarded(
      generated,
      foreign,
      Step(1),
      compute_test_limits(),
      max_output_rows=2,
      max_value_bytes=5,
      physical,
    )
    is Err(ForeignInput),
  )
  assert_true(
    execute_fixed_input_guarded(
      generated,
      foreign,
      Step(1),
      compute_test_limits(),
      max_output_rows=-1,
      max_value_bytes=5,
      physical,
    )
    is Err(InvalidLimits),
  )
  // The accessor conveys ownership, not permission to bypass execution checks.
  assert_true(
    execute_fixed_input_guarded(
      generated,
      input,
      Step(0),
      compute_test_limits(),
      max_output_rows=2,
      max_value_bytes=5,
      physical,
    )
    is Err(MissingOutput),
  )
}

///|
test "fixed input measurement spans input contexts and output with exact exhaustion frontiers" {
  let owner = wire_input_owner()
  let generated = fixed_input_generated(owner)
  let input = fixed_input_material(owner)
  // Three input rows/cells, one context, two output rows/cells: 11 work, 5 bytes/nodes.
  let exact : FixedInputGuardMeasureLimits = {
    max_work: 11,
    max_bytes: 5,
    max_nodes: 5,
    max_depth: 100,
  }
  for work in [5, 6, 10] {
    assert_true(
      execute_fixed_input_guarded(
        generated,
        input,
        Step(1),
        compute_test_limits(),
        max_output_rows=2,
        max_value_bytes=5,
        { ..exact, max_work: work, },
      )
      is Err(MeasurementWork),
    )
  }
  assert_true(
    execute_fixed_input_guarded(
      generated,
      input,
      Step(1),
      compute_test_limits(),
      max_output_rows=2,
      max_value_bytes=5,
      { ..exact, max_bytes: 2, },
    )
    is Err(Measurement(InputValues, 2, 0, _)),
  )
  assert_true(
    execute_fixed_input_guarded(
      generated,
      input,
      Step(1),
      compute_test_limits(),
      max_output_rows=2,
      max_value_bytes=5,
      { ..exact, max_nodes: 4, },
    )
    is Err(Measurement(Output, 1, 0, _)),
  )
  for _ in 0..<2 {
    let (completed, usage) = execute_fixed_input_guarded(
      generated,
      input,
      Step(1),
      compute_test_limits(),
      max_output_rows=2,
      max_value_bytes=5,
      exact,
    ).unwrap()
    assert_eq(usage, (11, 5, 5))
    let output = completed_output(completed, Step(1)).unwrap()
    assert_eq(completed_row_count(output), 2)
    assert_true(completed_cell(output, 0, 0) is Some(Number(3)))
    assert_true(completed_cell(output, 1, 0) is Some(Number(2)))
    assert_true(physical_equal(captured_owner(input), owner))
  }
}

///|
test "fixed input root ceiling does not mutate prepared contexts or re-evaluate expressions" {
  let owner = wire_input_owner()
  let generated = fixed_input_generated(owner)
  let input = fixed_input_material(owner)
  let physical : FixedInputGuardMeasureLimits = {
    max_work: 100,
    max_bytes: 100,
    max_nodes: 100,
    max_depth: 100,
  }
  // Input values fit, but false on input row 1 needs five bytes.
  assert_true(
    execute_fixed_input_guarded(
      generated,
      input,
      Step(1),
      compute_test_limits(),
      max_output_rows=2,
      max_value_bytes=4,
      physical,
    )
    is Err(
      Execution(
        Rows(
          0,
          Evaluation(
            1,
            0,
            { kind: LogicalValue(ValueMeasure(WireMeasureFailure)), .. }
          )
        )
      )
    ),
  )
  assert_true(
    execute_fixed_input_guarded(
      generated,
      input,
      Step(1),
      compute_test_limits(),
      max_output_rows=2,
      max_value_bytes=5,
      physical,
    )
    is Ok(_),
  )
  assert_true(
    execute_generated_sequence(generated, [input], compute_test_limits())
    is Ok(_),
  )
}
