///|
test "Carrier handoff inventory preserves exact typed edge occurrences" {
  let checked = @pipeline.check_carriers(
    cursor(
      "[{\"from\":\"rows\",\"to_events\":{" +
      "\"id\":\"event_id\",\"time\":\"occurred_at\"}}," +
      "{\"watermark_events\":{\"watermark_ms\":12.5," +
      "\"policy\":\"mark\"}},{\"events\":true}]",
    ),
    [("rows", event_relation())],
    None,
    None,
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  let owner = @lowering_relation.bind_parameters(
    @lowering_relation.prepare(checked, limits()).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  let index = @lowering_relation.prepare_carrier_handoffs(sequence, 2, 6).unwrap()
  assert_true(
    physical_equal(@lowering_relation.carrier_handoff_sequence(index), sequence),
  )
  assert_eq(@lowering_relation.carrier_handoff_count(index), 2)
  for position in 0..<2 {
    let expected = if position == 0 { (0, 1) } else { (1, 2) }
    let edge = @lowering_relation.carrier_handoff_at(index, position).unwrap()
    assert_eq(
      (
        @lowering_relation.carrier_handoff_producer(edge),
        @lowering_relation.carrier_handoff_consumer(edge),
      ),
      expected,
    )
    assert_eq(@lowering_relation.carrier_handoff_input(edge), 0)
    assert_eq(
      @carrier.kind(@lowering_relation.carrier_handoff_carrier(edge)),
      @carrier.EventsKind,
    )
  }
  assert_true(@lowering_relation.carrier_handoff_at(index, -1) is None)
  assert_true(@lowering_relation.carrier_handoff_at(index, 2) is None)
}

///|
test "Carrier handoff inventory is bounded before every retained edge" {
  let sequence = @lowering_relation.prepare_sequence(
    event_owner(),
    sequence_limits(),
  ).unwrap()
  assert_true(
    @lowering_relation.prepare_carrier_handoffs(sequence, 0, 4)
    is Err(@lowering_relation.CarrierHandoffEdgeLimit),
  )
  assert_true(
    @lowering_relation.prepare_carrier_handoffs(sequence, 2, 3)
    is Err(@lowering_relation.CarrierHandoffWorkLimit),
  )
  assert_true(
    @lowering_relation.prepare_carrier_handoffs(sequence, -1, 5)
    is Err(@lowering_relation.InvalidCarrierHandoffLimits),
  )
}
