///|
// Called only after the common receiving admission has verified the binding.
// Never forge a CapturedRows value from a successful producer's Table.
fn import_layout_producer(
  bound : BoundProducerInput,
  id : String,
  candidate : LayoutCandidate,
  limits : SequenceRunLimits,
  control : ControlBudget,
  output : ValueBudget,
  physical : LayoutAllocation,
) -> Result[LayoutRelation, RowIssue] {
  let source = test_row_output(bound.output)
  let producer = @lower.pipeline(
    @lower.bound_preparation(
      @lower.sequence_owner(bound.output.completion.sequence),
    ),
  )
  guard @pipeline.schema_at(producer, bound.output.target) is Some(schema) else {
    return Err(InvalidRows)
  }
  // The producer completion is a strong owner retained by the invocation;
  // converting or projecting does not release these source containers.
  if !reserve_slots(physical.slots, source.names.length()) ||
    !reserve_slots(physical.slots, source.rows.length()) {
    return Err(RowLimit)
  }
  for row in source.rows {
    if !reserve_slots(physical.slots, row.length()) ||
      !spend_control(physical.work, 1) {
      return Err(RowLimit)
    }
    if row.length() != source.names.length() {
      return Err(InvalidRows)
    }
  }
  let storage = if candidate == RowLayout {
    {
      body: RowArrays(source.rows),
      width: source.names.length(),
      count: source.rows.length(),
      selection: None,
      owned_selection: None,
    }
  } else {
    let builder = match
      layout_column_builder(
        schema,
        source.names,
        source.rows.length(),
        candidate,
        physical,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    for row in source.rows {
      match append_layout_row(builder, row) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
    }
    match finish_layout_columns(builder) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
  }
  let adopted : LayoutRelation = {
    candidate,
    owner: bound.receiver,
    id,
    names: source.names,
    storage,
  }
  match bound.projection {
    None => Ok(adopted)
    Some(projection) => {
      let result = evaluate_layout_source(
        CheckedProjection(projection),
        adopted,
        id,
        limits.max_rows,
        control,
        output,
        { limit: limits.operation_entries, live: 0, peak: 0, },
        physical,
        None,
      )
      release_layout_columns(adopted.storage)
      result
    }
  }
}

///|
test "producer projection releases conversion columns on success and failure" {
  let owner = row_owner("")
  let upstream = evaluate_sequence_components(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["values_0"],
    run_limits(),
    { remaining: 100000, max_frames: 100, },
  ).unwrap()
  let source = completed_output(upstream, Step(0)).unwrap()
  let receiver = projected_consumer(owner, "[\"a\"]", "[{\"select\":[\"a\"]}]")
  let bound = bind_completed_input(receiver, 0, owner, source).unwrap()
  for fail_projection in [false, true] {
    let ledger = layout_ledger(2, 36, 100)
    let physical = {
      ..layout_allocation(10000, 10000, 10000),
      ledger: Some(ledger),
    }
    let result = import_layout_producer(
      bound,
      "input_0",
      TypedColumns,
      run_limits(),
      { remaining: if fail_projection { 0 } else { 100000 }, max_frames: 100, },
      row_output(),
      physical,
    )
    if fail_projection {
      assert_true(result is Err(_))
    } else {
      let output = result.unwrap()
      assert_eq((ledger.slots.live, ledger.bytes.live), (1, 18))
      assert_true(layout_cell(output.storage, 0, 0) is Some(Number(1)))
      release_layout_columns(output.storage)
    }
    assert_eq((ledger.slots.live, ledger.bytes.live), (0, 0))
    assert_eq(ledger.bytes.peak, 36)
    assert_true(test_row_output(source).rows[0][0] is Number(1))
  }
}

///|
test "producer conversion accounts source coexistence and rejects receiver limits first" {
  let owner = row_owner("")
  let upstream = evaluate_sequence_components(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["values_0"],
    run_limits(),
    { remaining: 100000, max_frames: 100, },
  ).unwrap()
  let source = completed_output(upstream, Step(0)).unwrap()
  let receiver = projected_consumer(
    owner, "[{\"renamed\":\"b\"},\"a\"]", "[{\"select\":[\"renamed\",\"a\"]}]",
  )
  let bound = bind_completed_input(receiver, 0, owner, source).unwrap()
  // Source row containers: 8 slots; column builder metadata: 4; projection: 2.
  // Two number columns * two rows * (8 nominal bytes + 1 validity byte) = 36.
  // These are explicit element/container units, not allocator RSS estimates.
  for
    (slots, bytes, work, good) in [
      (14, 36, 12, true),
      (13, 36, 12, false),
      (14, 35, 12, false),
      (14, 36, 11, false),
    ] {
    let physical = layout_allocation(slots, bytes, work)
    let result = import_layout_producer(
      bound,
      "input_0",
      TypedColumns,
      run_limits(),
      { remaining: 100000, max_frames: 100, },
      row_output(),
      physical,
    )
    if good {
      assert_true(result is Ok(_))
      assert_eq(physical.slots.live, 14)
      assert_eq(physical.bytes.live, 36)
      assert_eq(physical.work.remaining, 0)
    } else {
      assert_true(result is Err(RowLimit))
    }
    assert_true(test_row_output(source).rows[0][0] is Number(1))
  }
  let calls : Array[Int] = []
  let limits = {
    ..run_limits(),
    input_values: {
      max_nodes: 5,
      max_text_bytes: 1000,
      max_depth: 10,
      max_work: 1000,
    },
  }
  let result = prepare_sequence_with_importers(
    registered_relation_contracts(),
    prepared_sequence(receiver),
    [],
    ["select_0"],
    limits,
    { remaining: 100000, max_frames: 100, },
    fn(_captured) { Err(InvalidRows) },
    fn(bound, id, output) {
      calls.push(1)
      import_layout_producer(
        bound,
        id,
        TypedColumns,
        limits,
        { remaining: 100000, max_frames: 100, },
        output,
        layout_allocation(100000, 100000, 100000),
      )
    },
    produced=[bound],
    fragments=Some([]),
    ordered={ contexts: [], max_bytes: 0, max_nodes: 0, max_depth: 0, },
  )
  assert_true(result is Err(InputLimit))
  assert_eq(calls, [])
}

///|
test "producer layout import uses the checked projection and keeps its success owner" {
  let owner = row_owner("")
  let upstream = evaluate_sequence_components(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["values_0"],
    run_limits(),
    { remaining: 100000, max_frames: 100, },
  ).unwrap()
  let source = completed_output(upstream, Step(0)).unwrap()
  let receiver = projected_consumer(
    owner, "[{\"renamed\":\"b\"},\"a\"]", "[{\"select\":[\"renamed\",\"a\"]}]",
  )
  let bound = bind_completed_input(receiver, 0, owner, source).unwrap()
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(receiver),
    [],
    ["input_0", "select_0"],
    100000,
    10000,
  ).unwrap()
  for candidate in [RowLayout, ValueColumns, TypedColumns] {
    for _repeat in 0..<2 {
      let control = { remaining: 100000, max_frames: 100, }
      let physical = layout_allocation(100000, 100000, 100000)
      let limits = run_limits()
      let invocation = prepare_sequence_with_importers(
        generated.contracts,
        generated.sequence,
        [],
        generated.retained_ids,
        limits,
        control,
        fn(_captured) { Err(InvalidRows) },
        fn(bound, id, output) {
          import_layout_producer(
            bound, id, candidate, limits, control, output, physical,
          )
        },
        produced=[bound],
        fragments=Some(generated.contexts),
        ordered={ contexts: [], max_bytes: 0, max_nodes: 0, max_depth: 0, },
      ).unwrap()
      assert_eq(invocation.input_rows, 2)
      assert_true(physical_equal(invocation.produced[0], bound))
      assert_true(physical.slots.live >= 8)
      run_sequence_with_backend(
        invocation,
        fn(_captured) { Err(InvalidRows) },
        fn(kernel, input, logical) {
          evaluate_layout_kernel(
            kernel,
            input,
            limits.max_rows,
            control,
            invocation.output_budget,
            { limit: limits.operation_entries, live: 0, peak: 0, },
            physical,
            logical,
          )
        },
      ).unwrap()
      for slot in [0, 1] {
        let table = invocation.store.tables[slot].unwrap().table
        assert_eq(table.names, ["renamed", "a"])
        assert_true(physical_equal(table.owner, receiver))
        assert_true(layout_cell(table.storage, 0, 0) is Some(Number(0)))
        assert_true(layout_cell(table.storage, 0, 1) is Some(Number(1)))
        assert_true(layout_cell(table.storage, 1, 0) is Some(Number(1)))
      }
      assert_eq(test_row_output(source).names, ["a", "b"])
      assert_true(test_row_output(source).rows[0][0] is Number(1))
      assert_true(physical_equal(test_row_output(source).owner, owner))
    }
  }
}
