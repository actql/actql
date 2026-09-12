///|
test "generated invocation imports owned captures without changing admission or result routing" {
  let owner = row_owner(",{\"select\":[\"a\"]}")
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["select_1"],
    100000,
    10000,
  ).unwrap()
  for candidate in [ValueColumns, TypedColumns] {
    let ledger = layout_ledger(12, 36, 100)
    let physical = {
      ..layout_allocation(10000, 10000, 10000),
      ledger: Some(ledger),
    }
    let roots : Array[LayoutOwnedBuffer[CapturedRows]] = []
    let import_rows = fn(captured) {
      let root = match retain_layout_capture(captured, ledger) {
        Ok(root) => root
        Err(_) => return Err(RowLimit)
      }
      roots.push(root)
      import_layout_capture_columns(root, candidate, physical)
    }
    let control = { remaining: 100000, max_frames: 100, }
    let invocation = prepare_sequence_with_importers(
      generated.contracts,
      generated.sequence,
      [],
      generated.retained_ids,
      run_limits(),
      control,
      import_rows,
      fn(_bound, _id, _output) { Err(InvalidRows) },
      release_table=fn(table : LayoutRelation) {
        release_layout_columns(table.storage)
      },
      produced=[],
      fragments=Some(generated.contexts),
      ordered={ contexts: [], max_bytes: 0, max_nodes: 0, max_depth: 0, },
    ).unwrap()
    run_sequence_with_backend(invocation, import_rows, fn(
      kernel,
      input,
      logical,
    ) {
      evaluate_layout_kernel(
        kernel,
        input,
        2,
        control,
        invocation.output_budget,
        { limit: 10000, live: 0, peak: 0, },
        physical,
        logical,
      )
    }).unwrap()
    assert_eq(roots.length(), 1)
    let output = invocation.store.tables[1].unwrap().table
    assert_true(layout_cell(output.storage, 0, 0) is Some(Number(1)))
    assert_true(layout_cell(output.storage, 1, 0) is Some(Number(0)))
    assert_eq(ledger.slots.peak, if candidate == TypedColumns { 8 } else { 10 })
    for root in roots {
      release_owned_layout_buffer(ledger, root).unwrap()
    }
    roots.clear()
    assert_eq(ledger.slots.live, if candidate == TypedColumns { 1 } else { 2 })
    assert_true(layout_cell(output.storage, 1, 0) is Some(Number(0)))
    clear_table_store(invocation.store)
    assert_eq((ledger.slots.live, ledger.bytes.live), (0, 0))
  }
}

///|
// Register already-admitted input containers before destination allocation.
// This is not admission of raw input, nor a measure of nested payload bytes.
// Count row-pointer and cell slots only. The checked schema is shared with the
// prepared owner and is not an independently releasable capture allocation.
// The invocation must keep this root until its last external capture reference
// is gone; converting the capture does not by itself authorize its release.
fn retain_layout_capture(
  input : CapturedRows,
  ledger : LayoutLedger,
) -> Result[LayoutOwnedBuffer[CapturedRows], LayoutStorageIssue] {
  let width = @schema.field_count(input.schema)
  let available = ledger.slots.limit - ledger.slots.live
  if input.rows.length() > available {
    return Err(Limit)
  }
  let mut slots = input.rows.length()
  for row in input.rows {
    if row.length() != width {
      return Err(Shape)
    }
    if !spend_control(ledger.work, 1) || width > available - slots {
      return Err(Limit)
    }
    slots += width
  }
  allocate_owned_layout_buffer(ledger, slots, 0, fn() { input })
}

///|
fn import_layout_capture_columns(
  source : LayoutOwnedBuffer[CapturedRows],
  candidate : LayoutCandidate,
  budget : LayoutAllocation,
) -> Result[LayoutRelation, RowIssue] {
  guard budget.ledger is Some(ledger) else { return Err(InvalidRows) }
  if !physical_equal(source.lease.buffer.ledger, ledger) ||
    source.lease.released {
    return Err(InvalidRows)
  }
  guard source.value is Some(input) else { return Err(InvalidRows) }
  if candidate == RowLayout {
    return Err(InvalidRows)
  }
  let prepared = @lower.bound_preparation(input.owner)
  let id = match input.origin {
    ValuesNode(i) =>
      match @lower.node_at(prepared, i) {
        Some(node) => @lower.node_id(node)
        None => return Err(InvalidRows)
      }
    SuppliedInput(i) =>
      match @lower.input_id(prepared, i) {
        Some(id) => id
        None => return Err(InvalidRows)
      }
  }
  let width = @schema.field_count(input.schema)
  if !reserve_slots(budget.slots, width) || !spend_control(budget.work, width) {
    return Err(RowLimit)
  }
  let names = Array::makei(width, i => {
    @schema.reference_name(@schema.field_at(input.schema, i).unwrap().name)
  })
  let builder = match
    layout_column_builder(
      input.schema,
      names,
      input.rows.length(),
      candidate,
      budget,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  for row in input.rows {
    // One row scratch only; no second retained row matrix.
    if !reserve_slots(budget.slots, width) || !spend_control(budget.work, width) {
      abort_layout_columns(builder)
      return Err(RowLimit)
    }
    match append_layout_row(builder, row.map(capture)) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  match finish_layout_columns(builder) {
    Ok(storage) => Ok({ candidate, owner: input.owner, id, names, storage, })
    Err(issue) => Err(issue)
  }
}

///|
test "capture owner remains charged during column conversion and can outlive output" {
  for candidate in [ValueColumns, TypedColumns] {
    let required = if candidate == TypedColumns { 8 } else { 10 }
    for limit in [required - 1, required] {
      let ledger = layout_ledger(limit, 36, 100)
      let source = retain_layout_capture(
        capture_values(row_owner(""), 0, max_rows=2, run_limits().input_values).unwrap(),
        ledger,
      ).unwrap()
      let budget = {
        ..layout_allocation(10000, 10000, 10000),
        ledger: Some(ledger),
      }
      assert_eq(ledger.slots.live, 6)
      let result = import_layout_capture_columns(source, candidate, budget)
      if limit < required {
        assert_true(result is Err(RowLimit))
        assert_eq((ledger.slots.live, ledger.bytes.live), (6, 0))
      } else {
        let output = result.unwrap()
        assert_eq(ledger.slots.live, required)
        assert_eq(ledger.slots.peak, required)
        assert_true(layout_cell(output.storage, 0, 0) is Some(Number(1)))
        release_layout_columns(output.storage)
        assert_eq((ledger.slots.live, ledger.bytes.live), (6, 0))
        // Output disposal must not dispose the invocation's source capture.
        assert_true(source.value is Some(_))
      }
      release_owned_layout_buffer(ledger, source).unwrap()
      assert_true(source.value is None)
      assert_eq(ledger.slots.live, 0)
      assert_true(
        import_layout_capture_columns(source, candidate, budget)
        is Err(InvalidRows),
      )
    }
  }
}
