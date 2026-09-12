///|
// The benchmark producer retains exactly one table. Count its row pointers and
// cell slots while converted columns coexist. Shared schema and nested Value
// object bytes are not represented by these nominal container-slot counters.
fn retain_layout_producer_output(
  output : CompletedOutput,
  ledger : LayoutLedger,
) -> Result[LayoutOwnedBuffer[CompletedOutput], LayoutStorageIssue] {
  for held in output.completion.store.tables {
    if held is Some(table) && !physical_equal(table.table, output.table) {
      return Err(Shape)
    }
  }
  let rows = output.table.rows
  let width = output.table.names.length()
  let available = ledger.slots.limit - ledger.slots.live
  if rows.length() > available {
    return Err(Limit)
  }
  let mut slots = rows.length()
  for row in rows {
    if row.length() != width {
      return Err(Shape)
    }
    if !spend_control(ledger.work, 1) || width > available - slots {
      return Err(Limit)
    }
    slots += width
  }
  allocate_owned_layout_buffer(ledger, slots, 0, fn() { output })
}

///|
test "producer source and destination must both fit and release independently" {
  let (_, bound) = layout_producer_case(4)
  // Four row pointers plus 4*64 cells; 64 typed destination buffers require one
  // nominal slot each, and four doubles plus validity bytes per column.
  for cap in [323, 324] {
    let ledger = layout_ledger(cap, 2304, 100000)
    let source = retain_layout_producer_output(bound.output, ledger).unwrap()
    assert_eq(ledger.slots.live, 260)
    let physical = {
      ..layout_allocation(100000, 100000, 100000),
      ledger: Some(ledger),
    }
    let result = import_layout_producer(
      bound,
      "input_0",
      TypedColumns,
      numeric_layout_limits(4),
      { remaining: 100000, max_frames: 100, },
      row_output(),
      physical,
    )
    if cap == 323 {
      assert_true(result is Err(RowLimit))
      assert_eq((ledger.slots.live, ledger.bytes.live), (260, 0))
    } else {
      let converted = result.unwrap()
      assert_eq((ledger.slots.live, ledger.bytes.live), (324, 2304))
      release_layout_columns(converted.storage)
      assert_eq((ledger.slots.live, ledger.bytes.live), (260, 0))
    }
    assert_true(source.value is Some(_))
    release_owned_layout_buffer(ledger, source).unwrap()
    assert_true(source.value is None)
    assert_eq((ledger.slots.live, ledger.bytes.live), (0, 0))
    assert_true(bound.output.table.rows[0][0] is Number(4))
  }
}
