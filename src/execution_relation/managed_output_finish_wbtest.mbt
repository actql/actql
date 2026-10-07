///|
test "managed receipt finish copies bounded entries with quantum independent facts" {
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
    let usage = stream.buffer.budget
    let work = stream.measurement.work
    let mut total_steps = 0
    let mut receipt = None
    // Two row boundaries and two boundaries per empty reference column:
    // 600 row/column entries, three phase changes, two counters, a boundary
    // and issuance. No reference or producer-input callback is required.
    while receipt is None {
      let poll = advance_managed_output_values_finish(stream, quantum).unwrap()
      assert_true(poll.steps > 0 && poll.steps <= quantum)
      total_steps += poll.steps
      assert_true(total_steps <= 607)
      receipt = poll.receipt
      if receipt is None {
        assert_true(stream.finish_cursor is Some(_))
        assert_true(finish_managed_output_values(stream) is Err(Closed))
        assert_true(
          append_managed_output_values(stream, 0, _ => None) is Err(Closed),
        )
      }
    }
    assert_eq(total_steps, 607)
    let receipt = receipt.unwrap()
    assert_true(stream.finish_cursor is None)
    assert_eq(receipt.rows, 100)
    assert_eq(receipt.reference_rows.length(), 100)
    assert_eq(receipt.reference_rows[99].length(), 2)
    assert_eq(receipt.column_usage, stream.column_usage)
    assert_eq(receipt.column_maxima, stream.column_maxima)
    assert_eq(receipt.column_nulls, stream.column_nulls)
    assert_eq(managed_output_measurement_index_cells(receipt), Some(200))
    // Each authored row contains Number 1 and Text "é": one UTF-8 number
    // byte, four UTF-8 canonical Text bytes, and two measured value nodes.
    assert_eq(managed_output_value_measurement(receipt), (300, 500, 200))
    // Three nodes plus two field-name bytes plus two Text payload bytes
    // consume seven admission work units per row, independently of polling.
    assert_eq(receipt.usage, { nodes: 300, text_bytes: 400, work: 700, })
    assert_eq(stream.measurement.work, work)
    assert_eq(receipt.usage, {
      nodes: usage.nodes,
      text_bytes: usage.text,
      work: usage.work,
    })
    assert_true(advance_managed_output_values_finish(stream, 1) is Err(Closed))
  }
}

///|
test "managed receipt reference revalidation yields between authority callbacks" {
  let owner = managed_reference_owner()
  let stream = prepare_managed_output_values(
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
  let calls = Ref(0)
  let contract = @schema.field_at(stream.buffer.schema, 0).unwrap().contract
  let wire = managed_reference_wire()
  let checked = @admitted.issue_reference(
    @admitted.bind_reference_issuer((_, candidate) => candidate == wire, _ => {
      calls.val += 1
      true
    }),
    contract,
    wire,
    { max_bytes: 4096, max_nodes: 64, max_depth: 4, max_text_units: 4096, },
  ).unwrap()
  for _ in 0..<80 {
    append_managed_output_values(stream, 1, _ => Some(checked)).unwrap()
  }
  calls.val = 0
  let mut total_steps = 0
  let mut receipt = None
  while receipt is None {
    let before = calls.val
    let poll = advance_managed_output_values_finish(stream, 1).unwrap()
    assert_true(calls.val - before <= 1)
    assert_eq(poll.steps, 1)
    total_steps += 1
    assert_true(total_steps <= 406)
    receipt = poll.receipt
  }
  assert_eq(total_steps, 406)
  assert_eq(calls.val, 80)
  assert_eq(receipt.unwrap().reference_rows[79][0].length(), 1)
}

///|
test "partial receipt cancellation retains copies until incremental cleanup" {
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
  assert_true(advance_managed_output_values_finish(stream, 0) is Err(Closed))
  assert_false(stream.finish_started)
  let poll = advance_managed_output_values_finish(stream, 8).unwrap()
  assert_true(poll.receipt is None)
  assert_eq(stream.finish_cursor.unwrap().references.length(), 2)
  let measured_work = stream.measurement.work
  assert_true(cancel_managed_output_values(stream))
  assert_false(managed_output_values_scratch_released(stream))
  assert_true(advance_managed_output_values_finish(stream, 1) is Err(Closed))
  // Existing 308 entries plus three copied columns, two copied row roots and
  // the cursor root. Cancellation itself does not drive this retirement.
  for entry in 0..<314 {
    assert_eq(
      advance_managed_output_values_reclamation(stream, 1),
      entry == 313,
    )
  }
  assert_true(managed_output_values_scratch_released(stream))
  assert_eq(stream.measurement.work, measured_work)
}

///|
test "partial receipt detects reference revocation before its resumed visit" {
  let owner = managed_reference_owner()
  let stream = prepare_managed_output_values(
    owner,
    Step(0),
    1,
    { max_nodes: 100, max_text_bytes: 10000, max_depth: 10, max_work: 10000, },
    8192,
    managed_test_measure_limits(),
  ).unwrap()
  let live = Ref(true)
  let contract = @schema.field_at(stream.buffer.schema, 0).unwrap().contract
  let wire = managed_reference_wire()
  let checked = @admitted.issue_reference(
    @admitted.bind_reference_issuer((_, candidate) => candidate == wire, _ => {
      live.val
    }),
    contract,
    wire,
    { max_bytes: 4096, max_nodes: 64, max_depth: 4, max_text_units: 4096, },
  ).unwrap()
  append_managed_output_values(stream, 1, _ => Some(checked)).unwrap()
  assert_true(
    advance_managed_output_values_finish(stream, 2).unwrap().receipt is None,
  )
  live.val = false
  assert_true(
    advance_managed_output_values_finish(stream, 1)
    is Err(ReferenceUnavailable(0, 0)),
  )
  assert_true(finish_managed_output_values(stream) is Err(Closed))
  dispose_managed_output_values_scratch(stream)
  assert_true(managed_output_values_scratch_released(stream))
}

///|
test "receipt callback disposal preserves active copies and resumes cleanup" {
  let owner = managed_reference_owner()
  let stream = prepare_managed_output_values(
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
  let armed = Ref(false)
  let reentry_rejected = Ref(false)
  let active_roots_preserved = Ref(false)
  let contract = @schema.field_at(stream.buffer.schema, 0).unwrap().contract
  let wire = managed_reference_wire()
  let checked = @admitted.issue_reference(
    @admitted.bind_reference_issuer((_, candidate) => candidate == wire, _ => {
      if armed.val {
        reentry_rejected.val = finish_managed_output_values(stream)
          is Err(Closed)
        dispose_managed_output_values_scratch(stream)
        active_roots_preserved.val = stream.finish_cursor is Some(_) &&
          stream.reference_rows.length() == 80 &&
          !managed_output_values_scratch_released(stream)
      }
      true
    }),
    contract,
    wire,
    { max_bytes: 4096, max_nodes: 64, max_depth: 4, max_text_units: 4096, },
  ).unwrap()
  for _ in 0..<80 {
    append_managed_output_values(stream, 1, _ => Some(checked)).unwrap()
  }
  armed.val = true
  assert_true(advance_managed_output_values_finish(stream, 3) is Err(Closed))
  assert_true(reentry_rejected.val)
  assert_true(active_roots_preserved.val)
  assert_false(managed_output_values_scratch_released(stream))
  // Buffer boundary, copied column/row/cursor, 240 original reference roots
  // and three column counters; the returned frame retired 64 entries.
  for entry in 0..<(1 + 3 + 240 + 3 - 64) {
    assert_eq(
      advance_managed_output_values_reclamation(stream, 1),
      entry == 1 + 3 + 240 + 3 - 64 - 1,
    )
  }
  assert_true(managed_output_values_scratch_released(stream))
}
