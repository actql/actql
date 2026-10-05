///|
test "logical Text measurement yields before scanning the whole scalar" {
  let cursor = start_logical_measure(
    Text(String::make(4096, 'g')),
    4097L,
    4098,
    1,
    0,
  ).unwrap()
  // Starting counts the scalar node, not its entire UTF-8 payload.
  assert_eq(cursor.remaining, 4096L)
  let mut done = false
  let mut polls = 0
  for _ in 0..<200 {
    if !done {
      let before = cursor.remaining
      match advance_logical_measure(cursor).unwrap() {
        None => ()
        Some(measured) => {
          assert_eq((measured.weight, measured.wire_bytes), (4097L, 4098))
          done = true
        }
      }
      assert_true(before - cursor.remaining <= 64L)
      polls += 1
    }
  }
  assert_true(done)
  assert_true(polls > 100)
}

///|
test "logical nested Text and keys keep independent exact limits" {
  let key = String::make(130, 'k')
  let text = String::make(130, 'a') + "😀"
  let value = logical_literal("{\"" + key + "\":[\"" + text + "\"]}")
  let cursor = start_logical_measure(value, 267L, 273, 3, 3).unwrap()
  let mut done = false
  for _ in 0..<100 {
    if !done {
      let before = cursor.remaining
      match advance_logical_measure(cursor).unwrap() {
        None => ()
        Some(measured) => {
          assert_eq((measured.weight, measured.wire_bytes), (267L, 273))
          done = true
        }
      }
      assert_true(before - cursor.remaining <= 70L)
    }
  }
  assert_true(done)
  assert_true(
    measure_logical_value(value, 266L, 273, 3, 3) is Err(LogicalWorkLimit),
  )
  assert_true(
    measure_logical_value(value, 267L, 272, 3, 3) is Err(WireMeasureFailure),
  )
}

///|
test "logical Text cleanup retains consumed work and closes unfinished wire" {
  for close_wire in [false, true] {
    let cursor = start_logical_measure(
      Text(String::make(4096, 'g')),
      4097L,
      4098,
      1,
      0,
    ).unwrap()
    advance_logical_measure(cursor).unwrap() |> ignore
    if close_wire {
      let mut reached = false
      for _ in 0..<200 {
        if !reached {
          advance_logical_measure(cursor).unwrap() |> ignore
          reached = cursor.emit is Some(TextWire(_)) &&
            cursor.writer is Some(writer) &&
            @encode.writer_progress(writer).0 > 1
        }
      }
      assert_true(reached)
    }
    let consumed = cursor.remaining
    let writer = cursor.writer
    clear_logical_measure(cursor)
    clear_logical_measure(cursor)
    assert_eq(cursor.remaining, consumed)
    assert_true(cursor.text is None)
    assert_true(cursor.stack.is_empty())
    assert_true(cursor.emit is None)
    assert_true(cursor.writer is None)
    assert_true(advance_logical_measure(cursor) is Err(InvalidMeasureLimits))
    if writer is Some(writer) {
      let issue = try {
        @encode.finish_measurement(writer) |> ignore
        false
      } catch {
        @encode.ClosedWriter => true
        _ => false
      }
      assert_true(issue)
    }
  }
}
