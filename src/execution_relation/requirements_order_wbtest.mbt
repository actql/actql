///|
test "review: requirement enumeration order must not reject the same occurrence set" {
  let sequence = prepared_sequence(
    row_owner(
      ",{\"derive\":{\"c\":\"a + 10\"}},{\"filter\":\"c > 10\"},{\"select\":[\"c\"]}",
    ),
  )
  let first = sequence_fragment_context(sequence, 1, 2L)
  let second = sequence_fragment_context(sequence, 2, 2L)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [first, second],
    ["select_3"],
    100000,
    10000,
  ).unwrap()
  let requirements = generated_sequence_requirements(generated, 10).unwrap()
  let reversed = @lower.prepare_sequence_requirements(
    sequence,
    [
      @lower.sequence_requirements_fragment_at(requirements, 1).unwrap(),
      @lower.sequence_requirements_fragment_at(requirements, 0).unwrap(),
    ],
    [],
    10,
  ).unwrap()
  let reversed_execution = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [second, first],
    ["select_3"],
    100000,
    10000,
  ).unwrap()
  let limits : SequenceExecutionLimits = {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }
  let a = execute_generated_sequence(generated, [], limits).unwrap()
  let b = execute_generated_sequence(reversed_execution, [], limits).unwrap()
  assert_eq(completed_row_count(completed_output(a, Step(3)).unwrap()), 1)
  assert_eq(completed_row_count(completed_output(b, Step(3)).unwrap()), 1)
  assert_true(generated_satisfies_requirements(generated, requirements))
  assert_true(generated_satisfies_requirements(generated, reversed))
  assert_true(
    generated_satisfies_requirements(reversed_execution, requirements),
  )
  assert_true(generated_satisfies_requirements(reversed_execution, reversed))
  let one = @lower.sequence_requirements_fragment_at(requirements, 0).unwrap()
  let two = @lower.sequence_requirements_fragment_at(requirements, 1).unwrap()
  let make = fn(items) {
    @lower.prepare_sequence_requirements(sequence, items, [], 10).unwrap()
  }
  assert_false(generated_satisfies_requirements(generated, make([one])))
  assert_true(
    @lower.prepare_sequence_requirements(sequence, [one, one], [], 10)
    is Err(DuplicateOccurrence),
  )
  assert_true(
    @lower.prepare_sequence_requirements(sequence, [one, two], [], 1)
    is Err(InvalidLimits),
  )
  let changed = @lower.prepare_fragment_enforcement(
    one.request,
    { ..one.logical, max_work: one.logical.max_work - 1L, },
    one.measure_bytes,
    one.measure_nodes,
    one.measure_depth,
    one.root_result_bytes,
    one.all_expression_roots,
  ).unwrap()
  assert_false(
    generated_satisfies_requirements(generated, make([two, changed])),
  )
  let replacement = sequence_fragment_context(sequence, 1, 2L)
  let replaced = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [replacement, second],
    ["select_3"],
    100000,
    10000,
  ).unwrap()
  assert_false(generated_satisfies_requirements(replaced, reversed))
  let foreign = prepared_sequence(
    row_owner(
      ",{\"derive\":{\"c\":\"a + 10\"}},{\"filter\":\"c > 10\"},{\"select\":[\"c\"]}",
    ),
  )
  assert_true(
    @lower.prepare_sequence_requirements(foreign, [one, two], [], 10)
    is Err(ForeignOccurrence),
  )
}
