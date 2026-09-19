///|
fn event_relation() -> @carrier.Carrier {
  @carrier.relation(
    @carrier.rows(
      [
        (
          @schema.Unqualified("event_id"),
          Some(@contract.primitive(@contract.NumberType, nullable=false)),
        ),
        (
          @schema.Unqualified("occurred_at"),
          Some(@contract.primitive(@contract.NumberType, nullable=false)),
        ),
        (
          @schema.Unqualified("payload"),
          Some(@contract.primitive(@contract.StringType, nullable=true)),
        ),
      ],
      field_set=@carrier.Closed,
      max_fields=3,
      max_name_bytes=26,
    ).unwrap(),
  )
}

///|
fn event_owner() -> @lowering_relation.BoundPrepared {
  let checked = @pipeline.check_carriers(
    cursor(
      "[{\"from\":\"rows\",\"to_events\":{\"id\":\"event_id\",\"time\":\"occurred_at\"}},{\"watermark_events\":{\"watermark_ms\":12.5,\"policy\":\"mark\"}}]",
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
  @lowering_relation.bind_parameters(
    @lowering_relation.prepare(checked, limits()).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
test "checked event bridge and watermark lower without source rediscovery" {
  let sequence = @lowering_relation.prepare_sequence(
    event_owner(),
    sequence_limits(),
  ).unwrap()
  let writer = @encode.writer(10000, 1000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  assert_eq(
    @encode.finish(writer),
    "[{\"id\":\"to_events_0\",\"in\":[\"input_0\"],\"op\":\"BRIDGE.rows.to_events\",\"params\":{\"id\":\"event_id\",\"time\":\"occurred_at\"}},{\"id\":\"watermark_events_1\",\"in\":[\"to_events_0\"],\"op\":\"TEA.watermark.label\",\"params\":{\"policy\":\"mark\",\"watermark_ms\":12.5}}]",
  )
}

///|
test "event lowering admits role metadata before emission" {
  let exact = { ..sequence_limits(), max_bindings: 2, max_name_bytes: 19, }
  assert_true(
    @lowering_relation.prepare_sequence(event_owner(), exact) is Ok(_),
  )
  assert_true(
    @lowering_relation.prepare_sequence(event_owner(), {
      ..exact,
      max_name_bytes: 18,
    })
    is Err(
      @lowering_relation.EventFailure(
        0,
        @lowering_relation.EventPreparationLimit
      )
    ),
  )
}
