///|
test "segment retention preserves readmitted status identity bindings and values and rejects a foreign receiver" {
  let owner = row_owner(
    ",{\"from\":\"seed\",\"select\":[\"a\"],\"as\":\"selected\"}",
  )
  let upstream = evaluate_sequence_components(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["values_0", "select_1"],
    run_limits(),
    { remaining: 10000, max_frames: 100, },
  ).unwrap()
  let source = completed_output(upstream, Step(0)).unwrap()
  let terminal = completed_output(upstream, Step(1)).unwrap()
  let input = prepare_producer_read(
    owner,
    bind_completed_operation_input(owner, 1, 0, owner, source).unwrap(),
    100,
    100,
  ).unwrap()
  // Only a controlled whitebox vector sets this flag; the product bridge must
  // preserve it and cannot promote these bytes to pending task completion.
  let readmitted = {
    ..terminal,
    completion: { ..terminal.completion, readmitted: true, },
  }
  let retained = retain_completed_segment_input(readmitted, input).unwrap()
  assert_true(retained.completion.readmitted)
  assert_true(
    physical_equal(
      retained.completion.result_identity,
      readmitted.completion.result_identity,
    ),
  )
  assert_true(
    physical_equal(
      retained.completion.input_bindings,
      readmitted.completion.input_bindings,
    ),
  )
  assert_true(physical_equal(retained.table, readmitted.table))
  assert_true(completed_output_matches_segment_input(retained, input))
  let rebound = prepare_producer_read(
    owner,
    bind_completed_operation_input(owner, 1, 0, owner, source).unwrap(),
    100,
    100,
  ).unwrap()
  assert_false(completed_output_matches_segment_input(retained, rebound))
  let foreign = row_owner(
    ",{\"from\":\"seed\",\"select\":[\"a\"],\"as\":\"selected\"}",
  )
  assert_true(
    retain_completed_segment_input(
      {
        ..readmitted,
        completion: {
          ..readmitted.completion,
          sequence: prepared_sequence(foreign),
        },
      },
      input,
    )
    is None,
  )
}

///|
// Pure completion/input component: no Model service, captured DAG or ordinary
// caller is executed here. The new Host consumer uses this existing predicate.
test "Model suffix input binding keeps its original completion rather than descendant or equal rows" {
  let owner = row_owner(
    ",{\"from\":\"seed\",\"select\":[\"a\"],\"as\":\"selected\"}",
  )
  let evaluate = () => {
    evaluate_sequence_components(
      registered_relation_contracts(),
      prepared_sequence(owner),
      [],
      ["values_0", "select_1"],
      run_limits(),
      { remaining: 10000, max_frames: 100, },
    ).unwrap()
  }
  let executed = evaluate()
  let raw = completed_output(executed, Step(0)).unwrap()
  let live = Ref(true)
  let original = restrict_completed_output(raw, () => live.val)
  let descendant = completed_output(executed, Step(1)).unwrap()
  let input = prepare_producer_read(
    owner,
    bind_completed_operation_input(owner, 1, 0, owner, original).unwrap(),
    100,
    100,
  ).unwrap()
  assert_true(producer_read_matches_completed_output(input, original))
  assert_false(producer_read_matches_completed_output(input, descendant))
  let foreign = completed_output(evaluate(), Step(0)).unwrap()
  assert_false(producer_read_matches_completed_output(input, foreign))
  live.val = false
  assert_false(producer_read_matches_completed_output(input, original))
  assert_true(completed_output_available(raw))
}

///|
// Actual executed completion and anchored operation binding, independently of
// the scheduler's temporary input alias. No Model service or Native caller.
test "completed operation keeps original input provenance after temporary read retirement" {
  let owner = row_owner(
    ",{\"from\":\"seed\",\"select\":[\"a\"],\"as\":\"selected\"}",
  )
  let execute = () => {
    evaluate_sequence_components(
      registered_relation_contracts(),
      prepared_sequence(owner),
      [],
      ["values_0", "select_1"],
      run_limits(),
      { remaining: 10000, max_frames: 100, },
    ).unwrap()
  }
  let actual = execute()
  let source = completed_output(actual, Step(0)).unwrap()
  let terminal = completed_output(actual, Step(1)).unwrap()
  let input = prepare_producer_read(
    owner,
    bind_completed_operation_input(owner, 1, 0, owner, source).unwrap(),
    100,
    100,
  ).unwrap()
  let anchored = anchor_completed_output_operation_inputs(terminal, 1, [input]).unwrap()
  let managed_binding = ordinary_relation_input_binding(input)
  assert_true(
    managed_input_binding_has_original_completion(managed_binding, source),
  )
  assert_false(
    managed_input_binding_has_original_completion(managed_binding, terminal),
  )
  let temporary = [Some(input)]
  temporary[0] = None
  assert_true(temporary[0] is None)
  assert_true(
    completed_output_has_original_operation_input(anchored, source, 0),
  )
  assert_false(
    completed_output_has_original_operation_input(anchored, terminal, 0),
  )
  let foreign = completed_output(execute(), Step(0)).unwrap()
  assert_false(
    completed_output_has_original_operation_input(anchored, foreign, 0),
  )
  assert_false(
    completed_output_has_original_operation_input(anchored, source, 1),
  )
  assert_false(
    completed_output_has_original_operation_input(anchored, source, -1),
  )
  let callbacks = Ref(0)
  let expired = restrict_completed_output(source, () => {
    callbacks.val += 1
    false
  })
  // Immutable provenance does not become availability or call the Host.
  assert_true(
    completed_output_has_original_operation_input(anchored, expired, 0),
  )
  assert_true(
    managed_input_binding_has_original_completion(managed_binding, expired),
  )
  assert_eq(callbacks.val, 0)
  assert_false(completed_output_available(expired))
  assert_eq(callbacks.val, 1)
}
