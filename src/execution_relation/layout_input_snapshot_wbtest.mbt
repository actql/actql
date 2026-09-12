///|
// Benchmark-only pin of an admitted, physically imported input. Its original
// ledger owns the buffers until release; per-run ledgers reserve that same input
// capacity as an existing floor, not as additional globally allocated bytes.
priv struct LayoutInputSnapshot {
  table : LayoutRelation
  mut released : Bool
}

///|
fn retain_layout_input_snapshot(
  table : LayoutRelation,
  ledger : LayoutLedger,
) -> Result[LayoutInputSnapshot, LayoutStorageIssue] {
  let storage = table.storage
  if table.candidate == RowLayout ||
    storage.count < 0 ||
    storage.width != table.names.length() ||
    storage.selection is Some(_) ||
    storage.owned_selection is Some(_) {
    return Err(Shape)
  }
  guard storage.body is OwnedColumnArrays(columns) else { return Err(Shape) }
  if columns.length() != storage.width ||
    !spend_control(ledger.work, columns.length() + 1) {
    return Err(Limit)
  }
  let pinned = []
  for column in columns {
    match share_owned_layout_buffer(ledger, column) {
      Ok(handle) => pinned.push(handle)
      Err(issue) => {
        for handle in pinned {
          ignore(release_owned_layout_buffer(ledger, handle))
        }
        return Err(issue)
      }
    }
  }
  Ok({
    table: {
      ..table,
      names: table.names.copy(),
      storage: { ..storage, body: OwnedColumnArrays(pinned), },
    },
    released: false,
  })
}

///|
fn release_layout_input_snapshot(snapshot : LayoutInputSnapshot) -> Unit {
  if !snapshot.released {
    release_layout_columns(snapshot.table.storage)
    snapshot.released = true
  }
}

///|
// New invocation handles, same sealed buffers: no transposition or per-cell
// reconstruction. Charge the full retained capacity before exposing each handle.
// These counters are per-run capacity obligations, never summed with the pin's
// ledger to claim that shared memory was physically allocated twice.
fn attach_layout_input_snapshot(
  snapshot : LayoutInputSnapshot,
  ledger : LayoutLedger,
) -> Result[LayoutRelation, RowIssue] {
  if snapshot.released {
    return Err(InvalidRows)
  }
  guard snapshot.table.storage.body is OwnedColumnArrays(columns) else {
    return Err(InvalidRows)
  }
  if !spend_control(ledger.work, columns.length() + 1) {
    return Err(RowLimit)
  }
  let attached = []
  for column in columns {
    let allocated = match column.value {
      Some(value) if !column.lease.released =>
        allocate_owned_layout_buffer(
          ledger,
          column.lease.buffer.slots,
          column.lease.buffer.bytes,
          fn() { value },
        )
      _ => Err(Shape)
    }
    match allocated {
      Ok(handle) => attached.push(handle)
      Err(issue) => {
        for handle in attached {
          ignore(release_owned_layout_buffer(ledger, handle))
        }
        return Err(
          match issue {
            Limit => RowLimit
            Shape => InvalidRows
          },
        )
      }
    }
  }
  Ok({
    ..snapshot.table,
    storage: { ..snapshot.table.storage, body: OwnedColumnArrays(attached), },
  })
}

///|
test "prepared input pins share buffers across fresh budgets and isolate cleanup" {
  let (_, input) = numeric_layout_fixture(
    NarrowProjection,
    4,
    producer_seed=true,
  )
  for candidate in [ValueColumns, TypedColumns] {
    let source_ledger = layout_ledger(100000, 100000, 100000)
    let capture = retain_layout_capture(input, source_ledger).unwrap()
    let physical = {
      ..layout_allocation(100000, 100000, 100000),
      ledger: Some(source_ledger),
    }
    let imported = import_layout_capture_columns(capture, candidate, physical).unwrap()
    let snapshot = retain_layout_input_snapshot(imported, source_ledger).unwrap()
    release_layout_columns(imported.storage)
    let input_slots = if candidate == TypedColumns { 64 } else { 256 }
    let input_bytes = if candidate == TypedColumns { 2304 } else { 0 }
    for cap in [input_slots - 1, input_slots, input_slots] {
      let run_ledger = layout_ledger(cap, input_bytes, 100000)
      let attached = attach_layout_input_snapshot(snapshot, run_ledger)
      if cap < input_slots {
        assert_true(attached is Err(RowLimit))
      } else {
        let table = attached.unwrap()
        assert_eq(
          (run_ledger.slots.live, run_ledger.bytes.live),
          (input_slots, input_bytes),
        )
        assert_true(IndexedRows::read_cell(table, 0, 0) is Number(4))
        guard table.storage.body is OwnedColumnArrays(actual) else {
          fail("attached columns")
        }
        guard snapshot.table.storage.body is OwnedColumnArrays(original) else {
          fail("pinned columns")
        }
        for column in 0..<64 {
          match (actual[column].value, original[column].value) {
            (Some(Generic(a)), Some(Generic(b))) =>
              assert_true(physical_equal(a, b))
            (Some(Numeric(a, an)), Some(Numeric(b, bn))) => {
              assert_true(physical_equal(a, b))
              assert_true(physical_equal(an, bn))
            }
            _ => fail("buffer kind mismatch")
          }
        }
        release_layout_columns(table.storage)
      }
      assert_eq((run_ledger.slots.live, run_ledger.bytes.live), (0, 0))
      assert_true(IndexedRows::read_cell(snapshot.table, 0, 0) is Number(4))
    }
    release_layout_input_snapshot(snapshot)
    assert_true(
      attach_layout_input_snapshot(
        snapshot,
        layout_ledger(100000, 100000, 100000),
      )
      is Err(InvalidRows),
    )
    release_owned_layout_buffer(source_ledger, capture).unwrap()
    assert_eq((source_ledger.slots.live, source_ledger.bytes.live), (0, 0))
  }
}

///|
test "zero-column prepared pins have an explicit lifetime despite no column handles" {
  let (_, input) = numeric_layout_fixture(ZeroColumns, 4)
  let ledger = layout_ledger(100, 100, 1000)
  let capture = retain_layout_capture(input, ledger).unwrap()
  let imported = import_layout_capture_columns(capture, TypedColumns, {
    ..layout_allocation(100, 100, 1000),
    ledger: Some(ledger),
  }).unwrap()
  let snapshot = retain_layout_input_snapshot(imported, ledger).unwrap()
  release_layout_columns(imported.storage)
  let attached = attach_layout_input_snapshot(snapshot, layout_ledger(0, 0, 1)).unwrap()
  assert_eq(attached.storage.count, 4)
  assert_eq(attached.storage.width, 0)
  release_layout_input_snapshot(snapshot)
  assert_true(
    attach_layout_input_snapshot(snapshot, layout_ledger(0, 0, 1))
    is Err(InvalidRows),
  )
  release_owned_layout_buffer(ledger, capture).unwrap()
  assert_eq(ledger.slots.live, 0)
}

///|
test "prepared column inputs repeat the common driver with fresh admission budgets" {
  let count = 16
  for shape in [NarrowProjection, NullableProjection, ZeroColumns] {
    let (generated, input) = numeric_layout_fixture(shape, count)
    for candidate in [ValueColumns, TypedColumns] {
      let source_ledger = layout_ledger(1000000, 1000000, 1000000)
      let root = retain_layout_capture(input, source_ledger).unwrap()
      let imported = import_layout_capture_columns(root, candidate, {
        ..layout_allocation(1000000, 1000000, 1000000),
        ledger: Some(source_ledger),
      }).unwrap()
      let snapshot = retain_layout_input_snapshot(imported, source_ledger).unwrap()
      release_layout_columns(imported.storage)
      let successes = []
      // The failed first admission must neither import nor consume the pin.
      for admitted_rows in [count - 1, count, count] {
        let ledger = layout_ledger(1000000, 1000000, 1000000)
        let physical = {
          ..layout_allocation(1000000, 1000000, 1000000),
          ledger: Some(ledger),
        }
        let limits = {
          ..numeric_layout_limits(count),
          max_rows: admitted_rows,
        }
        let control = { remaining: 1000000, max_frames: 100, }
        let invocation = prepare_sequence_with_importers(
          generated.contracts,
          generated.sequence,
          [input],
          generated.retained_ids,
          limits,
          control,
          fn(captured) {
            if !physical_equal(captured, input) {
              return Err(InvalidRows)
            }
            attach_layout_input_snapshot(snapshot, ledger)
          },
          fn(_bound, _id, _output) { Err(InvalidRows) },
          release_table=fn(table : LayoutRelation) {
            release_layout_columns(table.storage)
          },
          produced=[],
          fragments=Some(generated.contexts),
          ordered={ contexts: [], max_bytes: 0, max_nodes: 0, max_depth: 0, },
        )
        if admitted_rows < count {
          assert_true(invocation is Err(InputLimit))
        } else {
          let invocation = invocation.unwrap()
          run_sequence_with_backend(
            invocation,
            fn(_captured) { Err(InvalidRows) },
            fn(kernel, table, logical) {
              evaluate_layout_kernel(
                kernel,
                table,
                count,
                control,
                invocation.output_budget,
                { limit: limits.operation_entries, live: 0, peak: 0, },
                physical,
                logical,
              )
            },
          ).unwrap()
          verify_numeric_layout_output(
            invocation.store.tables[invocation.store.tables.length() - 1].unwrap().table,
            shape,
            count,
          )
          successes.push(control.remaining)
          clear_table_store(invocation.store)
        }
        assert_eq((ledger.slots.live, ledger.bytes.live), (0, 0))
        assert_eq(IndexedRows::row_count(snapshot.table), count)
        if shape != ZeroColumns {
          assert_true(
            IndexedRows::read_cell(snapshot.table, 0, 0) is Number(16),
          )
        }
      }
      assert_eq(successes.length(), 2)
      assert_eq(successes[0], successes[1])
      release_layout_input_snapshot(snapshot)
      release_owned_layout_buffer(source_ledger, root).unwrap()
      assert_eq((source_ledger.slots.live, source_ledger.bytes.live), (0, 0))
    }
  }
}
