///|
fn bounded_view_finish_fixture(
  work? : Int = 206,
  bytes? : Int = 212,
  nodes? : Int = 204,
) -> (
  ManagedViewOutputPort[Unit, Int],
  ManagedOutputValues,
  ManagedCompletedOutput[Int],
  Ref[Bool],
  Ref[Int],
) raise {
  let owner = capture_fixture()
  let live = Ref(true)
  let source = managed_read_fixture(owner, live, index_cells=4)
  let copied_fields = Array::makei(100, index => {
    "\"v" + index.to_string() + "\":\"n\""
  }).join(",")
  let receiver = typed_receiver(owner, "[{\"derive\":{" + copied_fields + "}}]")
  let input = prepare_managed_producer_read(
    receiver, 0, owner, source, 1000, 10000,
  ).unwrap()
  let plan = prepare_managed_view_plan(
    input,
    [row_kernel(receiver, 0)],
    100000,
    100000,
    200,
  ).unwrap()
  let selected = prepare_managed_view_selection(plan, [0, 1], 204, 100000).unwrap()
  let stream = prepare_managed_output_values(
    receiver,
    Step(0),
    2,
    {
      max_nodes: 10000,
      max_text_bytes: 100000,
      max_depth: 10,
      max_work: 100000,
    },
    100,
    { max_work: work, max_bytes: bytes, max_nodes: nodes, max_depth: 10, },
  ).unwrap()
  let calls = Ref(0)
  let port = prepare_managed_selected_view_output_port(selected, stream, (
    _ : Unit,
  ) => {
    calls.val += 1
    true
  }).unwrap()
  (port, stream, source, live, calls)
}

///|
test "wide selected view finish preserves exact accounting across quanta" {
  for quantum in [1, 7, 64] {
    let (port, stream, source, live, calls) = bounded_view_finish_fixture()
    assert_true(advance_managed_view_output_finish(port, (), 0) is Err(Closed))
    assert_true(port.open)
    let mut receipt = None
    let mut steps = 0
    // 102 fields: verification (1), facts (102+3), receipt (102+5).
    while receipt is None {
      let poll = advance_managed_view_output_finish(port, (), quantum).unwrap()
      assert_true(poll.steps > 0 && poll.steps <= quantum)
      steps += poll.steps
      assert_true(steps <= 213)
      receipt = poll.receipt
      if receipt is None {
        assert_true(finish_managed_view_output(port, ()) is Err(Closed))
        assert_true(finish_managed_output_values(stream) is Err(Closed))
        assert_true(
          append_managed_output_values(stream, 0, _ => None) is Err(Closed),
        )
      }
    }
    assert_eq(steps, 213)
    assert_eq(calls.val, 1)
    let receipt = receipt.unwrap()
    // Two source rows contain n=1/2, s="é"/"😀", and 100 copies of n.
    assert_eq(managed_output_value_measurement(receipt), (206, 212, 204))
    assert_eq(managed_output_measurement_index_cells(receipt), Some(204))
    assert_eq(
      (
        stream.measurement.work,
        stream.measurement.bytes,
        stream.measurement.nodes,
      ),
      (0, 0, 0),
    )
    assert_false(cancel_managed_view_output_port(port))
    assert_eq(managed_output_measurement_index_cells(receipt), Some(204))
    live.val = false
    assert_eq(
      managed_output_measurement_index_cells(source.material.receipt),
      Some(4),
    )
  }
}

///|
test "wide selected view one-short work and capacity remain typed" {
  for quantum in [1, 7, 64] {
    for limit in 0..<3 {
      let (port, _, _, _, calls) = bounded_view_finish_fixture(
        work=if limit == 0 { 205 } else { 206 },
        bytes=if limit == 1 { 211 } else { 212 },
        nodes=if limit == 2 { 203 } else { 204 },
      )
      let mut failed = false
      for _ in 0..<600 {
        match advance_managed_view_output_finish(port, (), quantum) {
          Ok(poll) => assert_true(poll.receipt is None)
          Err(issue) => {
            if limit == 0 {
              assert_true(issue is Values(Guard(MeasurementWork)))
            } else {
              assert_true(
                issue
                is Values(
                  Guard(Measurement(Output, 1, 101, @encode.OutputLimit))
                ),
              )
            }
            failed = true
            break
          }
        }
      }
      assert_true(failed)
      assert_eq(calls.val, 1)
      assert_true(port.index is None)
    }
  }
}

///|
test "yielded view facts cannot replace an already validated column" {
  let (port, _, _, _, calls) = bounded_view_finish_fixture()
  // The first poll verifies; the second validates n for the two authored rows.
  advance_managed_view_output_finish(port, (), 1).unwrap() |> ignore
  advance_managed_view_output_finish(port, (), 1).unwrap() |> ignore
  let facts = port.facts_cursor.unwrap().facts
  assert_eq((facts.columns[0].bytes, facts.columns[0].nodes), (2, 2))
  facts.columns[0] = {
    ..facts.columns[0],
    bytes: 1000000,
    max_value_bytes: 1000000,
  }
  let mut receipt = None
  for _ in 0..<600 {
    let poll = advance_managed_view_output_finish(port, (), 1).unwrap()
    receipt = poll.receipt
    if receipt is Some(_) {
      break
    }
  }
  assert_eq(calls.val, 1)
  assert_true(receipt is Some(_))
  assert_eq(receipt.unwrap().column_usage[0], (2, 2))
  assert_eq(managed_output_value_measurement(receipt.unwrap()), (206, 212, 204))
}

///|
test "changed pending view fact width is rejected before receipt issuance" {
  for grow in [false, true] {
    let (port, stream, source, _, _) = bounded_view_finish_fixture()
    advance_managed_view_output_finish(port, (), 1).unwrap() |> ignore
    let facts = port.facts_cursor.unwrap().facts
    if grow {
      facts.columns.push(facts.columns[0])
    } else {
      facts.columns.pop() |> ignore
    }
    assert_true(
      advance_managed_view_output_finish(port, (), 1) is Err(InconsistentFacts),
    )
    assert_false(stream.open)
    assert_true(port.index is None)
    assert_eq(
      managed_output_measurement_index_cells(source.material.receipt),
      Some(4),
    )
  }
}

///|
test "cancelled ordered view diagnosis retains consumed work and capacity" {
  let (port, stream, source, _, calls) = bounded_view_finish_fixture(bytes=211)
  // Verification, 102 column checks, boundary and choice precede ordered
  // diagnosis. Its first row and first numeric cell consume work 2/bytes 1.
  for _ in 0..<107 {
    let poll = advance_managed_view_output_finish(port, (), 1).unwrap()
    assert_true(poll.receipt is None)
  }
  assert_eq(calls.val, 1)
  assert_true(port.facts_cursor.unwrap().phase is MeasureIndex)
  assert_eq(
    (
      stream.measurement.work,
      stream.measurement.bytes,
      stream.measurement.nodes,
    ),
    (204, 210, 203),
  )
  assert_true(cancel_managed_view_output_port(port))
  assert_true(advance_managed_view_output_finish(port, (), 1) is Err(Closed))
  assert_eq(
    (
      stream.measurement.work,
      stream.measurement.bytes,
      stream.measurement.nodes,
    ),
    (204, 210, 203),
  )
  assert_eq(
    managed_output_measurement_index_cells(source.material.receipt),
    Some(4),
  )
  dispose_managed_output_values_scratch(stream)
  for _ in 0..<16 {
    if advance_managed_output_values_reclamation(stream, 64) {
      break
    }
  }
  assert_true(managed_output_values_scratch_released(stream))
}

///|
test "selected view cancellation and revoked input cannot escape a yielded finish" {
  for stop in [1, 20, 106, 150, 212] {
    for revoked in [false, true] {
      let (port, stream, source, live, calls) = bounded_view_finish_fixture()
      for _ in 0..<stop {
        let poll = advance_managed_view_output_finish(port, (), 1).unwrap()
        assert_true(poll.receipt is None)
      }
      assert_eq(calls.val, 1)
      if revoked {
        live.val = false
        assert_true(
          advance_managed_view_output_finish(port, (), 1) is Err(ForeignBinding),
        )
      } else {
        assert_true(cancel_managed_view_output_port(port))
        assert_true(
          advance_managed_view_output_finish(port, (), 1) is Err(Closed),
        )
      }
      assert_true(port.index is None)
      assert_true(port.facts_cursor is None)
      assert_false(stream.open)
      assert_eq(
        managed_output_measurement_index_cells(source.material.receipt),
        Some(4),
      )
      dispose_managed_output_values_scratch(stream)
      for _ in 0..<16 {
        if advance_managed_output_values_reclamation(stream, 64) {
          break
        }
      }
      assert_true(managed_output_values_scratch_released(stream))
    }
  }
}
