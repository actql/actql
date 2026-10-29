///|
test "one original full task lowers once across unchanged preparation requests" {
  let prepared = values_compilation_parts_prepared()
  let limits = prepared_client_values_sequence_limits(prepared)
  let calls = Ref(0)
  let lower = (owner, limits) => {
    calls.val += 1
    @lower.prepare_sequence(owner, limits)
  }
  let first = prepared_client_full_sequence(prepared, 0, limits, prepare=lower).unwrap()
  let second = prepared_client_full_sequence(prepared, 0, limits, prepare=lower).unwrap()
  assert_eq(calls.val, 1)
  assert_true(physical_equal(first, second))
}

///|
test "full sequence retention matches every limit and bounds its task inventory" {
  let prepared = values_compilation_parts_prepared()
  let limits = prepared_client_values_sequence_limits(prepared)
  let calls = Ref(0)
  let lower = (owner, limits) => {
    calls.val += 1
    @lower.prepare_sequence(owner, limits)
  }
  let changed : Array[@lower.SequenceLimits] = [
    { ..limits, max_steps: limits.max_steps + 1, },
    { ..limits, max_rows: limits.max_rows + 1, },
    { ..limits, max_cells: limits.max_cells + 1, },
    { ..limits, max_bindings: limits.max_bindings + 1, },
    { ..limits, max_name_bytes: limits.max_name_bytes + 1, },
    {
      ..limits,
      expressions: {
        ..limits.expressions,
        max_nodes: limits.expressions.max_nodes + 1,
      },
    },
    {
      ..limits,
      expressions: {
        ..limits.expressions,
        max_work: limits.expressions.max_work + 1,
      },
    },
    {
      ..limits,
      expressions: {
        ..limits.expressions,
        max_depth: limits.expressions.max_depth + 1,
      },
    },
    {
      ..limits,
      expressions: {
        ..limits.expressions,
        max_literal_nodes: limits.expressions.max_literal_nodes + 1,
      },
    },
    {
      ..limits,
      expressions: {
        ..limits.expressions,
        max_literal_text_bytes: limits.expressions.max_literal_text_bytes + 1,
      },
    },
  ]
  let mut prior = prepared_client_full_sequence(
    prepared,
    0,
    limits,
    prepare=lower,
  ).unwrap()
  for index in 0..<changed.length() {
    let next = prepared_client_full_sequence(
      prepared,
      0,
      changed[index],
      prepare=lower,
    ).unwrap()
    assert_false(physical_equal(prior, next))
    assert_true(
      physical_equal(
        next,
        prepared_client_full_sequence(
          prepared,
          0,
          changed[index],
          prepare=lower,
        ).unwrap(),
      ),
    )
    assert_eq(calls.val, index + 2)
    assert_eq(prepared.full_sequences.length(), 1)
    prior = next
  }
  let valid = prepared_client_full_sequence(prepared, 0, limits, prepare=lower).unwrap()
  let before_failure = calls.val
  for
    invalid in [
      { ..limits, max_rows: 1, },
      { ..limits, max_cells: 1, },
      { ..limits, max_steps: 0, },
      { ..limits, expressions: { ..limits.expressions, max_work: -1, }, },
    ] {
    assert_true(
      prepared_client_full_sequence(prepared, 0, invalid, prepare=lower)
      is Err(Sequence(_)),
    )
  }
  assert_eq(calls.val, before_failure + 4)
  assert_true(
    physical_equal(
      valid,
      prepared_client_full_sequence(prepared, 0, limits, prepare=lower).unwrap(),
    ),
  )
  assert_eq(calls.val, before_failure + 4)
  for task in [-1, 1] {
    assert_true(
      prepared_client_full_sequence(prepared, task, limits, prepare=lower)
      is Err(MissingTask),
    )
  }
  assert_eq(calls.val, before_failure + 4)
  assert_eq(prepared.full_sequences.length(), 1)
}

///|
test "equal foreign Programs and row-limit views cannot borrow a retained sequence" {
  let original = values_compilation_parts_prepared()
  let foreign = values_compilation_parts_prepared()
  assert_eq(
    prepared_client_identity(original),
    prepared_client_identity(foreign),
  )
  let limits = prepared_client_values_sequence_limits(original)
  let first = prepare_prepared_client_full_sequence(original, 0, limits).unwrap()
  let second = prepare_prepared_client_full_sequence(foreign, 0, limits).unwrap()
  assert_false(physical_equal(first, second))
  assert_false(
    physical_equal(@lower.sequence_owner(first), @lower.sequence_owner(second)),
  )
  let view = with_prepared_client_values_row_limit(original, limits.max_rows).unwrap()
  assert_true(view.full_sequences.is_empty())
  assert_false(
    physical_equal(
      first,
      prepare_prepared_client_full_sequence(view, 0, limits).unwrap(),
    ),
  )
  let tighter = with_prepared_client_values_row_limit(original, 1).unwrap()
  assert_true(
    prepare_prepared_client_full_sequence(
      tighter,
      0,
      prepared_client_values_sequence_limits(tighter),
    )
    is Err(Sequence(_)),
  )
  assert_true(tighter.full_sequences.is_empty())
  assert_true(
    physical_equal(
      first,
      prepare_prepared_client_full_sequence(original, 0, limits).unwrap(),
    ),
  )
}

///|
test "Values compilation carries its first full lowering into the original preparation" {
  let prepared = values_compilation_parts_prepared()
  let limits = prepared_client_values_sequence_limits(prepared)
  assert_true(prepared.full_sequences.is_empty())
  let compiled = issue_prepared_client_values_compilation(
    prepared,
    run_materials_manifests(),
    limits,
    1000,
    1000,
    1000000,
    100000,
    100,
  ).unwrap()
  assert_true(physical_equal(compiled.owner, prepared))
  assert_eq(prepared.full_sequences.length(), 1)
  let retained = prepared.full_sequences[0].sequence
  assert_true(
    physical_equal(
      retained,
      prepare_prepared_client_full_sequence(prepared, 0, limits).unwrap(),
    ),
  )
  let original = issue_client_values_aoa_parts_graph(
    prepared.graph,
    0,
    limits,
    1000000,
    100000,
    100,
  ).unwrap()
  assert_eq(compiled.fragment.logical_cid, original.identity.cid)
  assert_eq(
    compiled.fragment.logical_cid,
    issue_prepared_client_values_aoa_identity(
      prepared, 0, limits, 1000000, 100000, 100,
    ).unwrap().cid,
  )
  assert_true(physical_equal(retained, prepared.full_sequences[0].sequence))
}

///|
test "Task pipeline retains its original full sequence for compilation and execution" {
  let prepared = values_compilation_parts_prepared()
  let limits = prepared_client_values_sequence_limits(prepared)
  assert_true(prepared.full_sequences.is_empty())
  let wire = emit_prepared_client_task_pipeline(
    prepared, 0, limits, 1000000, 100000, 100,
  ).unwrap()
  let expected =
    #|{"output":"values_0","sources":{},"steps":[{"id":"values_0","in":[],"op":"REL.values","params":{"rows":[{"id":1},{"id":2}],"schema":{"id":{"nullable":false,"type":"number"}}}}],"version":"aoa-pipeline/0.1"}
  assert_eq(wire, expected)
  assert_eq(prepared.full_sequences.length(), 1)
  let original = prepared.full_sequences[0].sequence
  assert_true(
    physical_equal(
      original,
      prepare_prepared_client_full_sequence(prepared, 0, limits).unwrap(),
    ),
  )
  assert_eq(
    emit_prepared_client_task_pipeline(
      prepared, 0, limits, 1000000, 100000, 100,
    ).unwrap(),
    expected,
  )
  assert_true(physical_equal(original, prepared.full_sequences[0].sequence))
  let foreign = values_compilation_parts_prepared()
  emit_prepared_client_task_pipeline(foreign, 0, limits, 1000000, 100000, 100).unwrap()
  |> ignore
  assert_false(physical_equal(original, foreign.full_sequences[0].sequence))
  assert_true(
    emit_prepared_client_task_pipeline(
      prepared,
      0,
      { ..limits, max_rows: 1, },
      1000000,
      100000,
      100,
    )
    is Err(Sequence(_)),
  )
  assert_true(physical_equal(original, prepared.full_sequences[0].sequence))
}
