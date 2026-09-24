///|
fn event_window_cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(
      text,
      { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      source_path="local-tea-window.aql",
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
fn event_window_relation(
  timestamp? : Bool = false,
  wide? : Bool = false,
) -> @carrier.Carrier {
  let fields = [
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
  ]
  if wide {
    fields.push(
      (
        @schema.Unqualified("payload_extra"),
        Some(@contract.primitive(@contract.StringType, nullable=false)),
      ),
    )
  }
  @carrier.relation(
    @carrier.rows(
      fields,
      field_set=@carrier.Closed,
      max_fields=if wide { 4 } else { 3 },
      max_name_bytes=if wide { 39 } else { 26 },
    ).unwrap(),
  )
}

///|
fn event_window_bind(
  checked : @pipeline.CheckedPipeline,
) -> @lower.BoundPrepared {
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
fn event_window_producer(
  timestamp? : Bool = false,
  wide? : Bool = false,
) -> @lower.BoundPrepared {
  event_window_bind(
    @pipeline.check_carriers(
      event_window_cursor(
        "[{\"from\":\"rows\",\"to_events\":{\"id\":\"event_id\",\"time\":\"occurred_at\"}}]",
      ),
      [("rows", event_window_relation(timestamp~, wide~))],
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
fn event_window_owner(
  producer : @lower.BoundPrepared,
  body : String,
) -> @lower.BoundPrepared {
  event_window_bind(
    @pipeline.check_with_evidence(
      event_window_cursor("[{\"window_events\":" + body + "}]"),
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
      Some(event_window_cursor("\"prior\"")),
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
fn event_window_sequence(
  owner : @lower.BoundPrepared,
) -> @lower.PreparedSequence {
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
fn event_window_limits(
  max_records? : Int = 20,
  workspace? : Int = 100,
  fields? : Int = 5,
) -> @storage.Limits {
  {
    max_input_records: 10,
    max_records,
    max_fields_per_record: fields,
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
fn event_window_number(value : Double) -> @value.CheckedValue {
  @value.admit(
    @contract.primitive(@contract.NumberType, nullable=false),
    event_window_cursor(value.to_string()),
    { max_nodes: 1, max_depth: 1, max_text_bytes: 0, },
  ).unwrap()
}

///|
fn event_window_text(value : String) -> @value.CheckedValue {
  @value.admit(
    @contract.primitive(@contract.StringType, nullable=false),
    event_window_cursor("\"" + value + "\""),
    { max_nodes: 1, max_depth: 1, max_text_bytes: 100, },
  ).unwrap()
}

///|
fn event_window_source(
  owner : @lower.BoundPrepared,
  times : Array[Double],
  live : Ref[Bool],
  wide? : Bool = false,
) -> @records.Completed {
  let output = @records.prepare_output(
    owner,
    @pipeline.Step(0),
    event_window_limits(),
    4096L,
    fn() { live.val },
  ).unwrap()
  for index, time in times {
    let fields = [
      (
        @schema.Unqualified("event_id"),
        event_window_number(index.to_double() + 1.0),
      ),
      (@schema.Unqualified("occurred_at"), event_window_number(time)),
      (
        @schema.Unqualified("payload"),
        event_window_text("p" + index.to_string()),
      ),
    ]
    if wide {
      fields.push(
        (@schema.Unqualified("payload_extra"), event_window_text("q")),
      )
    }
    @records.append_record(output, fields).unwrap()
  }
  @records.finish_output(output).unwrap()
}

///|
fn event_window_timestamp_source(
  owner : @lower.BoundPrepared,
  live : Ref[Bool],
  wide? : Bool = false,
) -> @records.Completed {
  let output = @records.prepare_output(
    owner,
    @pipeline.Step(0),
    event_window_limits(),
    4096L,
    fn() { live.val },
  ).unwrap()
  let time = @value.admit(
    @contract.primitive(@contract.TimestampType, nullable=false),
    event_window_cursor("\"1970-01-01T00:00:00.009Z\""),
    { max_nodes: 1, max_depth: 1, max_text_bytes: 100, },
  ).unwrap()
  let fields = [
    (@schema.Unqualified("event_id"), event_window_number(1.0)),
    (@schema.Unqualified("occurred_at"), time),
    (@schema.Unqualified("payload"), event_window_text("p0")),
  ]
  if wide {
    fields.push((@schema.Unqualified("payload_extra"), event_window_text("q")))
  }
  @records.append_record(output, fields).unwrap()
  @records.finish_output(output).unwrap()
}

///|
fn event_window_finish(
  execution : EventWindowExecution,
) -> (@records.Completed, Int64) {
  let mut work = 0L
  while true {
    match advance_event_window(execution, 1).unwrap() {
      EventWindowContinue(work=used, ..) => work = used
      EventWindowComplete(output, work=used, ..) => {
        work = used
        return (output, work)
      }
      EventWindowFailed(_, ..) => abort("window failed")
      EventWindowStopped(_, ..) => abort("unexpected stop")
    }
  } nobreak {
    abort("unreachable")
  }
}

///|
fn event_window_field(
  storage : @storage.Storage,
  record : Int,
  name : String,
) -> Double {
  let width = @storage.record_field_count(storage, record).unwrap()
  for field in 0..<width {
    let (field_name, value) = @storage.record_field_at(storage, record, field).unwrap()
    if @schema.reference_name(field_name) == name {
      guard value.value is @value.Number(number) else { abort("number field") }
      return number
    }
  }
  abort("missing field " + name)
}

///|
test "fixed and sliding event windows preserve order with bounded steps" {
  let producer = event_window_producer()
  let live = Ref(true)
  for
    (body, times, expected_starts) in [
      ("{\"kind\":\"fixed\",\"size\":10}", [9.0, 10.0], [0.0, 10.0]),
      (
        "{\"kind\":\"sliding\",\"size\":10,\"step\":5}",
        [9.0, 10.0],
        [0.0, 5.0, 5.0, 10.0],
      ),
      ("{\"kind\":\"sliding\",\"size\":5,\"step\":10}", [6.0], []),
      (
        "{\"kind\":\"sliding\",\"size\":10,\"step\":5,\"offset\":-2}",
        [9.0],
        [3.0, 8.0],
      ),
    ] {
    let owner = event_window_owner(producer, body)
    let source = event_window_source(producer, times, live)
    let read = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
    let (output, work) = event_window_finish(
      start_event_window(
        @bounded.control(),
        event_window_sequence(owner),
        0,
        read,
        event_window_limits(),
        4096L,
        fn() { true },
      ).unwrap(),
    )
    let storage = @records.completed_storage(output).unwrap()
    assert_eq(@storage.record_count(storage), expected_starts.length())
    for index, expected in expected_starts {
      assert_eq(event_window_field(storage, index, "window_start_ms"), expected)
      assert_eq(
        event_window_field(storage, index, "window_end_ms"),
        expected + 10.0,
      )
    }
    assert_true(work > 0L)
    assert_true(@records.discard_completed(output))
    assert_true(@records.discard_completed(source))
  }
}

///|
// Expectations are transcribed from the separately authored
// portability/corpus/event-window-boundaries.json.
test "event windows use exact grids and reject unrepresentable boundaries" {
  let producer = event_window_producer()
  let live = Ref(true)
  for
    (time, step, arithmetic) in [
      (9007199254740992.0, 1, true),
      (9007199254740992.0, 2, false),
      (18014398509481984.0, 1, true),
      (18014398509481984.0, 2, true),
      (18014398509481984.0, 4, false),
      (-9007199254740992.0, 1, true),
      (-9007199254740992.0, 2, false),
      (-18014398509481984.0, 1, true),
      (-18014398509481984.0, 2, true),
      (-18014398509481984.0, 4, false),
    ] {
    let body = "{\"kind\":\"sliding\",\"size\":8,\"step\":" +
      step.to_string() +
      "}"
    let owner = event_window_owner(producer, body)
    let source = event_window_source(producer, [time], live)
    let read = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
    let execution = start_event_window(
      @bounded.control(),
      event_window_sequence(owner),
      0,
      read,
      event_window_limits(),
      4096L,
      fn() { true },
    ).unwrap()
    let mut polls = 0
    let mut terminal = false
    while !terminal && polls < 64 {
      polls += 1
      match advance_event_window(execution, 1).unwrap() {
        EventWindowContinue(..) => ()
        EventWindowComplete(output, ..) => {
          assert_false(arithmetic)
          assert_true(@records.discard_completed(output))
          terminal = true
        }
        EventWindowFailed(EventWindowArithmetic(0), ..) => {
          assert_true(arithmetic)
          terminal = true
        }
        EventWindowFailed(_, ..) => fail("unexpected window failure")
        EventWindowStopped(_, ..) => fail("unexpected window stop")
      }
    }
    assert_true(terminal)
    assert_true(polls < 64)
    assert_true(cleanup_event_window(execution).unwrap())
    assert_true(@records.discard_completed(source))
  }
  for
    time in [
      9007199254740992.0, 18014398509481984.0, -9007199254740992.0, -18014398509481984.0,
    ] {
    let owner = event_window_owner(producer, "{\"kind\":\"fixed\",\"size\":8}")
    let source = event_window_source(producer, [time], live)
    let read = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
    let (output, _) = event_window_finish(
      start_event_window(
        @bounded.control(),
        event_window_sequence(owner),
        0,
        read,
        event_window_limits(),
        4096L,
        fn() { true },
      ).unwrap(),
    )
    assert_true(@records.discard_completed(output))
    assert_true(@records.discard_completed(source))
  }
}

///|
test "event windows distinguish exact membership from boundary encoding" {
  let producer = event_window_producer()
  let live = Ref(true)
  for
    (time, body, expected_start, expected_end) in [
      (-0.5, "{\"kind\":\"fixed\",\"size\":10}", -10.0, 0.0),
      (0.5, "{\"kind\":\"fixed\",\"size\":10}", 0.0, 10.0),
      (
        9007199254740992.0, "{\"kind\":\"fixed\",\"size\":8}", 9007199254740992.0,
        9007199254741000.0,
      ),
      (
        18014398509481984.0, "{\"kind\":\"fixed\",\"size\":4}", 18014398509481984.0,
        18014398509481988.0,
      ),
      (
        9223372036854775808.0, "{\"kind\":\"fixed\",\"size\":2048}", 9223372036854775808.0,
        9223372036854777856.0,
      ),
      (
        -9223372036854775808.0, "{\"kind\":\"fixed\",\"size\":2048}", -9223372036854775808.0,
        -9223372036854773760.0,
      ),
    ] {
    let owner = event_window_owner(producer, body)
    let source = event_window_source(producer, [time], live)
    let read = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
    let (output, _) = event_window_finish(
      start_event_window(
        @bounded.control(),
        event_window_sequence(owner),
        0,
        read,
        event_window_limits(),
        4096L,
        fn() { true },
      ).unwrap(),
    )
    let storage = @records.completed_storage(output).unwrap()
    assert_eq(@storage.record_count(storage), 1)
    assert_eq(event_window_field(storage, 0, "window_start_ms"), expected_start)
    assert_eq(event_window_field(storage, 0, "window_end_ms"), expected_end)
    assert_true(@records.discard_completed(output))
    assert_true(@records.discard_completed(source))
  }
  let owner = event_window_owner(
    producer, "{\"kind\":\"sliding\",\"size\":1,\"step\":3,\"offset\":1}",
  )
  let source = event_window_source(producer, [9007199254740992.0], live)
  let read = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  let (output, _) = event_window_finish(
    start_event_window(
      @bounded.control(),
      event_window_sequence(owner),
      0,
      read,
      event_window_limits(),
      4096L,
      fn() { true },
    ).unwrap(),
  )
  let storage = @records.completed_storage(output).unwrap()
  assert_eq(@storage.record_count(storage), 0)
  assert_true(@records.discard_completed(output))
  assert_true(@records.discard_completed(source))
}

///|
test "event windows admit capacity before allocation and clean cancellation" {
  let producer = event_window_producer()
  let owner = event_window_owner(
    producer, "{\"kind\":\"sliding\",\"size\":10,\"step\":5}",
  )
  let live = Ref(true)
  let source = event_window_source(producer, [9.0, 10.0], live)
  let sequence = event_window_sequence(owner)
  let short_read = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  assert_true(
    start_event_window(
      @bounded.control(),
      sequence,
      0,
      short_read,
      event_window_limits(max_records=3),
      4096L,
      fn() { true },
    )
    is Err(InvalidEventWindowLimits),
  )
  let workspace_read = @records.prepare_producer_read(
    owner, 0, producer, source,
  ).unwrap()
  assert_true(
    start_event_window(
      @bounded.control(),
      sequence,
      0,
      workspace_read,
      event_window_limits(max_records=4, workspace=27),
      4096L,
      fn() { true },
    )
    is Err(InvalidEventWindowLimits),
  )
  let control = @bounded.control()
  let read = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  let execution = start_event_window(
    control,
    sequence,
    0,
    read,
    event_window_limits(max_records=4, workspace=28),
    4096L,
    fn() { true },
  ).unwrap()
  match advance_event_window(execution, 1).unwrap() {
    EventWindowContinue(..) => ()
    _ => fail("first bounded step")
  }
  @bounded.request_cancel(control) |> ignore
  match advance_event_window(execution, 1).unwrap() {
    EventWindowStopped(_, ..) => ()
    _ => fail("cancelled window")
  }
  assert_true(cleanup_event_window(execution).unwrap())
  assert_false(event_window_cleanup_pending(execution))
  assert_true(@records.discard_completed(source))
}

///|
test "event windows admit exact control work across resumes" {
  // Begin one record, read three fields, prepare membership, seek once,
  // build and commit one window, then finish: nine fixed control steps.
  // Sliding takes one additional seek and one additional build/commit pair.
  for
    (body, time, exact, rows, timestamp_clock, wide) in [
      ("{\"kind\":\"fixed\",\"size\":10}", 4.0, 9, 1, false, false),
      (
        "{\"kind\":\"sliding\",\"size\":10,\"step\":5}", 9.0, 12, 2, false, false,
      ),
      ("{\"kind\":\"fixed\",\"size\":10}", 9.0, 9, 1, true, false),
      ("{\"kind\":\"sliding\",\"size\":10,\"step\":5}", 9.0, 12, 2, true, false),
      ("{\"kind\":\"fixed\",\"size\":10}", 4.0, 10, 1, false, true),
      ("{\"kind\":\"sliding\",\"size\":10,\"step\":5}", 9.0, 13, 2, false, true),
      ("{\"kind\":\"fixed\",\"size\":10}", 9.0, 10, 1, true, true),
      ("{\"kind\":\"sliding\",\"size\":10,\"step\":5}", 9.0, 13, 2, true, true),
    ] {
    let producer = event_window_producer(timestamp=timestamp_clock, wide~)
    let owner = event_window_owner(producer, body)
    let source = if timestamp_clock {
      event_window_timestamp_source(producer, Ref(true), wide~)
    } else {
      event_window_source(producer, [time], Ref(true), wide~)
    }
    for (limit, accepted) in [(exact, true), (exact - 1, false)] {
      let read = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
      let execution = start_event_window(
        @bounded.control(),
        event_window_sequence(owner),
        0,
        read,
        event_window_limits(fields=if wide { 6 } else { 5 }),
        4096L,
        fn() { true },
        control_work_limit=Some(limit),
      ).unwrap()
      let mut terminal = false
      let mut charged = 0L
      for _ in 0..<32 {
        if !terminal {
          match advance_event_window(execution, 1).unwrap() {
            EventWindowContinue(work~, ..) => {
              assert_true(work >= charged && work - charged <= 1L)
              charged = work
            }
            EventWindowComplete(output, work~, ..) => {
              assert_true(work >= charged && work - charged <= 1L)
              charged = work
              assert_true(accepted)
              assert_eq(
                @storage.record_count(
                  @records.completed_storage(output).unwrap(),
                ),
                rows,
              )
              assert_true(@records.discard_completed(output))
              terminal = true
            }
            EventWindowFailed(EventWindowWorkLimit, work~, ..) => {
              assert_true(work >= charged && work - charged <= 1L)
              charged = work
              assert_false(accepted)
              assert_true(event_window_cleanup_pending(execution))
              terminal = true
            }
            _ => fail("unexpected event-window work result")
          }
        }
      }
      assert_true(terminal)
      assert_eq(charged, limit.to_int64())
      assert_true(cleanup_event_window(execution).unwrap())
      assert_true(@records.producer_read_available(read))
    }
    assert_true(@records.discard_completed(source))
  }
}

///|
test "event windows admit exact fixed and sliding workspace" {
  // Each emitted record has five declared fields and two window boundaries.
  // One fixed record needs seven slots; two sliding records need 14.
  for
    (body, time, workspace, rows, timestamp_clock, wide) in [
      ("{\"kind\":\"fixed\",\"size\":10}", 4.0, 7, 1, false, false),
      (
        "{\"kind\":\"sliding\",\"size\":10,\"step\":5}", 9.0, 14, 2, false, false,
      ),
      ("{\"kind\":\"fixed\",\"size\":10}", 9.0, 7, 1, true, false),
      ("{\"kind\":\"sliding\",\"size\":10,\"step\":5}", 9.0, 14, 2, true, false),
      ("{\"kind\":\"fixed\",\"size\":10}", 4.0, 8, 1, false, true),
      ("{\"kind\":\"sliding\",\"size\":10,\"step\":5}", 9.0, 16, 2, false, true),
      ("{\"kind\":\"fixed\",\"size\":10}", 9.0, 8, 1, true, true),
      ("{\"kind\":\"sliding\",\"size\":10,\"step\":5}", 9.0, 16, 2, true, true),
    ] {
    let producer = event_window_producer(timestamp=timestamp_clock, wide~)
    let owner = event_window_owner(producer, body)
    let source = if timestamp_clock {
      event_window_timestamp_source(producer, Ref(true), wide~)
    } else {
      event_window_source(producer, [time], Ref(true), wide~)
    }
    let short_read = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
    assert_true(
      start_event_window(
        @bounded.control(),
        event_window_sequence(owner),
        0,
        short_read,
        event_window_limits(
          max_records=rows,
          workspace=workspace - 1,
          fields=if wide { 6 } else { 5 },
        ),
        4096L,
        fn() { true },
      )
      is Err(InvalidEventWindowLimits),
    )
    let read = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
    let execution = start_event_window(
      @bounded.control(),
      event_window_sequence(owner),
      0,
      read,
      event_window_limits(
        max_records=rows,
        workspace~,
        fields=if wide { 6 } else { 5 },
      ),
      4096L,
      fn() { true },
    ).unwrap()
    let (output, _) = event_window_finish(execution)
    assert_eq(
      @storage.record_count(@records.completed_storage(output).unwrap()),
      rows,
    )
    assert_true(cleanup_event_window(execution).unwrap())
    assert_true(@records.discard_completed(output))
    assert_true(@records.producer_read_available(read))
    assert_true(@records.discard_completed(source))
  }
}

///|
test "empty event windows stop at the exact finish-work boundary" {
  let producer = event_window_producer()
  for
    body in [
      "{\"kind\":\"fixed\",\"size\":10}", "{\"kind\":\"sliding\",\"size\":10,\"step\":5}",
    ] {
    let owner = event_window_owner(producer, body)
    let source = event_window_source(producer, [], Ref(true))
    let read = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
    assert_true(
      start_event_window(
        @bounded.control(),
        event_window_sequence(owner),
        0,
        read,
        event_window_limits(max_records=0),
        4096L,
        fn() { true },
        control_work_limit=Some(0),
      )
      is Err(EventWindowWorkLimit),
    )
    let execution = start_event_window(
      @bounded.control(),
      event_window_sequence(owner),
      0,
      read,
      event_window_limits(max_records=0),
      4096L,
      fn() { true },
      control_work_limit=Some(1),
    ).unwrap()
    match advance_event_window(execution, 1).unwrap() {
      EventWindowComplete(output, progress=0L, work=1L) => {
        assert_eq(
          @storage.record_count(@records.completed_storage(output).unwrap()),
          0,
        )
        assert_true(@records.discard_completed(output))
      }
      _ => fail("empty window did not finish in one charged step")
    }
    assert_true(cleanup_event_window(execution).unwrap())
    assert_true(@records.discard_completed(source))
  }
}
