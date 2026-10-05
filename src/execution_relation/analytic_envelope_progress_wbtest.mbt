///|
test "analytic envelope yields within copied long Text emission" {
  let owner = aggregate_output_text_owner(
    "{\"analytic\":{\"partition_by\":[\"group\"],\"order_by\":[{\"id\":\"asc\"}],\"functions\":{\"position\":{\"fn\":\"row_number\"}}}}",
  )
  let input = aggregate_output_text_input(owner)
  let workspace = row_workspace(10000)
  let accepted : Array[Array[Value]] = []
  let state = start_analytic_evaluation(
    @lower.kernel_analytic(row_kernel(owner, 0)).unwrap(),
    input,
    1,
    { remaining: 100000, max_frames: 100, },
    row_output(),
    workspace,
    None,
    [],
    Some(analytic_test_envelope(100000L, 100000L, 100000L, 0L, 1L)),
    run_limits().input_values,
    None,
    0,
    (row, _) => {
      accepted.push(row)
      Ok(())
    },
  )
  let mut maximum = 0
  let mut done = false
  for _ in 0..<10000 {
    if !done {
      let before = [state.writer, state.output_writer].map(writer => {
        writer.map(writer => (writer, @encode.writer_progress(writer).0))
      })
      match advance_analytic_evaluation(state) {
        Ok(Some(_)) => done = true
        Ok(None) => ()
        Err(_) => fail("analytic envelope rejected the valid control")
      }
      for index, writer in [state.writer, state.output_writer] {
        if writer is Some(writer) &&
          before[index] is Some((prior, bytes)) &&
          physical_equal(writer, prior) {
          maximum = Int::max(maximum, @encode.writer_progress(writer).0 - bytes)
        }
      }
    }
  }
  close_analytic_evaluation(state)
  assert_true(done)
  assert_eq(accepted.length(), 1)
  assert_true(accepted[0][0] is Number(7))
  assert_true(accepted[0][1] is Text(text) && text == String::make(4096, 'g'))
  assert_true(accepted[0][2] is Number(1))
  assert_true(accepted[0][3] is Number(1))
  assert_true(accepted[0][4] is Text("open"))
  // The copied ASCII Text alone must not be emitted in one analytic step.
  // This fixed bound allows a small field key and one 64-unit Text chunk.
  assert_true(maximum <= 256)
}

///|
test "analytic closes input partition and output wire custody mid Text" {
  for boundary in 0..<3 {
    let owner = aggregate_output_text_owner(
      "{\"analytic\":{\"partition_by\":[\"group\"],\"order_by\":[{\"id\":\"asc\"}],\"functions\":{\"position\":{\"fn\":\"row_number\"}}}}",
    )
    let input = aggregate_output_text_input(owner)
    let workspace = row_workspace(10000)
    let control = { remaining: 100000, max_frames: 100, }
    let accepted = Ref(0)
    let state = start_analytic_evaluation(
      @lower.kernel_analytic(row_kernel(owner, 0)).unwrap(),
      input,
      1,
      control,
      row_output(),
      workspace,
      None,
      [],
      Some(analytic_test_envelope(100000L, 100000L, 100000L, 0L, 1L)),
      run_limits().input_values,
      None,
      0,
      (_, _) => {
        accepted.val += 1
        Ok(())
      },
    )
    let mut reached = false
    let mut wire_steps = 0
    for _ in 0..<10000 {
      if !reached {
        assert_true(advance_analytic_evaluation(state).unwrap() is None)
        let phase = if state.output_writer is Some(_) {
          2
        } else if state.measure_scope == InputWireBytes {
          0
        } else {
          1
        }
        if phase == boundary &&
          state.wire is Some(cursor) &&
          cursor.cursor is TextWire(_) {
          wire_steps += 1
          // Starting the cursor writes its quote; the next step writes a chunk.
          reached = wire_steps == 2
        }
      }
    }
    assert_true(reached)
    let cursor = state.wire.unwrap()
    let slots = workspace.live
    let reserved = cursor.reserved
    let work = control.remaining
    let writer = match state.writer {
      Some(writer) => writer
      None => state.output_writer.unwrap()
    }
    assert_eq(accepted.val, 0)
    close_analytic_evaluation(state)
    close_analytic_evaluation(state)
    assert_true(cursor.closed)
    assert_eq(workspace.live, slots - reserved)
    assert_eq(control.remaining, work)
    assert_true(
      state.wire is None && state.writer is None && state.output_writer is None,
    )
    assert_true(advance_analytic_evaluation(state) is Err(InvalidRows))
    assert_true(
      try {
        @encode.finish_measurement(writer) |> ignore
        false
      } catch {
        @encode.ClosedWriter => true
        _ => false
      },
    )
    assert_true(
      IndexedRows::read_cell(input, 0, 1) is Text(text) && text.length() == 4096,
    )
    assert_eq(accepted.val, 0)
  }
}

///|
test "analytic stepped Text keeps independent exact wire envelope limits" {
  let owner = aggregate_output_text_owner(
    "{\"analytic\":{\"partition_by\":[\"group\"],\"order_by\":[{\"id\":\"asc\"}],\"functions\":{\"position\":{\"fn\":\"row_number\"}}}}",
  )
  // Independent row literals, not a measurement of the evaluated output.
  let text = String::make(4096, 'g')
  let input = "[{\"amount\":7,\"group\":\"" +
    text +
    "\",\"id\":1,\"status\":\"open\"}]"
  let output = "[{\"amount\":7,\"group\":\"" +
    text +
    "\",\"id\":1,\"position\":1,\"status\":\"open\"}]"
  // All characters here are ASCII: the literal length is its UTF-8 byte cost.
  let exact = analytic_test_envelope(
    input.length().to_int64(),
    output.length().to_int64(),
    input.length().to_int64(),
    0L,
    1L,
  )
  for
    (envelope, expected) in [
      (exact, None),
      (
        { ..exact, input_wire_bytes: exact.input_wire_bytes - 1L, },
        Some(InputWireBytes),
      ),
      (
        { ..exact, partition_wire_bytes: exact.partition_wire_bytes - 1L, },
        Some(PartitionWireBytes),
      ),
      (
        { ..exact, output_wire_bytes: exact.output_wire_bytes - 1L, },
        Some(OutputWireBytes),
      ),
    ] {
    let workspace = row_workspace(10000)
    let accepted = Ref(0)
    let state = start_analytic_evaluation(
      @lower.kernel_analytic(row_kernel(owner, 0)).unwrap(),
      aggregate_output_text_input(owner),
      1,
      { remaining: 100000, max_frames: 100, },
      row_output(),
      workspace,
      None,
      [],
      Some(envelope),
      run_limits().input_values,
      None,
      0,
      (_, _) => {
        accepted.val += 1
        Ok(())
      },
    )
    let mut terminal = false
    let mut completed = false
    for _ in 0..<10000 {
      if !terminal {
        match advance_analytic_evaluation(state) {
          Ok(None) => ()
          Ok(Some(_)) => {
            assert_true(expected is None)
            completed = true
            terminal = true
          }
          Err(AnalyticEnvelope(scope)) => {
            assert_eq(expected, Some(scope))
            terminal = true
          }
          Err(_) => fail("unexpected envelope failure")
        }
      }
    }
    assert_true(terminal)
    assert_eq(completed, expected is None)
    // The final array bracket is checked after a privately accepted row.
    // A one-short output envelope must still reject completion/publication.
    assert_eq(
      accepted.val,
      if expected is None || expected == Some(OutputWireBytes) {
        1
      } else {
        0
      },
    )
    close_analytic_evaluation(state)
    assert_true(state.wire is None)
  }
}
