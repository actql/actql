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
  assert_eq(capacity.retained_bytes, 3400L)
  assert_eq(capacity.execution_bytes, 3880L)
  let wider = native_capacity({
    ..limits,
    physical: { ..limits.physical, max_nodes: 2, },
  }).unwrap()
  assert_eq(wider.retained_bytes, 3912L)
  assert_eq(wider.execution_bytes, 3880L)
  assert_true(native_capacity({ ..limits, output_rows: -1, }) is None)
  assert_true(
    native_capacity({
      ..limits,
      transport: { ..limits.transport, max_bytes: -1, },
    })
    is None,
  )
}
