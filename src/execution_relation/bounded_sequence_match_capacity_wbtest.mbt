///|
test "bounded Sequence constructor keeps complete output and original source while removing only nonexistent input forests" {
  let original : Ref[GeneratedSequence?] = Ref(None)
  let (_, active, input) = bounded_sequence_fixture(text_keys=true, constrain=generated => {
    original.val = Some(generated)
    generated
  })
  let generated = original.val.unwrap()
  let values : ValueLimits = {
    max_nodes: 3300,
    max_text_bytes: 20000000,
    max_depth: 100,
    max_work: 20000000,
  }
  let limits = {
    ..compute_test_limits(),
    rows: {
      ..compute_test_limits().rows,
      input_values: values,
      output_values: values,
    },
    max_work: 20000000,
  }
  let measurement : FixedInputGuardMeasureLimits = {
    max_work: 20000000,
    max_bytes: 20000000,
    max_nodes: 20000000,
    max_depth: 100,
  }
  let full = generated_sequence_capacity(generated, limits, measurement).unwrap()
  let bounded = generated_bounded_sequence_match_capacity(
    generated, limits, measurement, 10000,
  ).unwrap()
  assert_eq(bounded.retained_bytes, full.retained_bytes)
  assert_true(bounded.execution_bytes >= bounded.retained_bytes)
  assert_true(bounded.execution_bytes < full.execution_bytes)
  assert_true(bounded.retained_bytes + bounded.execution_bytes < 536870912L)
  assert_true(
    generated_bounded_sequence_match_capacity(
      generated, limits, measurement, -1,
    )
    is None,
  )
  assert_true(
    generated_bounded_sequence_match_capacity(
      generated,
      { ..limits, rows: { ..limits.rows, operation_entries: -1, }, },
      measurement,
      10000,
    )
    is None,
  )
  let before = producer_read_row_count(input)
  let output = match finish_bounded_sequence(active) {
    BoundedSequenceMatchComplete(output, ..) => output
    _ => fail("original bounded Text Sequence must complete")
  }
  assert_eq(completed_row_count(output), 3)
  cleanup_bounded_sequence_match(active).unwrap() |> ignore
  assert_false(bounded_sequence_match_cleanup_pending(active))
  assert_bounded_sequence_scratch_reclaimed(active)
  // Accepted completion survives scratch cleanup and still supplies its
  // original borrowed cells; the source remains available independently.
  assert_true(completed_output_available(output))
  assert_true(producer_read_available(input))
  assert_eq(producer_read_row_count(input), before)
}

///|
test "bounded Sequence constructor rejects dormant Text predicate construction without changing work refusal" {
  let original : Ref[GeneratedSequence?] = Ref(None)
  let (_, execution, input) = bounded_sequence_try_fixture(
    text_keys=true,
    first_predicate="if(true, value = 1, concat(key, 'x') = 'x')",
    constrain=generated => {
      original.val = Some(generated)
      generated
    },
  )
  let active = execution.unwrap()
  assert_true(
    generated_bounded_sequence_match_capacity(
      original.val.unwrap(),
      compute_test_limits(),
      { max_work: 10000, max_bytes: 10000, max_nodes: 10000, max_depth: 100, },
      10000,
    )
    is None,
  )
  @bounded.request_cancel(bounded_sequence_match_state(active).engine) |> ignore
  for _ in 0..<10000 {
    if advance_bounded_sequence_match(active, 1)
      is Ok(BoundedSequenceMatchStopped(_, ..)) {
      break
    }
  }
  cleanup_bounded_sequence_match(active).unwrap() |> ignore
  assert_false(bounded_sequence_match_cleanup_pending(active))
  assert_true(producer_read_available(input))
  let (_, low, low_input) = bounded_sequence_fixture(text_keys=true, max_work=1)
  assert_true(
    finish_bounded_sequence(low)
    is BoundedSequenceMatchFailed(Rows(RowLimit), ..),
  )
  cleanup_bounded_sequence_match(low).unwrap() |> ignore
  assert_false(bounded_sequence_match_cleanup_pending(low))
  assert_true(producer_read_available(low_input))
}
