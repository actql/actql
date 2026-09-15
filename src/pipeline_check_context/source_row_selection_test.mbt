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
    )
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
test "automatic keyed source selection does not substitute a Host ceiling for a producer proof" {
  let selected = prepared_keyed_source_context(omit_proof=true)
  assert_true(
    prepare_program_source_acquisitions_auto(
      selected,
      {
        max_work: 10000000,
        max_pairs: 1000,
        values: { max_nodes: 10000, max_depth: 100, max_text_bytes: 100000, },
      },
      max_bindings=100,
      max_slots=1000,
    )
    is Err(Rows(MissingPositiveBound(0, 0, _))),
  )
}
