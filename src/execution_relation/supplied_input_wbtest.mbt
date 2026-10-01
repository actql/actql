///|
fn input_cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(
      text,
      { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      source_path="supplied.json",
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
fn input_owner() -> @lower.BoundPrepared {
  let seed = capture_values(capture_fixture(), 0, max_rows=2, {
    max_nodes: 100,
    max_text_bytes: 100,
    max_depth: 10,
    max_work: 200,
  }).unwrap()
  let pipeline = @pipeline.check(
    input_cursor("[{\"select\":[\"s\",\"n\"]}]"),
    [("select_0", captured_schema(seed))],
    None,
    Some(input_cursor("\"select_0\"")),
    {
      max_steps: 100,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(pipeline, {
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
test "supplied input admits exact checked schema independently of input object order" {
  let owner = input_owner()
  let supplied = [input_cursor("{\"s\":\"é\",\"n\":3}")]
  let rows = capture_input(owner, 0, supplied, max_rows=1, {
    max_nodes: 3,
    max_text_bytes: 4,
    max_depth: 2,
    max_work: 7,
  }).unwrap()
  assert_eq(captured_origin(rows), SuppliedInput(0))
  assert_true(physical_equal(captured_owner(rows), owner))
  assert_true(captured_cell(rows, 0, 0) is Some(@admitted.Number(3.0)))
  assert_true(captured_cell(rows, 0, 1) is Some(@admitted.Text("é")))
  assert_eq(captured_usage(rows), { nodes: 3, text_bytes: 4, work: 7, })
  supplied[0] = input_cursor("{\"s\":\"changed\",\"n\":100}")
  supplied.clear()
  assert_true(captured_cell(rows, 0, 1) is Some(@admitted.Text("é")))
}

///|
test "supplied input rejects malformed values without coercion or source normalization" {
  let owner = input_owner()
  let limits = {
    max_nodes: 100,
    max_text_bytes: 100,
    max_depth: 10,
    max_work: 200,
  }
  for
    text in [
      "{\"s\":\"ok\",\"n\":null}", "{\"s\":\"ok\",\"n\":\"3\"}", "{\"s\":\"ok\"}",
      "{\"s\":\"ok\",\"n\":3,\"extra\":4}",
    ] {
    guard capture_input(owner, 0, [input_cursor(text)], max_rows=1, limits)
      is Err(InputValue(0, _)) else {
      fail("invalid data admitted: " + text)
    }
  }
  let good = input_cursor("{\"s\":\"ok\",\"n\":3}")
  let bad = input_cursor("{\"s\":\"ok\",\"n\":null}")
  guard capture_input(owner, 0, [good, bad], max_rows=2, limits)
    is Err(InputValue(1, _)) else {
    fail("partial result")
  }
  assert_true(capture_input(owner, 0, [good], max_rows=1, limits) is Ok(_))
  // Source parsing intentionally normalizes. Construct noncanonical supplied
  // data after that boundary to test capture, not source authoring semantics.
  let raw = @source.parse_json("{\"s\":\"ok\",\"n\":3}", {
    max_input_bytes: 1000,
    max_nodes: 100,
    max_depth: 10,
  }).unwrap()
  guard raw.value is @source.Object(fields) else { fail("object") }
  fields[0] = {
    ..fields[0],
    value: { ..fields[0].value, value: @source.String("e\u{0301}"), },
  }
  let noncanonical = @decode.admit(raw, {
    max_nodes: 100,
    max_depth: 10,
    max_string_bytes: 1000,
    max_total_string_bytes: 1000,
  }).unwrap()
  assert_true(
    capture_input(owner, 0, [noncanonical], max_rows=1, limits) is Ok(_),
  )
}

///|
test "supplied budgets are cumulative and invalid input target is not a values index" {
  let owner = input_owner()
  let good = input_cursor("{\"n\":1,\"s\":\"é\"}")
  let limits = { max_nodes: 6, max_text_bytes: 8, max_depth: 2, max_work: 14, }
  assert_true(
    capture_input(owner, 0, [good, good], max_rows=2, limits) is Ok(_),
  )
  for
    cap in [
      { ..limits, max_nodes: 5, },
      { ..limits, max_text_bytes: 7, },
      { ..limits, max_work: 13, },
      { ..limits, max_depth: 1, },
    ] {
    assert_true(
      capture_input(owner, 0, [good, good], max_rows=2, cap) is Err(_),
    )
  }
  assert_true(
    capture_input(owner, 0, [good, good], max_rows=1, limits)
    is Err(CaptureLimit),
  )
  assert_true(
    capture_input(owner, 1, [], max_rows=0, limits) is Err(NotRelationInput),
  )
  assert_true(
    capture_input(capture_fixture(), 0, [], max_rows=0, limits)
    is Err(NotRelationInput),
  )
  assert_eq(
    captured_row_count(
      capture_input(owner, 0, [], max_rows=0, {
        max_nodes: 0,
        max_text_bytes: 0,
        max_depth: 0,
        max_work: 0,
      }).unwrap(),
    ),
    0,
  )
}

///|
test "supplied relation read retains exact input position and liveness" {
  let owner = input_owner()
  let rows = capture_input(
    owner,
    0,
    [input_cursor("{\"s\":\"ok\",\"n\":3}")],
    max_rows=1,
    { max_nodes: 100, max_text_bytes: 100, max_depth: 10, max_work: 200, },
  ).unwrap()
  let live = Ref(true)
  let read = prepare_supplied_relation_read(owner, 0, rows, fn() { live.val }).unwrap()
  assert_true(supplied_relation_read_available(read))
  assert_true(supplied_relation_read_matches_input(read, owner, 0))
  assert_true(supplied_relation_read_matches_operation_input(read, owner, 0, 0))
  assert_eq(supplied_relation_read_row_count(read), 1)
  assert_true(
    supplied_relation_read_checked_cell(read, 0, 0, {
      max_nodes: 10,
      max_depth: 10,
      max_text_bytes: 100,
    })
    is Some({ value: @admitted.Number(3.0), .. }),
  )
  let binding = supplied_relation_input_binding(read)
  assert_true(managed_input_binding_matches_input(binding, owner, 0))
  assert_true(managed_input_binding_matches_supplied_read(binding, read))
  let operation = managed_input_binding_for_operation(binding, owner, 0, 0).unwrap()
  assert_true(
    managed_input_binding_matches_operation_input(operation, owner, 0, 0),
  )
  assert_false(managed_input_binding_matches_input(operation, owner, 0))
  assert_true(managed_input_binding_for_operation(binding, owner, 0, 1) is None)
  assert_true(
    managed_input_binding_for_operation(binding, input_owner(), 0, 0) is None,
  )
  live.val = false
  assert_false(supplied_relation_read_available(read))
  assert_true(supplied_relation_read_cell(read, 0, 0) is None)
  assert_false(managed_input_binding_matches_input(binding, owner, 0))
}

///|
test "bounded selected rows retain supplied input provenance" {
  let owner = input_owner()
  let captured = capture_input(
    owner,
    0,
    [input_cursor("{\"s\":\"ok\",\"n\":3}")],
    max_rows=1,
    { max_nodes: 100, max_text_bytes: 100, max_depth: 10, max_work: 200, },
  ).unwrap()
  let live = Ref(true)
  let read = prepare_supplied_relation_read(owner, 0, captured, fn() {
    live.val
  }).unwrap()
  let sequence = prepared_sequence(owner)
  let node = @lower.node_at(@lower.bound_preparation(owner), 0).unwrap()
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    [@lower.node_id(node)],
    10000,
    1000,
  ).unwrap()
  let control = @bounded.control()
  let active = start_bounded_binding_rows_supplied(
    control,
    generated,
    read,
    1,
    { max_nodes: 100, max_text_bytes: 100, max_depth: 10, max_work: 200, },
    { max_nodes: 100, max_text_bytes: 100, max_depth: 10, max_work: 200, },
    1000,
    100,
    100,
    1000,
  ).unwrap()
  let mut complete = false
  for _ in 0..<1000 {
    if complete {
      break
    }
    match advance_bounded_binding_rows(active, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsComplete(output, ..) => {
        assert_eq(completed_row_count(output), 1)
        assert_true(completed_cell(output, 0, 0) is Some(Number(3.0)))
        assert_true(completed_cell(output, 0, 1) is Some(Text("ok")))
        complete = true
      }
      _ => fail("supplied bounded selection failed")
    }
  }
  assert_true(complete)
  assert_true(cleanup_bounded_binding_rows(active).unwrap())
  assert_true(supplied_relation_read_available(read))
  live.val = false
  assert_false(supplied_relation_read_available(read))
}

///|
test "bounded supplied projection admits exact work and workspace" {
  // One input-row opening, one output-row opening, and the two UTF-8 bytes
  // in the projected names give four work units. Two view entries, two
  // input and output names, two input and selected ordinals, and four row
  // slots give a fourteen-slot structural peak.
  let owner = input_owner()
  let captured = capture_input(
    owner,
    0,
    [input_cursor("{\"s\":\"ok\",\"n\":3}")],
    max_rows=1,
    { max_nodes: 100, max_text_bytes: 100, max_depth: 10, max_work: 200, },
  ).unwrap()
  let live = Ref(true)
  let read = prepare_supplied_relation_read(owner, 0, captured, fn() {
    live.val
  }).unwrap()
  let sequence = prepared_sequence(owner)
  let node = @lower.node_at(@lower.bound_preparation(owner), 0).unwrap()
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    [@lower.node_id(node)],
    10000,
    1000,
  ).unwrap()
  for (work, slots, succeeds) in [(4, 14, true), (3, 14, false), (4, 13, false)] {
    let started = start_bounded_binding_rows_supplied(
      @bounded.control(),
      generated,
      read,
      1,
      { max_nodes: 100, max_text_bytes: 100, max_depth: 10, max_work: 200, },
      { max_nodes: 100, max_text_bytes: 100, max_depth: 10, max_work: 200, },
      work,
      100,
      slots,
      1000,
    )
    let active = match started {
      Ok(active) => active
      Err(Rows(RowLimit)) => {
        assert_false(succeeds)
        continue
      }
      Err(_) => fail("supplied projection admission had another outcome")
    }
    let mut terminal = false
    for _ in 0..<1000 {
      if terminal {
        break
      }
      match advance_bounded_binding_rows(active, 1).unwrap() {
        BoundedBindingRowsContinue(..) => ()
        BoundedBindingRowsComplete(output, ..) => {
          assert_true(succeeds)
          assert_eq(completed_row_count(output), 1)
          terminal = true
        }
        BoundedBindingRowsFailed(Rows(RowLimit), ..) => {
          assert_false(succeeds)
          terminal = true
        }
        _ => fail("supplied projection resource boundary had another outcome")
      }
    }
    assert_true(terminal)
    assert_true(cleanup_bounded_binding_rows(active).unwrap())
    assert_true(supplied_relation_read_available(read))
  }
  live.val = false
  assert_false(supplied_relation_read_available(read))
}

///|
fn long_supplied_projection_fixture(
  output_text_bytes : Int,
  output_work? : Int = 6000,
  max_entries? : Int = 100,
) -> (@bounded.Control, BoundedBindingRowsExecution, SuppliedRelationRead) raise {
  let owner = input_owner()
  let text = Array::make(256, "aaaaaaaaaaaaaaaa").join("")
  let captured = capture_input(
    owner,
    0,
    [input_cursor("{\"s\":\"" + text + "\",\"n\":3}")],
    max_rows=1,
    { max_nodes: 10, max_text_bytes: 5000, max_depth: 10, max_work: 6000, },
  ).unwrap()
  let read = prepare_supplied_relation_read(owner, 0, captured, fn() { true }).unwrap()
  let sequence = prepared_sequence(owner)
  let node = @lower.node_at(@lower.bound_preparation(owner), 0).unwrap()
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    [@lower.node_id(node)],
    10000,
    1000,
  ).unwrap()
  let control = @bounded.control()
  let active = start_bounded_binding_rows_supplied(
    control,
    generated,
    read,
    1,
    { max_nodes: 10, max_text_bytes: 5000, max_depth: 10, max_work: 6000, },
    {
      max_nodes: 10,
      max_text_bytes: output_text_bytes,
      max_depth: 10,
      max_work: output_work,
    },
    10000,
    100,
    max_entries,
    10000,
  ).unwrap()
  (control, active, read)
}

///|
test "bounded supplied projection stops during admitted output retention" {
  let (control, active, read) = long_supplied_projection_fixture(4098)
  let mut measuring = false
  for _ in 0..<10000 {
    if !measuring {
      match advance_bounded_binding_rows(active, 1).unwrap() {
        BoundedBindingRowsContinue(..) => ()
        _ => fail("long projection ended before output retention")
      }
      measuring = active.state.phase is ChargeOutputRow &&
        active.state.output_charge_measure is Some(_)
    }
  }
  assert_true(measuring)
  assert_true(
    active.state.checked_row.any(value => value is ExactAdmittedOutputCell(_)),
  )
  guard active.state.output is Some(output) else {
    fail("unpublished projection output is missing")
  }
  assert_eq(output.buffer.rows.length(), 0)
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_binding_rows(active, 1).unwrap()
    is BoundedBindingRowsStopped(_, ..),
  )
  assert_true(cleanup_bounded_binding_rows(active).unwrap())
  assert_true(supplied_relation_read_available(read))
}

///|
fn nested_supplied_projection_fixture(
  count : Int,
  output_nodes : Int,
) -> (@bounded.Control, BoundedBindingRowsExecution, SuppliedRelationRead) raise {
  let seed_owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"items\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}},\"rows\":[{\"items\":[1]}]},\"as\":\"seed\"}]",
  )
  let seed = capture_values(seed_owner, 0, max_rows=1, {
    max_nodes: 20,
    max_text_bytes: 100,
    max_depth: 10,
    max_work: 100,
  }).unwrap()
  let pipeline = @pipeline.check(
    input_cursor("[{\"select\":[\"items\"]}]"),
    [("rows", captured_schema(seed))],
    None,
    Some(input_cursor("\"rows\"")),
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  let owner = @lower.bind_parameters(
    @lower.prepare(pipeline, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let limits : ValueLimits = {
    max_nodes: count + 10,
    max_text_bytes: 100,
    max_depth: 10,
    max_work: count + 100,
  }
  let captured = capture_input(
    owner,
    0,
    [input_cursor("{\"items\":[" + Array::make(count, "1").join(",") + "]}")],
    max_rows=1,
    limits,
  ).unwrap()
  let read = prepare_supplied_relation_read(owner, 0, captured, fn() { true }).unwrap()
  let sequence = prepared_sequence(owner)
  let node = @lower.node_at(@lower.bound_preparation(owner), 0).unwrap()
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    [@lower.node_id(node)],
    10000,
    1000,
  ).unwrap()
  let control = @bounded.control()
  let active = start_bounded_binding_rows_supplied(
    control,
    generated,
    read,
    1,
    limits,
    {
      max_nodes: output_nodes,
      max_text_bytes: 100,
      max_depth: 10,
      max_work: count + 100,
    },
    10000,
    100,
    100,
    1000,
  ).unwrap()
  (control, active, read)
}

///|
test "bounded supplied projection reuses exact nested admission" {
  let (control, active, read) = nested_supplied_projection_fixture(256, 300)
  let mut measuring = false
  for _ in 0..<1000 {
    if !measuring {
      match advance_bounded_binding_rows(active, 1).unwrap() {
        BoundedBindingRowsContinue(..) => ()
        _ => fail("nested projection ended before output measurement")
      }
      measuring = active.state.phase is ChargeOutputRow &&
        active.state.output_charge_measure is Some(_)
    }
  }
  assert_true(measuring)
  assert_true(
    active.state.checked_row.any(value => {
      value is ExactAdmittedOutputCell(@admitted.Array(_))
    }),
  )
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_binding_rows(active, 1).unwrap()
    is BoundedBindingRowsStopped(_, ..),
  )
  assert_true(cleanup_bounded_binding_rows(active).unwrap())
  assert_true(supplied_relation_read_available(read))
}

///|
test "bounded supplied nested projection charges exact output nodes" {
  // The output row, array and eight elements account for ten value nodes.
  for (nodes, succeeds) in [(10, true), (9, false)] {
    let (_, active, read) = nested_supplied_projection_fixture(8, nodes)
    let mut terminal = false
    for _ in 0..<200 {
      if !terminal {
        match advance_bounded_binding_rows(active, 1).unwrap() {
          BoundedBindingRowsContinue(..) => ()
          BoundedBindingRowsComplete(output, ..) => {
            assert_true(succeeds)
            assert_eq(completed_row_count(output), 1)
            terminal = true
          }
          BoundedBindingRowsFailed(Rows(RowLimit), ..)
          | BoundedBindingRowsFailed(Capture(CaptureLimit), ..) => {
            assert_false(succeeds)
            terminal = true
          }
          _ => fail("nested projection had another terminal outcome")
        }
      }
    }
    assert_true(terminal)
    assert_true(cleanup_bounded_binding_rows(active).unwrap())
    assert_true(supplied_relation_read_available(read))
  }
}

///|
test "bounded supplied projection charges exact admitted output text" {
  // One 4,096-byte value and two one-byte output field names are retained.
  for (text_bytes, succeeds) in [(4098, true), (4097, false)] {
    let (_, active, read) = long_supplied_projection_fixture(text_bytes)
    let mut terminal = false
    for _ in 0..<20000 {
      if !terminal {
        match advance_bounded_binding_rows(active, 1).unwrap() {
          BoundedBindingRowsContinue(..) => ()
          BoundedBindingRowsComplete(output, ..) => {
            assert_true(succeeds)
            assert_eq(completed_row_count(output), 1)
            terminal = true
          }
          BoundedBindingRowsFailed(Rows(RowLimit), ..)
          | BoundedBindingRowsFailed(Capture(CaptureLimit), ..) => {
            assert_false(succeeds)
            terminal = true
          }
          _ => fail("long projection ended with another outcome")
        }
      }
    }
    assert_true(terminal)
    assert_true(cleanup_bounded_binding_rows(active).unwrap())
    assert_true(supplied_relation_read_available(read))
  }
}

///|
test "bounded supplied projection admits exact work for copied long text" {
  // A row node, two one-byte names, two cell nodes and 4,096 value bytes.
  for (work, succeeds) in [(4101, true), (4100, false)] {
    let (_, active, read) = long_supplied_projection_fixture(
      4098,
      output_work=work,
    )
    let mut terminal = false
    for _ in 0..<20000 {
      if !terminal {
        match advance_bounded_binding_rows(active, 1).unwrap() {
          BoundedBindingRowsContinue(..) => ()
          BoundedBindingRowsComplete(_, ..) => {
            assert_true(succeeds)
            terminal = true
          }
          BoundedBindingRowsFailed(Rows(RowLimit), ..)
          | BoundedBindingRowsFailed(Capture(CaptureLimit), ..) => {
            assert_false(succeeds)
            terminal = true
          }
          _ => fail("long projection work boundary had another outcome")
        }
      }
    }
    assert_true(terminal)
    assert_true(cleanup_bounded_binding_rows(active).unwrap())
    assert_true(supplied_relation_read_available(read))
  }
}

///|
test "bounded supplied projection reserves long capture overlap" {
  for (slots, succeeds) in [(16, true), (15, false)] {
    let (_, active, read) = long_supplied_projection_fixture(
      4098,
      max_entries=slots,
    )
    let mut terminal = false
    for _ in 0..<20000 {
      if !terminal {
        match advance_bounded_binding_rows(active, 1).unwrap() {
          BoundedBindingRowsContinue(..) => ()
          BoundedBindingRowsComplete(_, ..) => {
            assert_true(succeeds)
            terminal = true
          }
          BoundedBindingRowsFailed(Rows(RowLimit), ..) => {
            assert_false(succeeds)
            terminal = true
          }
          _ => fail("long projection workspace had another outcome")
        }
      }
    }
    assert_true(terminal)
    assert_true(cleanup_bounded_binding_rows(active).unwrap())
    assert_true(supplied_relation_read_available(read))
  }
}

///|
test "supplied relation read rejects foreign owners and input positions" {
  let owner = input_owner()
  let rows = capture_input(owner, 0, [], max_rows=0, {
    max_nodes: 0,
    max_text_bytes: 0,
    max_depth: 0,
    max_work: 0,
  }).unwrap()
  assert_true(
    prepare_supplied_relation_read(owner, 1, rows, fn() { true })
    is Err(InvalidProjection),
  )
  assert_true(
    prepare_supplied_relation_read(input_owner(), 0, rows, fn() { true })
    is Err(ForeignReceiver),
  )
  assert_true(
    prepare_supplied_relation_read(owner, 0, rows, fn() { false })
    is Err(ProducerUnavailable),
  )
}
