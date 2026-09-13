///|
fn sequence_fragment_context(
  sequence : @lower.PreparedSequence,
  step : Int,
  rows : Int64,
) -> FragmentRuntimeContext raise {
  let pipeline = @lower.prepare_fragment_pipeline(sequence, step, {
    max_roots: 100,
    max_pointer_bytes: 10000,
    max_work: 100000,
  }).unwrap()
  let request = @lower.prepare_fragment_request(pipeline, 10L, 1000L).unwrap()
  prepare_runtime_fragment(
    request,
    test_fragment_contract(),
    material_demands(),
    registry_limits(),
    {
      max_input_rows: rows,
      max_value_bytes: 1000L,
      max_live_value_bytes: 10000L,
      max_work: 100000L,
    },
  ).unwrap()
}

///|
test "checked map and filter fragments drive the existing four-operation sequence" {
  let sequence = prepared_sequence(
    row_owner(
      ",{\"derive\":{\"c\":\"a + 10\"}},{\"filter\":\"c > 10\"},{\"select\":[\"c\",\"b\"]}",
    ),
  )
  let map = sequence_fragment_context(sequence, 1, 2L)
  let filter = sequence_fragment_context(sequence, 2, 2L)
  let result = evaluate_sequence_components(
    registered_relation_contracts(),
    sequence,
    [],
    ["select_3"],
    run_limits(),
    { remaining: 100000, max_frames: 100, },
    fragments=Some([map, filter]),
  ).unwrap()
  let output = test_row_store(result).tables[3].unwrap().table
  assert_eq(output.names, ["c", "b"])
  assert_eq(output.rows.length(), 1)
  assert_true(output.rows[0][0] is Number(11.0))
  // The second operation receives its own fixed context, not the first one's
  // remaining counters or a fresh permissive default.
  let tight = sequence_fragment_context(sequence, 2, 1L)
  assert_true(
    evaluate_sequence_components(
      registered_relation_contracts(),
      sequence,
      [],
      ["select_3"],
      run_limits(),
      { remaining: 100000, max_frames: 100, },
      fragments=Some([map, tight]),
    )
    is Err(Rows(2, LogicalRows(InputRowLimit))),
  )
  assert_true(
    evaluate_sequence_components(
      registered_relation_contracts(),
      sequence,
      [],
      ["select_3"],
      run_limits(),
      { remaining: 100000, max_frames: 100, },
      fragments=Some([map]),
    )
    is Err(MissingFragmentContext(2)),
  )
  assert_true(
    evaluate_sequence_components(
      registered_relation_contracts(),
      sequence,
      [],
      ["select_3"],
      run_limits(),
      { remaining: 100000, max_frames: 100, },
      fragments=Some([map, map]),
    )
    is Err(FragmentContext(1, KernelMismatch)),
  )
}

///|
test "fragment context preflight rejects missing and foreign evidence before RHS failure" {
  let make = fn() {
    prepared_sequence(row_owner(",{\"derive\":{\"unused\":\"1 / b\"}}"))
  }
  let sequence = make()
  let foreign = sequence_fragment_context(make(), 1, 2L)
  assert_true(
    evaluate_sequence_components(
      registered_relation_contracts(),
      sequence,
      [],
      ["derive_1"],
      run_limits(),
      { remaining: 100000, max_frames: 100, },
      fragments=Some([]),
    )
    is Err(MissingFragmentContext(1)),
  )
  assert_true(
    evaluate_sequence_components(
      registered_relation_contracts(),
      sequence,
      [],
      ["derive_1"],
      run_limits(),
      { remaining: 100000, max_frames: 100, },
      fragments=Some([foreign]),
    )
    is Err(FragmentContext(1, KernelMismatch)),
  )
}
