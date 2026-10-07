///|
test "managed admission retirement is incremental and preserves receipt facts" {
  for quantum in [1, 7, 64] {
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
    let columns = receipt.column_usage.copy()
    assert_eq(managed_output_measurement_index_cells(receipt), Some(200))
    assert_false(advance_managed_output_values_reclamation(stream, 1))
    dispose_managed_output_values_scratch(stream)
    assert_false(managed_output_values_scratch_released(stream))
    let remaining = stream.reference_rows.length()
    for _ in 0..<10 {
      assert_false(managed_output_values_scratch_released(stream))
    }
    assert_eq(stream.reference_rows.length(), remaining)
    assert_false(advance_managed_output_values_reclamation(stream, 0))
    assert_eq(stream.reference_rows.length(), remaining)
    // Each original row contributes two empty reference containers and one
    // row container. There are six column counters and one buffer boundary.
    // The successful receipt already owns the measurement index.
    let remaining_entries = 100 * (2 + 1) + 3 * 2 + 1 - 64
    let polls = (remaining_entries + quantum - 1) / quantum
    for poll in 0..<polls {
      assert_eq(
        advance_managed_output_values_reclamation(stream, quantum),
        poll == polls - 1,
      )
    }
    assert_true(managed_output_values_scratch_released(stream))
    assert_true(advance_managed_output_values_reclamation(stream, 1))
    dispose_managed_output_values_scratch(stream)
    assert_true(managed_output_values_scratch_released(stream))
    assert_eq(managed_output_measurement_index_cells(receipt), Some(200))
    assert_eq(managed_output_value_row_count(receipt), 100)
    assert_eq(managed_output_value_measurement(receipt), measured)
    assert_eq(managed_output_value_usage(receipt), usage)
    assert_eq(receipt.column_usage, columns)
    assert_eq(receipt.reference_rows.length(), 100)
    assert_eq(receipt.reference_rows[99].length(), 2)
    assert_true(finish_managed_output_values(stream) is Err(Closed))
    assert_true(
      append_managed_output_values(stream, 0, _ => None) is Err(Closed),
    )
  }
}

///|
test "managed admission cancellation revokes without retiring unbounded scratch" {
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
  let work = stream.measurement.work
  assert_true(cancel_managed_output_values(stream))
  assert_eq(stream.reference_rows.length(), 100)
  assert_false(managed_output_values_scratch_released(stream))
  assert_false(cancel_managed_output_values(stream))
  assert_false(advance_managed_output_values_reclamation(stream, 0))
  // Buffer boundary, untransferred index, 300 containers, six counters.
  for entry in 0..<308 {
    assert_eq(
      advance_managed_output_values_reclamation(stream, 1),
      entry == 307,
    )
  }
  assert_true(managed_output_values_scratch_released(stream))
  assert_eq(stream.measurement.work, work)
  assert_true(finish_managed_output_values(stream) is Err(Closed))
}

///|
test "managed reference retirement keeps receipt authority independent" {
  let owner = managed_reference_owner()
  let values = prepare_managed_output_values(
    owner,
    Step(0),
    80,
    {
      max_nodes: 10000,
      max_text_bytes: 100000,
      max_depth: 10,
      max_work: 100000,
    },
    8192,
    { max_work: 100000, max_bytes: 100000, max_nodes: 10000, max_depth: 10, },
  ).unwrap()
  let live = Ref(true)
  let wire = managed_reference_wire()
  let contract = @schema.field_at(managed_output_values_schema(values), 0).unwrap().contract
  let checked = @admitted.issue_reference(
    @admitted.bind_reference_issuer((_, candidate) => candidate == wire, _ => {
      live.val
    }),
    contract,
    wire,
    { max_bytes: 4096, max_nodes: 64, max_depth: 4, max_text_units: 4096, },
  ).unwrap()
  for _ in 0..<80 {
    append_managed_output_values(values, 1, _ => Some(checked)).unwrap()
  }
  let receipt = finish_managed_output_values(values).unwrap()
  assert_true(cancel_managed_output_values(values) == false)
  dispose_managed_output_values_scratch(values)
  assert_false(managed_output_values_scratch_released(values))
  // One buffer boundary, then one reference, column and row per original row,
  // followed by three metadata entries. Sixty-four entries were already retired.
  for entry in 0..<(1 + 80 * 3 + 3 - 64) {
    assert_eq(
      advance_managed_output_values_reclamation(values, 1),
      entry == 1 + 80 * 3 + 3 - 64 - 1,
    )
  }
  assert_true(managed_output_values_scratch_released(values))
  for row in receipt.reference_rows {
    assert_eq(row.length(), 1)
    assert_eq(row[0].length(), 1)
    assert_eq(
      @admitted.reference_identity_cid(row[0][0]),
      "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
    )
    assert_true(@admitted.reference_available(row[0][0]))
  }
  live.val = false
  assert_false(@admitted.reference_available(receipt.reference_rows[0][0][0]))
}
