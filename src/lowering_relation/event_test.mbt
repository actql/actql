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
test "event projection lowers back to a typed Relation occurrence" {
  let checked = @pipeline.check_carriers(
    cursor(
      "[{\"from\":\"rows\",\"to_events\":{\"id\":\"event_id\",\"time\":\"occurred_at\"}},{\"watermark_events\":{\"watermark_ms\":12.5,\"policy\":\"mark\"}},{\"events\":true}]",
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
  guard @lowering_relation.sequence_step(sequence, 2)
    is Some(@lowering_relation.CarrierProjectionStep(projection)) else {
    fail("expected event projection")
  }
  assert_eq(
    @lowering_relation.carrier_projection_operation(projection),
    @projection.Events,
  )
  assert_eq(
    @carrier.kind(
      @lowering_relation.carrier_projection_output_carrier(projection),
    ),
    @carrier.RelationKind,
  )
  let writer = @encode.writer(10000, 1000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  assert_eq(
    @encode.finish(writer),
    "[{\"id\":\"to_events_0\",\"in\":[\"input_0\"],\"op\":\"BRIDGE.rows.to_events\",\"params\":{\"id\":\"event_id\",\"time\":\"occurred_at\"}},{\"id\":\"watermark_events_1\",\"in\":[\"to_events_0\"],\"op\":\"TEA.watermark.label\",\"params\":{\"policy\":\"mark\",\"watermark_ms\":12.5}},{\"id\":\"events_2\",\"in\":[\"watermark_events_1\"],\"op\":\"BRIDGE.events.to_rows\",\"params\":{}}]",
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

///|
fn event_stateful_owner() -> @lowering_relation.BoundPrepared {
  let checked = @pipeline.check_carriers(
    cursor(
      "[{\"from\":\"rows\",\"to_events\":{\"id\":\"event_id\",\"time\":\"occurred_at\"}},{\"dedupe_events\":{\"by\":[\"event_id\",\"event_id\"],\"order_by\":[{\"field\":\"occurred_at\",\"dir\":\"desc\",\"nulls\":\"first\"}]}},{\"session\":{\"by\":[\"event_id\"],\"gap\":1000}}]",
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
test "event dedupe and session preserve typed parameters in canonical lowering" {
  let sequence = @lowering_relation.prepare_sequence(
    event_stateful_owner(),
    sequence_limits(),
  ).unwrap()
  guard @lowering_relation.sequence_step(sequence, 1)
    is Some(@lowering_relation.EventStep(dedupe)) &&
    @lowering_relation.sequence_step(sequence, 2)
    is Some(@lowering_relation.EventStep(session)) else {
    fail("expected event steps")
  }
  assert_eq(@lowering_relation.event_dedupe_key_count(dedupe), Some(2))
  assert_eq(
    @lowering_relation.event_dedupe_key_at(dedupe, 1),
    Some(@schema.Unqualified("event_id")),
  )
  assert_eq(@lowering_relation.event_dedupe_order_count(dedupe), Some(1))
  assert_eq(
    @lowering_relation.event_dedupe_order_at(dedupe, 0),
    Some((@schema.Unqualified("occurred_at"), true, true)),
  )
  assert_eq(
    @lowering_relation.event_session_keys(session),
    Some([@schema.Unqualified("event_id")]),
  )
  assert_eq(
    @lowering_relation.event_session_identity(session),
    Some(@schema.Unqualified("event_id")),
  )
  assert_eq(
    @lowering_relation.event_session_time(session),
    Some(@schema.Unqualified("occurred_at")),
  )
  assert_eq(
    @lowering_relation.event_session_uses_timestamp(session),
    Some(false),
  )
  assert_eq(@lowering_relation.event_session_gap(session), Some(1000L))
  assert_true(
    @carrier.kind(@lowering_relation.event_output_carrier(session)) ==
    @carrier.EventsKind,
  )
  let writer = @encode.writer(10000, 1000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  assert_eq(
    @encode.finish(writer),
    "[{\"id\":\"to_events_0\",\"in\":[\"input_0\"],\"op\":\"BRIDGE.rows.to_events\",\"params\":{\"id\":\"event_id\",\"time\":\"occurred_at\"}},{\"id\":\"dedupe_events_1\",\"in\":[\"to_events_0\"],\"op\":\"TEA.dedupe\",\"params\":{\"by\":[\"event_id\",\"event_id\"],\"on_tie\":\"fail\",\"order_by\":[{\"dir\":\"desc\",\"field\":\"occurred_at\",\"nulls\":\"first\"}]}},{\"id\":\"session_2\",\"in\":[\"dedupe_events_1\"],\"op\":\"TEA.window.session_assign\",\"params\":{\"by\":[\"event_id\"],\"gap_ms\":1000,\"id\":\"event_id\",\"time\":\"occurred_at\",\"time_encoding\":\"epoch_ms\"}}]",
  )
  let exact = { ..sequence_limits(), max_bindings: 8, max_name_bytes: 73, }
  assert_true(
    @lowering_relation.prepare_sequence(event_stateful_owner(), exact) is Ok(_),
  )
  assert_true(
    @lowering_relation.prepare_sequence(event_stateful_owner(), {
      ..exact,
      max_bindings: 7,
    })
    is Err(@lowering_relation.EventFailure(_, EventPreparationLimit)),
  )
  assert_true(
    @lowering_relation.prepare_sequence(event_stateful_owner(), {
      ..exact,
      max_name_bytes: 72,
    })
    is Err(@lowering_relation.EventFailure(_, EventPreparationLimit)),
  )
}

///|
test "event session resolves its exact bound gap before canonical emission" {
  let declarations = @parameter.read_declarations(
    Some(cursor("{\"gap\":{\"type\":\"number\",\"nullable\":false}}")),
    { max_parameters: 1, max_nodes: 10, max_depth: 10, max_text_bytes: 100, },
  ).unwrap()
  let checked = @pipeline.check_carriers(
    cursor(
      "[{\"from\":\"rows\",\"to_events\":{\"id\":\"event_id\",\"time\":\"occurred_at\"}},{\"session\":{\"by\":[],\"gap\":{\"$param\":\"gap\"}}}]",
    ),
    [("rows", event_relation())],
    Some(declarations),
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
  let bound = match
    @parameter.bind(declarations, Some(cursor("{\"gap\":250}")), {
      max_nodes: 10,
      max_depth: 10,
      max_text_bytes: 100,
    }).unwrap() {
    @parameter.Ready(value) => value
    @parameter.NeedsBindings(_) => fail("missing gap binding")
  }
  let owner = @lowering_relation.bind_parameters(
    @lowering_relation.prepare(checked, limits()).unwrap(),
    Some(bound),
    max_parameters=1,
    max_name_bytes=3,
  ).unwrap()
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  guard @lowering_relation.sequence_step(sequence, 1)
    is Some(@lowering_relation.EventStep(session)) else {
    fail("expected session")
  }
  assert_eq(@lowering_relation.event_session_gap(session), Some(250L))
}
