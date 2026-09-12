///|
fn ordered_sequence_fragment_context(
  sequence : @lower.PreparedSequence,
  work : Int64,
  limits? : LogicalLimits? = None,
) -> FragmentRuntimeContext raise {
  let context = execution_for(sequence, work, limits~).contexts[0]
  let pipeline = @lower.prepare_fragment_pipeline(sequence, 1, {
    max_roots: 100,
    max_pointer_bytes: 10000,
    max_work: 100000,
  }).unwrap()
  let request = @lower.prepare_fragment_request(
    pipeline,
    10L,
    1000L,
    row_limits=Some(context.limits),
  ).unwrap()
  prepare_runtime_fragment(
    request,
    test_fragment_contract(),
    material_demands(),
    registry_limits(),
    context.limits,
    ordered=Some(context.params.contract),
  ).unwrap()
}

///|
test "checked ordered fragment supplies its own limits through the common four-operation driver" {
  let sequence = prepared_sequence(
    row_owner(
      ",{\"derive\":[{\"old\":\"a\"},{\"a\":\"old + 1\"},{\"total\":\"old + a\"}]},{\"filter\":\"total > 1\"},{\"select\":[\"total\",\"a\"]}",
    ),
  )
  let ordered = ordered_sequence_fragment_context(sequence, 84L)
  let filter = sequence_fragment_context(sequence, 2, 2L)
  let contracts = registered_relation_contracts()
  let run = fn(context) {
    evaluate_sequence_components(
      contracts,
      sequence,
      [],
      ["select_3"],
      run_limits(),
      { remaining: 100000, max_frames: 100, },
      fragments=Some([context, filter]),
    )
  }
  let output = completed_output(run(ordered).unwrap(), Step(3)).unwrap().table
  assert_eq(output.names, ["total", "a"])
  assert_eq(output.rows.length(), 1)
  assert_true(output.rows[0][0] is Number(3.0))
  assert_true(output.rows[0][1] is Number(2.0))
  let tight = prepare_fragment_runtime_context(
    ordered.fragment,
    { ..ordered.limits, max_work: 83L, },
    registry_limits(),
  ).unwrap()
  assert_true(run(tight) is Err(Rows(1, _)))
  assert_true(run(ordered) is Ok(_))
  for
    larger in [
      { ..ordered.limits, max_work: 85L, },
      { ..ordered.limits, max_input_rows: 3L, },
      { ..ordered.limits, max_value_bytes: 32L, },
      { ..ordered.limits, max_live_value_bytes: 79L, },
    ] {
    assert_true(
      prepare_fragment_runtime_context(
        ordered.fragment,
        larger,
        registry_limits(),
      )
      is Err(ExceedsRequest),
    )
  }
  assert_true(
    evaluate_sequence_components(
      contracts,
      sequence,
      [],
      ["select_3"],
      run_limits(),
      { remaining: 100000, max_frames: 100, },
      fragments=Some([filter]),
    )
    is Err(MissingFragmentContext(1)),
  )
  let legacy = execution_for(sequence, 84L)
  assert_true(
    evaluate_sequence_components(
      contracts,
      sequence,
      [],
      ["select_3"],
      run_limits(),
      { remaining: 100000, max_frames: 100, },
      fragments=Some([ordered, filter]),
      ordered=legacy,
    )
    is Err(MixedExecutionConfiguration),
  )
}

///|
test "checked ordered execution preserves row-major failure even for a discarded binding" {
  let sequence = prepared_sequence(
    row_owner(
      ",{\"derive\":[{\"x\":\"1 / a\"},{\"y\":\"1 / b\"}]},{\"select\":[\"a\"]}",
    ),
  )
  let context = ordered_sequence_fragment_context(sequence, 10000L)
  let result = evaluate_sequence_components(
    registered_relation_contracts(),
    sequence,
    [],
    ["select_2"],
    run_limits(),
    { remaining: 100000, max_frames: 100, },
    fragments=Some([context]),
  )
  assert_true(
    result
    is Err(Rows(1, Evaluation(0, 1, { kind: Scalar(ArithmeticFailure), .. }))),
  )
}
