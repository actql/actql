///|
test "automatic keyed source selection preserves sparse claim coordinates" {
  for host_first in [false, true] {
    let selected = prepared_keyed_source_context(host_first~)
    let caps : @sourceviews.RequestLimits = {
      max_work: 10000000,
      max_pairs: 1000,
      values: { max_nodes: 10000, max_depth: 100, max_text_bytes: 100000, },
    }
    let value = prepare_program_source_acquisitions_auto(
      selected,
      caps,
      max_bindings=100,
      max_slots=1000,
    ).unwrap()
    let membership = source_producer_at(value, 0, 0).unwrap()
    let (visit, claim, producer) = @capacity.target_membership_coordinates(
      membership,
    ).unwrap()
    assert_eq(visit, 0)
    assert_eq(claim, if host_first { 1 } else { 0 })
    assert_eq(producer, 0)
    let bounds = @capacity.target_membership_rows(membership)
    assert_eq(@program.target_rows_target(bounds), @pipeline.Step(0))
    assert_eq(@program.target_rows_value(bounds), 1L)
    let used = source_producer_work(value)
    let exact = prepare_program_source_acquisitions_auto(
      selected,
      { ..caps, max_work: used, },
      max_bindings=100,
      max_slots=1000,
    ).unwrap()
    assert_eq(source_producer_work(exact), used)
    assert_true(
      prepare_program_source_acquisitions_auto(
        selected,
        { ..caps, max_work: used - 1, },
        max_bindings=100,
        max_slots=1000,
      )
      is Err(_),
    )
  }
}

///|
test "automatic keyed source selection retains runtime admission without inventing a producer proof" {
  let selected = prepared_keyed_source_context(omit_proof=true)
  let prepared = prepare_program_source_acquisitions_auto(
      selected,
      {
        max_work: 10000000,
        max_pairs: 1000,
        values: { max_nodes: 10000, max_depth: 100, max_text_bytes: 100000, },
      },
      max_bindings=100,
      max_slots=1000,
    ).unwrap()
  assert_true(source_producer_at(prepared, 0, 0) is None)
  assert_true(bind_source_producers(
    source_producer_capacity(prepared), [[(0, 0)]], 10000000,
  ) is Err(MissingEstimate(0, 0)))
  let bounds = source_capacity_stage(source_producer_capacity(prepared), 0).unwrap()
  let requirement = @sourceviews.lookup_requirement_at(bounds, 0).unwrap()
  assert_true(@sourceviews.lookup_bounds_at(bounds, 0) is None)
  assert_true(@sourceviews.lookup_requirement_admission(requirement) is @sourceviews.RuntimeAdmission)
  guard @sourceviews.keyed_rows_requirement_at(@sourceviews.lookup_bounds_rows(bounds), 0)
    is Some(@sourceviews.RuntimeAdmission(join)) else {
    fail("missing exact runtime row requirement")
  }
  assert_true(physical_equal(join, @sourceviews.lookup_requirement_join(requirement)))
}
