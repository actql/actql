///|
test "native declared capacity includes both batches and every retained evidence document" {
  let limits : NativeHostLimits = {
    physical: { max_rows: 1, max_cells: 1, max_nodes: 1, max_text_bytes: 1, },
    metadata_work: 1,
    measurement: { max_work: 1, max_bytes: 1, max_nodes: 1, max_depth: 1, },
    completion: {
      demand: { max_work: 1, max_bytes: 1, max_nodes: 1, max_depth: 1, },
      receipts: {
        max_columns: 1,
        max_order_work: 1,
        max_bytes: 1,
        max_nodes: 1,
        max_depth: 1,
      },
      max_received_rows: 1,
      max_received_bytes: 1,
      max_retained_wire_bytes: 1,
      records: {
        max_work: 1,
        max_fields: 1,
        max_parameters: 1,
        max_bytes: 1,
        max_nodes: 1,
        max_depth: 1,
      },
      capture: { max_bytes: 1, max_nodes: 1, max_depth: 1, },
    },
    retention: { max_nodes: 1, max_text_bytes: 1, max_depth: 1, max_work: 1, },
    output_rows: 1,
    output_entries: 1,
    output_name_bytes: 1,
    transport: {
      max_bytes: 1,
      max_nodes: 1,
      max_columns: 1,
      max_rows: 1,
      max_text_bytes: 1,
    },
  }
  let capacity = native_capacity(limits).unwrap()
  // Thirteen retained structural allowances and nine text/wire allowances;
  // fifteen temporary structural allowances and five temporary text allowances.
  // Both also cover the same retained identity's H2/R2/W5=88 metadata bytes.
  assert_eq(capacity.retained_bytes, 3488L)
  assert_eq(capacity.execution_bytes, 3968L)
  let wider = native_capacity({
    ..limits,
    physical: { ..limits.physical, max_nodes: 2, },
  }).unwrap()
  assert_eq(wider.retained_bytes, 4000L)
  assert_eq(wider.execution_bytes, 3968L)
  let stream = retained_native_capacity(limits).unwrap()
  assert_eq(stream.retained_bytes, 2432L)
  assert_eq(stream.execution_bytes, 5024L)
  let stream_wider = retained_native_capacity({
    ..limits,
    physical: { ..limits.physical, max_nodes: 1000000, max_rows: 1000000, },
    retention: { ..limits.retention, max_nodes: 1000000, },
    output_rows: 1000000,
  }).unwrap()
  assert_eq(stream_wider.retained_bytes, stream.retained_bytes)
  assert_eq(stream_wider.execution_bytes, 5320L)
  let still_wider = retained_native_capacity({
    ..limits,
    physical: { ..limits.physical, max_nodes: 2000000, max_rows: 2000000, },
    retention: { ..limits.retention, max_nodes: 2000000, },
    output_rows: 2000000,
  }).unwrap()
  assert_eq(still_wider.execution_bytes, stream_wider.execution_bytes)
  let larger_batch = retained_native_capacity({
    ..limits,
    transport: { ..limits.transport, max_nodes: 2, max_bytes: 2, },
  }).unwrap()
  assert_eq(larger_batch.execution_bytes, stream.execution_bytes + 264L)
  // The exact capture Owner must fund the new metadata before handoff.
  // Neither quote DATA nor a one-short parent can create capacity.
  for selected in [capacity, stream] {
    for short in 0..<2 {
      let ledger = @resources.create_ledger({
        planning_work: 1,
        attempts: 1,
        holdings: 1,
        transfer_bytes: 1L,
        retained_bytes: selected.retained_bytes -
        (if short == 0 { 1L } else { 0L }),
        execution_bytes: selected.execution_bytes -
        (if short == 1 { 1L } else { 0L }),
      }).unwrap()
      let refused = @resources.reserve_capacity(
        ledger,
        selected.retained_bytes,
        selected.execution_bytes,
      )
      if short == 0 {
        assert_true(refused is Err(RetentionLimit))
      } else {
        assert_true(refused is Err(ExecutionLimit))
      }
      let usage = @resources.ledger_usage(ledger)
      assert_eq(usage.reserved_retention_bytes, 0L)
      assert_eq(usage.reserved_execution_bytes, 0L)
    }
    let ledger = @resources.create_ledger({
      planning_work: 1,
      attempts: 1,
      holdings: 1,
      transfer_bytes: 1L,
      retained_bytes: selected.retained_bytes,
      execution_bytes: selected.execution_bytes,
    }).unwrap()
    let held = @resources.reserve_capacity(
      ledger,
      selected.retained_bytes,
      selected.execution_bytes,
    ).unwrap()
    assert_true(
      @resources.capacity_reservation_matches(
        ledger,
        held,
        selected.retained_bytes,
        selected.execution_bytes,
      ),
    )
    @resources.settle_capacity(ledger, held).unwrap()
    let usage = @resources.ledger_usage(ledger)
    assert_eq(usage.reserved_retention_bytes, 0L)
    assert_eq(usage.reserved_execution_bytes, 0L)
  }
  let more_metadata = retained_native_capacity({
    ..limits,
    transport: { ..limits.transport, max_columns: 2, },
  }).unwrap()
  assert_eq(more_metadata.retained_bytes, stream.retained_bytes + 1024L)
  assert_true(retained_native_capacity({ ..limits, output_rows: -1, }) is None)
  assert_true(native_capacity({ ..limits, output_rows: -1, }) is None)
  assert_true(
    native_capacity({
      ..limits,
      transport: { ..limits.transport, max_bytes: -1, },
    })
    is None,
  )
}
