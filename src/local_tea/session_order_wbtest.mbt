///|
fn session_order_probe(
  times : Array[Double],
  quantum : Int,
) -> Array[Double] raise {
  let producer = event_window_producer()
  let owner = session_owner(producer, "[]")
  let source = event_window_source(producer, times, Ref(true))
  let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  let execution = start_session(
    @bounded.control(),
    event_window_sequence(owner),
    0,
    input,
    event_window_limits(fields=6),
    4096L,
    () => true,
  ).unwrap()
  let mut completed = None
  for _ in 0..<10000 {
    match advance_session(execution, quantum).unwrap() {
      SessionContinue(..) => ()
      SessionComplete(output, ..) => {
        completed = Some(output)
        break
      }
      _ => fail("session must complete within the admitted finite profile")
    }
  }
  let output = completed.unwrap()
  assert_true(cleanup_session(execution).unwrap())
  let storage = @records.completed_storage(output).unwrap()
  let ids = []
  assert_eq(@storage.record_count(storage), times.length())
  for record in 0..<times.length() {
    ids.push(event_window_field(storage, record, "event_id"))
    let id = ids[record]
    // IDs are originally 1 and 2; clock and labels remain tied to the ID.
    let expected_clock = if id == 1.0 { times[0] } else { times[1] }
    assert_eq(
      event_window_field(storage, record, "occurred_at"),
      expected_clock,
    )
    assert_eq(
      event_window_field(storage, record, "session_start_ms"),
      expected_clock,
    )
    assert_eq(
      event_window_field(storage, record, "session_end_ms"),
      expected_clock + 10.0,
    )
  }
  assert_true(@records.discard_completed(output))
  assert_true(@records.producer_read_available(input))
  assert_true(@records.discard_completed(source))
  ids
}

///|
test "Events session preserves reverse clock input at quantum 1" {
  assert_eq(session_order_probe([10.0, 0.0], 1), [1.0, 2.0])
}

///|
test "Events session preserves reverse clock input at quantum 7" {
  assert_eq(session_order_probe([10.0, 0.0], 7), [1.0, 2.0])
}

///|
test "Events session preserves reverse clock input at quantum 64" {
  assert_eq(session_order_probe([10.0, 0.0], 64), [1.0, 2.0])
}

///|
test "Events session ascending clock control and exact gap labels" {
  assert_eq(session_order_probe([0.0, 10.0], 7), [1.0, 2.0])
}

///|
test "Events session empty control" {
  assert_eq(session_order_probe([], 7), [])
}

///|
test "Events session preserves occurrence order and chronological identities across partitions and views" {
  for quantum in [1, 7, 64] {
    for viewed in [false, true] {
      for partitioned in [false, true] {
        let producer = event_window_producer()
        let owner = session_owner(
          producer,
          if partitioned {
            "[\"payload\"]"
          } else {
            "[]"
          },
        )
        let builder = @records.prepare_output(
          producer,
          @pipeline.Step(0),
          event_window_limits(fields=6),
          10000L,
          () => true,
        ).unwrap()
        let ids = [4.0, 10.0, 3.0, 2.0, 7.0, 8.0]
        let times = [30.0, 0.0, 20.0, 0.0, 9.0, 9.0]
        let payloads = ["a", "b", "a", "a", "a", "b"]
        for row in 0..<ids.length() {
          @records.append_record(builder, [
            (@schema.Unqualified("event_id"), event_window_number(ids[row])),
            (
              @schema.Unqualified("occurred_at"),
              event_window_number(times[row]),
            ),
            (@schema.Unqualified("payload"), event_window_text(payloads[row])),
          ]).unwrap()
        }
        let source = @records.finish_output(builder).unwrap()
        let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
        let limits = { ..event_window_limits(fields=6), max_work: 10000, }
        let execution = if viewed {
          start_session_view(
            @bounded.control(),
            event_window_sequence(owner),
            0,
            @records.producer_read_view(input).unwrap(),
            limits,
            10000L,
            () => true,
          ).unwrap()
        } else {
          start_session(
            @bounded.control(),
            event_window_sequence(owner),
            0,
            input,
            limits,
            10000L,
            () => true,
          ).unwrap()
        }
        let mut output = None
        for _ in 0..<10000 {
          match advance_session(execution, quantum).unwrap() {
            SessionContinue(..) => ()
            SessionComplete(value, ..) => {
              output = Some(value)
              break
            }
            _ => fail("session fixture did not complete")
          }
        }
        let output = output.unwrap()
        let storage = @records.completed_storage(output).unwrap()
        let starts = [30.0, 0.0, 20.0, 0.0, 0.0, 0.0]
        let ends = [40.0, 19.0, 30.0, 19.0, 19.0, 19.0]
        let global_ids = [
          "session:30:v:1:4", "session:0:v:1:2", "session:20:v:1:3", "session:0:v:1:2",
          "session:0:v:1:2", "session:0:v:1:2",
        ]
        let partition_ids = [
          "session:30:v:1:a:v:1:4", "session:0:v:1:b:v:2:10", "session:20:v:1:a:v:1:3",
          "session:0:v:1:a:v:1:2", "session:0:v:1:a:v:1:2", "session:0:v:1:b:v:2:10",
        ]
        assert_eq(@storage.record_count(storage), ids.length())
        for row in 0..<ids.length() {
          assert_eq(event_window_field(storage, row, "event_id"), ids[row])
          assert_eq(event_window_field(storage, row, "occurred_at"), times[row])
          assert_eq(session_text_field(storage, row, "payload"), payloads[row])
          assert_eq(
            event_window_field(storage, row, "session_start_ms"),
            starts[row],
          )
          assert_eq(
            event_window_field(storage, row, "session_end_ms"),
            ends[row],
          )
          assert_eq(
            session_text_field(storage, row, "session_id"),
            if partitioned {
              partition_ids[row]
            } else {
              global_ids[row]
            },
          )
        }
        assert_true(cleanup_session(execution).unwrap())
        assert_true(@records.discard_completed(output))
        assert_true(@records.producer_read_available(input))
        assert_true(@records.discard_completed(source))
      }
    }
  }
}

///|
test "Events session cancellation releases retained labels and final emission" {
  for emitting in [false, true] {
    let producer = event_window_producer()
    let owner = session_owner(producer, "[]")
    let source = event_window_source(producer, [10.0, 0.0], Ref(true))
    let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
    let control = @bounded.control()
    let execution = start_session(
      control,
      event_window_sequence(owner),
      0,
      input,
      event_window_limits(fields=6),
      4096L,
      () => true,
    ).unwrap()
    let mut reached = false
    for _ in 0..<1000 {
      if (emitting && execution.state.phase is EmitFields) ||
        (!emitting && execution.state.phase is LabelRecords) {
        reached = true
        break
      }
      assert_true(advance_session(execution, 1).unwrap() is SessionContinue(..))
    }
    assert_true(reached)
    assert_true(execution.state.label_starts.length() == 2)
    assert_true(@bounded.request_cancel(control))
    assert_true(advance_session(execution, 1).unwrap() is SessionStopped(_, ..))
    assert_true(cleanup_session(execution).unwrap())
    assert_eq(execution.state.label_starts.length(), 0)
    assert_eq(execution.state.label_ends.length(), 0)
    assert_eq(execution.state.target_order.length(), 0)
    assert_true(@records.producer_read_available(input))
    assert_true(@records.discard_completed(source))
  }
}
