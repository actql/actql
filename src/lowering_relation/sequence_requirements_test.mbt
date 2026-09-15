///|
test "neutral requirements bind exact fragment without a Local preparation" {
  let owner = expression_pipeline(
    ",{\"filter\":\"id > 0\"},{\"select\":[\"id\"]}",
  )
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  let fragment = @lowering_relation.prepare_fragment_pipeline(
    sequence,
    1,
    root_limits(),
  ).unwrap()
  let request = @lowering_relation.prepare_fragment_request(fragment, 10L, 100L).unwrap()
  let logical : @lowering_relation.FragmentRowLimits = {
    max_input_rows: 10L,
    max_value_bytes: 100L,
    max_live_value_bytes: 200L,
    max_work: 300L,
  }
  let enforcement = @lowering_relation.prepare_fragment_enforcement(
    request,
    logical,
    1000,
    100,
    10,
    None,
    false,
  ).unwrap()
  let entries = [enforcement]
  let requirements = @lowering_relation.prepare_sequence_requirements(
    sequence,
    entries,
    [],
    1,
  ).unwrap()
  entries.clear()
  assert_eq(
    @lowering_relation.sequence_requirements_fragment_count(requirements),
    1,
  )
  assert_true(
    physical_equal(
      @lowering_relation.sequence_requirements_owner(requirements),
      owner,
    ),
  )
  assert_true(
    physical_equal(
      @lowering_relation.sequence_requirements_fragment_at(requirements, 0).unwrap().request,
      request,
    ),
  )
  assert_true(
    @lowering_relation.sequence_requirements_fragment_at(requirements, 1)
    is None,
  )
  assert_true(
    @lowering_relation.prepare_sequence_requirements(
      sequence,
      [enforcement, enforcement],
      [],
      2,
    )
    is Err(DuplicateOccurrence),
  )
  let equal_sequence = @lowering_relation.prepare_sequence(
    owner,
    sequence_limits(),
  ).unwrap()
  assert_true(
    @lowering_relation.prepare_sequence_requirements(
      equal_sequence,
      [enforcement],
      [],
      1,
    )
    is Err(ForeignOccurrence),
  )
  assert_true(
    @lowering_relation.prepare_fragment_enforcement(
      request,
      { ..logical, max_input_rows: 11L, },
      1000,
      100,
      10,
      None,
      false,
    )
    is Err(ExceedsRequest),
  )
  assert_true(
    @lowering_relation.prepare_sequence_requirements(
      sequence,
      [enforcement],
      [],
      0,
    )
    is Err(InvalidLimits),
  )
  assert_true(
    @lowering_relation.prepare_sequence_requirements(sequence, [], [(1, 1L)], 1)
    is Err(ForeignOccurrence),
  )
}
