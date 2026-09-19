///|
fn cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(
      text,
      { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      source_path="local-tea-watermark.aql",
    ).unwrap(),
    {
      max_nodes: 1000,
      max_depth: 100,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
  ).unwrap()
}

///|
fn event_relation(timestamp : Bool) -> @carrier.Carrier {
  @carrier.relation(
    @carrier.rows(
      [
        (
          @schema.Unqualified("event_id"),
          Some(@contract.primitive(@contract.NumberType, nullable=false)),
        ),
        (
          @schema.Unqualified("occurred_at"),
          Some(
            @contract.primitive(
              if timestamp {
                @contract.TimestampType
              } else {
                @contract.NumberType
              },
              nullable=false,
            ),
          ),
        ),
        (
          @schema.Unqualified("payload"),
          Some(@contract.primitive(@contract.StringType, nullable=false)),
        ),
      ],
      field_set=@carrier.Closed,
      max_fields=3,
      max_name_bytes=26,
    ).unwrap(),
  )
}

///|
fn bind(checked : @pipeline.CheckedPipeline) -> @lower.BoundPrepared {
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
fn producer_owner(timestamp : Bool) -> @lower.BoundPrepared {
  bind(
    @pipeline.check_carriers(
      cursor(
        "[{\"from\":\"rows\",\"to_events\":{\"id\":\"event_id\",\"time\":\"occurred_at\"}}]",
      ),
      [("rows", event_relation(timestamp))],
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
    ).unwrap(),
  )
}

///|
fn watermark_owner(
  producer : @lower.BoundPrepared,
  policy : String,
) -> @lower.BoundPrepared {
  bind(
    @pipeline.check_with_evidence(
      cursor(
        "[{\"watermark_events\":{\"watermark_ms\":10,\"policy\":\"" +
        policy +
        "\"}}]",
      ),
      [
        (
          "prior",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(producer)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
      ],
      None,
      Some(cursor("\"prior\"")),
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
fn event_consumer_owner(
  producer : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  bind(
    @pipeline.check_with_evidence(
      cursor(
        "[{\"dedupe_events\":{\"by\":[\"event_id\"],\"order_by\":[{\"field\":\"occurred_at\",\"dir\":\"asc\",\"nulls\":\"last\"}]}}]",
      ),
      [
        (
          "prior",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(producer)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
      ],
      None,
      Some(cursor("\"prior\"")),
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
fn sequence(owner : @lower.BoundPrepared) -> @lower.PreparedSequence {
  @lower.prepare_sequence(owner, {
    max_steps: 10,
    max_rows: 100,
    max_cells: 1000,
    max_bindings: 100,
    max_name_bytes: 1000,
    expressions: {
      max_nodes: 100,
      max_work: 1000,
      max_depth: 100,
      max_literal_nodes: 100,
      max_literal_text_bytes: 1000,
    },
  }).unwrap()
}

///|
fn limits(workspace? : Int = 1000) -> @storage.Limits {
  {
    max_input_records: 10,
    max_records: 10,
    max_fields_per_record: 10,
    max_value_bytes: 1000,
    max_total_value_bytes: 10000,
    max_retained_value_bytes: 10000,
    max_value_nodes: 100,
    max_value_depth: 10,
    max_contract_work: 1000,
    max_work: 1000,
    max_workspace_slots: workspace,
  }
}

///|
fn number(value : Double) -> @value.CheckedValue {
  @value.admit(
    @contract.primitive(@contract.NumberType, nullable=false),
    cursor(value.to_string()),
    { max_nodes: 1, max_depth: 1, max_text_bytes: 0, },
  ).unwrap()
}

///|
fn text(value : String) -> @value.CheckedValue {
  @value.admit(
    @contract.primitive(@contract.StringType, nullable=false),
    cursor("\"" + value + "\""),
    { max_nodes: 1, max_depth: 1, max_text_bytes: 100, },
  ).unwrap()
}

///|
fn timestamp(value : String) -> @value.CheckedValue {
  @value.admit(
    @contract.primitive(@contract.TimestampType, nullable=false),
    cursor("\"" + value + "\""),
    { max_nodes: 1, max_depth: 1, max_text_bytes: 100, },
  ).unwrap()
}

///|
fn source_events(
  owner : @lower.BoundPrepared,
  live : Ref[Bool],
  timestamp_clock : Bool,
) -> @records.Completed {
  let output = @records.prepare_output(
    owner,
    @pipeline.Step(0),
    limits(),
    4096L,
    fn() { live.val },
  ).unwrap()
  let times = if timestamp_clock {
    [
      timestamp("1970-01-01T00:00:00.009Z"),
      timestamp("1970-01-01T00:00:00.010Z"),
      timestamp("1970-01-01T00:00:00.011Z"),
    ]
  } else {
    [number(9.0), number(10.0), number(11.0)]
  }
  for index in 0..<3 {
    @records.append_record(output, [
      (@schema.Unqualified("event_id"), number(index.to_double() + 1.0)),
      (@schema.Unqualified("occurred_at"), times[index]),
      (@schema.Unqualified("payload"), text("p" + index.to_string())),
    ]).unwrap()
  }
  @records.finish_output(output).unwrap()
}

///|
fn finish(execution : WatermarkExecution) -> @records.Completed {
  while true {
    match advance_watermark(execution, 1).unwrap() {
      Continue(..) => ()
      Complete(output, ..) => return output
      Failed(_, ..) => abort("watermark failed")
      Stopped(_, ..) => abort("watermark stopped")
    }
  }
  abort("unreachable")
}

///|
fn field(
  storage : @storage.Storage,
  record : Int,
  expected : String,
) -> @value.CheckedValue {
  let count = @storage.record_field_count(storage, record).unwrap()
  for index in 0..<count {
    guard @storage.record_field_at(storage, record, index)
      is Some((name, value)) else {
      abort("watermark field")
    }
    if @schema.reference_name(name) == expected {
      return value
    }
  }
  abort("missing watermark field")
}

///|
test "watermark mark preserves order and feeds two exact consumers" {
  let producer = producer_owner(false)
  let source_live = Ref(true)
  let source = source_events(producer, source_live, false)
  let owner = watermark_owner(producer, "mark")
  let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  let execution = start_watermark(
    @bounded.control(),
    sequence(owner),
    0,
    input,
    limits(),
    4096L,
    fn() { true },
  ).unwrap()
  assert_eq(watermark_max_noninterruptible_value_nodes(execution), 3)
  let completed = finish(execution)
  assert_true(watermark_stopped(execution))
  assert_true(watermark_cleanup_pending(execution))
  assert_eq(cleanup_watermark(execution), Ok(true))
  source_live.val = false
  let material = @records.completed_storage(completed).unwrap()
  assert_eq(@storage.record_count(material), 3)
  for (record, expected) in [(0, true), (1, false), (2, false)] {
    guard field(material, record, "late").value is @value.Boolean(late) &&
      field(material, record, "watermark_decision").value
      is @value.Text(decision) else {
      fail("watermark labels")
    }
    assert_eq(late, expected)
    assert_eq(decision, if expected { "mark" } else { "keep" })
  }
  let consumer = event_consumer_owner(owner)
  let first = @records.prepare_producer_read(consumer, 0, owner, completed).unwrap()
  let second = @records.prepare_producer_read(consumer, 0, owner, completed).unwrap()
  assert_false(@records.producer_read_same(first, second))
  assert_eq(
    @storage.record_count(@records.producer_read_storage(first).unwrap()),
    3,
  )
  assert_eq(
    @storage.record_count(@records.producer_read_storage(second).unwrap()),
    3,
  )
}

///|
test "watermark drop handles equality and canonical UTC clocks" {
  for timestamp_clock in [false, true] {
    let producer = producer_owner(timestamp_clock)
    let source = source_events(producer, Ref(true), timestamp_clock)
    let owner = watermark_owner(producer, "drop")
    let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
    let completed = finish(
      start_watermark(
        @bounded.control(),
        sequence(owner),
        0,
        input,
        limits(),
        4096L,
        fn() { true },
      ).unwrap(),
    )
    let material = @records.completed_storage(completed).unwrap()
    assert_eq(@storage.record_count(material), 2)
    guard field(material, 0, "event_id").value is @value.Number(first) &&
      field(material, 1, "event_id").value is @value.Number(second) else {
      fail("watermark identity")
    }
    assert_eq(first, 2.0)
    assert_eq(second, 3.0)
  }
}

///|
test "watermark admits workspace before records and observes cancellation" {
  let producer = producer_owner(false)
  let source = source_events(producer, Ref(true), false)
  let owner = watermark_owner(producer, "mark")
  let constrained = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  let too_small = start_watermark(
    @bounded.control(),
    sequence(owner),
    0,
    constrained,
    limits(workspace=5),
    4096L,
    fn() { true },
  ).unwrap()
  assert_true(
    advance_watermark(too_small, 1).unwrap()
    is Failed(WorkspaceLimit, progress=0L, work=0L),
  )
  assert_eq(cleanup_watermark(too_small), Ok(true))

  let control = @bounded.control()
  let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  let execution = start_watermark(
    control,
    sequence(owner),
    0,
    input,
    limits(),
    4096L,
    fn() { true },
  ).unwrap()
  assert_true(advance_watermark(execution, 1).unwrap() is Continue(_))
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_watermark(execution, 1).unwrap()
    is Stopped(@bounded.Cancelled, progress=0L, work=1L),
  )
  assert_eq(cleanup_watermark(execution), Ok(true))
}

///|
test "watermark retains completed output custody until stop cleanup" {
  let producer = producer_owner(false)
  let source = source_events(producer, Ref(true), false)
  let owner = watermark_owner(producer, "mark")
  let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  let control = @bounded.control()
  let availability_checks = Ref(0)
  let execution = start_watermark(
    control,
    sequence(owner),
    0,
    input,
    limits(),
    4096L,
    fn() {
      availability_checks.val += 1
      if availability_checks.val == 2 {
        @bounded.request_cancel(control) |> ignore
      }
      true
    },
  ).unwrap()
  while true {
    match advance_watermark(execution, 1).unwrap() {
      Continue(..) => continue
      Stopped(@bounded.Cancelled, ..) => break
      Complete(_, ..) => fail("cancelled output escaped")
      Failed(_, ..) => fail("watermark failed")
      Stopped(_, ..) => fail("wrong stop reason")
    }
  }
  assert_true(availability_checks.val >= 2)
  assert_true(watermark_cleanup_pending(execution))
  assert_eq(cleanup_watermark(execution), Ok(true))
  assert_false(watermark_cleanup_pending(execution))
}
