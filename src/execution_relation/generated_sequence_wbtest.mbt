///|
test "generated composition owns its selection and contexts and reuses no counters" {
  let sequence = prepared_sequence(
    row_owner(
      ",{\"derive\":[{\"old\":\"a\"},{\"a\":\"old + 1\"},{\"total\":\"old + a\"}]},{\"filter\":\"total > 1\"},{\"select\":[\"total\",\"a\"]}",
    ),
  )
  let contexts = [
    ordered_sequence_fragment_context(sequence, 84L),
    sequence_fragment_context(sequence, 2, 2L),
  ]
  let selected = ["select_3"]
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    contexts,
    selected,
    100000,
    10000,
  ).unwrap()
  contexts.clear()
  selected[0] = "missing"
  let limits : SequenceExecutionLimits = {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }
  assert_true(
    execute_generated_sequence(generated, [], { ..limits, max_work: 0, })
    is Err(_),
  )
  for _i = 0; _i < 2; _i = _i + 1 {
    let completed = execute_generated_sequence(generated, [], limits).unwrap()
    let output = test_row_output(completed_output(completed, Step(3)).unwrap())
    assert_eq(output.names, ["total", "a"])
    assert_eq(output.rows.length(), 1)
    assert_true(output.rows[0][0] is Number(3.0))
    assert_true(output.rows[0][1] is Number(2.0))
  }
}

///|
test "generated composition rejects incomplete and foreign fragments before execution" {
  let make = fn() {
    prepared_sequence(row_owner(",{\"derive\":{\"x\":\"a + 1\"}}"))
  }
  let sequence = make()
  let contracts = registered_relation_contracts()
  assert_true(
    prepare_generated_sequence(
      contracts,
      sequence,
      [],
      ["derive_1"],
      100000,
      10000,
    )
    is Err(MissingFragmentContext(1)),
  )
  let foreign = sequence_fragment_context(make(), 1, 2L)
  assert_true(
    prepare_generated_sequence(
      contracts,
      sequence,
      [foreign],
      ["derive_1"],
      100000,
      10000,
    )
    is Err(FragmentContext(1, KernelMismatch)),
  )
  let valid = sequence_fragment_context(sequence, 1, 2L)
  assert_true(
    prepare_generated_sequence(
      contracts,
      sequence,
      [valid],
      ["derive_1"],
      100000,
      0,
    )
    is Err(Wiring(Limit)),
  )
  let generated = prepare_generated_sequence(
    contracts,
    sequence,
    [valid],
    ["derive_1"],
    100000,
    10000,
  ).unwrap()
  let completed = execute_generated_sequence(generated, [], {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }).unwrap()
  let output = test_row_output(completed_output(completed, Step(1)).unwrap())
  assert_eq(output.rows.length(), 2)
}

///|
test "generated analytic aggregate expressions require their exact fragment" {
  let sequence = prepared_sequence(
    bound_pipeline(
      "[{\"values\":{\"schema\":{\"amount\":{\"type\":\"number\",\"nullable\":false},\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"amount\":0,\"id\":1}]},\"as\":\"seed\"},{\"analytic\":{\"partition_by\":[],\"order_by\":[{\"id\":\"asc\"}],\"frame\":{\"start\":\"unbounded_preceding\",\"end\":\"current_row\"},\"functions\":{\"lowest\":{\"fn\":\"min\",\"expr\":\"10 / amount\",\"filter\":\"amount > 0\"}}}}]",
    ),
  )
  let contracts = registered_relation_contracts()
  assert_true(
    prepare_generated_sequence(
      contracts,
      sequence,
      [],
      ["analytic_1"],
      100000,
      10000,
    )
    is Err(MissingFragmentContext(1)),
  )
  let context = sequence_fragment_context(sequence, 1, 1L)
  assert_true(
    prepare_generated_sequence(
      contracts,
      sequence,
      [context],
      ["analytic_1"],
      100000,
      10000,
    )
    is Ok(_),
  )
}

///|
test "generated row capability inspection rejects other prepared step kinds" {
  let row = input_owner()
  let row_sequence = prepared_sequence(row)
  let row_generated = prepare_generated_sequence(
    registered_relation_contracts(),
    row_sequence,
    [],
    ["select_0"],
    100000,
    10000,
  ).unwrap()
  assert_true(
    generated_sequence_all_row_kernels(row_generated, fn(body) {
      body is @lower.Select(_)
    }),
  )
  assert_false(generated_sequence_all_row_kernels(row_generated, _ => false))

  let values_owner = row_owner("")
  let values_sequence = prepared_sequence(values_owner)
  let values_node = @lower.node_at(@lower.bound_preparation(values_owner), 0).unwrap()
  let values_generated = prepare_generated_sequence(
    registered_relation_contracts(),
    values_sequence,
    [],
    [@lower.node_id(values_node)],
    100000,
    10000,
  ).unwrap()
  assert_false(generated_sequence_all_row_kernels(values_generated, _ => true))
  assert_true(
    generated_sequence_all_steps(values_generated, fn(step) {
      step is @lower.ValuesStep(_)
    }),
  )
  assert_false(generated_sequence_all_steps(values_generated, _ => false))
  let selected = select_generated_sequence_step(values_generated, 0).unwrap()
  assert_eq(generated_sequence_step_count(selected), 1)
  assert_eq(generated_sequence_step_index_at(selected, 0), Some(0))
  assert_true(generated_sequence_step_index_at(selected, 1) is None)
  assert_true(
    generated_sequence_step_at(selected, 0) is Some(@lower.ValuesStep(_)),
  )
  assert_true(
    generated_sequence_all_steps(selected, fn(step) {
      step is @lower.ValuesStep(_)
    }),
  )
  assert_true(select_generated_sequence_step(values_generated, -1) is None)
  assert_true(select_generated_sequence_step(values_generated, 1) is None)
}
