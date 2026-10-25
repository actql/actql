///|
test "successful receipt scratch retirement begins without hidden work and preserves output" {
  for quantum in [1, 64, 2147483647] {
    let owner = capture_fixture()
    let stream = prepare_managed_output_values(
      owner,
      Step(1),
      100,
      stream_value_limits(),
      100,
      managed_test_measure_limits(),
    ).unwrap()
    enable_managed_row_measurements(stream, 200).unwrap()
    let cells = output_fixture_row(owner, 0)
    for _ in 0..<100 {
      append_managed_output_values(stream, cells.length(), column => {
        cells.get(column)
      }).unwrap()
    }
    let receipt = finish_managed_output_values(stream).unwrap()
    let measured = managed_output_value_measurement(receipt)
    let usage = managed_output_value_usage(receipt)
    let semantic_work = stream.measurement.work
    let before = managed_output_values_reclamation_steps(stream)
    request_managed_output_values_disposal(stream)
    assert_eq(managed_output_values_reclamation_steps(stream), before)
    assert_false(advance_managed_output_values_reclamation(stream, 0))
    assert_false(advance_managed_output_values_reclamation(stream, -1))
    assert_eq(managed_output_values_reclamation_steps(stream), before)
    assert_true(
      append_managed_output_values(stream, 0, _ => None) is Err(Closed),
    )
    assert_true(finish_managed_output_values(stream) is Err(Closed))
    let mut polls = 0
    while !managed_output_values_scratch_released(stream) {
      let start = managed_output_values_reclamation_steps(stream)
      advance_managed_output_values_reclamation(stream, quantum) |> ignore
      let spent = managed_output_values_reclamation_steps(stream) - start
      assert_true(spent >= 0L && spent <= quantum.to_int64())
      polls += 1
    }
    if quantum <= 64 {
      assert_true(polls > 1)
    }
    assert_eq(stream.measurement.work, semantic_work)
    assert_eq(managed_output_value_row_count(receipt), 100)
    assert_eq(managed_output_measurement_index_cells(receipt), Some(200))
    assert_eq(managed_output_value_measurement(receipt), measured)
    assert_eq(managed_output_value_usage(receipt), usage)
    assert_eq(receipt.reference_rows[99].length(), 2)
    request_managed_output_values_disposal(stream)
    assert_true(advance_managed_output_values_reclamation(stream, 1))
  }
}

///|
test "successful and one-short semantic admission both retain bounded cleanup authority" {
  let owner = capture_fixture()
  let cells = output_fixture_row(owner, 0)
  let probe = prepare_managed_output_values(
    owner,
    Step(1),
    100,
    stream_value_limits(),
    100,
    managed_test_measure_limits(),
  ).unwrap()
  for _ in 0..<100 {
    append_managed_output_values(probe, cells.length(), column => {
      cells.get(column)
    }).unwrap()
  }
  let needed = managed_test_measure_limits().max_work - probe.measurement.work
  request_managed_output_values_disposal(probe)
  while !advance_managed_output_values_reclamation(probe, 64) {

  }
  for budget in [needed, needed - 1] {
    let stream = prepare_managed_output_values(
      owner,
      Step(1),
      100,
      stream_value_limits(),
      100,
      { ..managed_test_measure_limits(), max_work: budget, },
    ).unwrap()
    let mut accepted = 0
    for _ in 0..<100 {
      match
        append_managed_output_values(stream, cells.length(), column => {
          cells.get(column)
        }) {
        Ok(_) => accepted += 1
        Err(_) => break
      }
    }
    if budget == needed {
      assert_eq(accepted, 100)
      assert_eq(stream.measurement.work, 0)
      assert_eq(
        managed_output_value_row_count(
          finish_managed_output_values(stream).unwrap(),
        ),
        100,
      )
    } else {
      // Measurement records a pending guard failure; receipt issuance is the
      // atomic semantic boundary, not necessarily the last append.
      assert_true(finish_managed_output_values(stream) is Err(_))
    }
    let remaining = stream.measurement.work
    request_managed_output_values_disposal(stream)
    advance_managed_output_values_reclamation(stream, 1) |> ignore
    // Cancellation may arrive between successful finalization cleanup polls.
    cancel_managed_output_values(stream) |> ignore
    request_managed_output_values_disposal(stream)
    while !advance_managed_output_values_reclamation(stream, 1) {

    }
    assert_true(managed_output_values_scratch_released(stream))
    assert_eq(stream.measurement.work, remaining)
    assert_true(
      append_managed_output_values(stream, 0, _ => None) is Err(Closed),
    )
  }
}
