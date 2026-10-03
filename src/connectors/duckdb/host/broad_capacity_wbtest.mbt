///|
test "Broad capacity retains scan, residual and evidence and rejects overflow" {
  let l : BroadHostLimits = {
    physical: { max_rows: 1, max_cells: 1, max_nodes: 1, max_text_bytes: 1, },
    metadata_work: 1,
    retention: { max_nodes: 1, max_text_bytes: 1, max_depth: 1, max_work: 1, },
    transport: {
      max_bytes: 1,
      max_nodes: 1,
      max_columns: 1,
      max_rows: 1,
      max_text_bytes: 1,
    },
    completion: {
      execution: {
        rows: {
          max_rows: 1,
          metadata_entries: 1,
          retained_entries: 1,
          operation_entries: 1,
          input_values: {
            max_nodes: 1,
            max_text_bytes: 1,
            max_depth: 1,
            max_work: 1,
          },
          output_values: {
            max_nodes: 1,
            max_text_bytes: 1,
            max_depth: 1,
            max_work: 1,
          },
        },
        max_work: 1,
        max_frames: 1,
      },
      guards: { max_work: 1, max_bytes: 1, max_nodes: 1, max_depth: 1, },
      retention: {
        received_wire_bytes: 1,
        retained_wire_bytes: 1,
        measurement: {
          max_columns: 1,
          max_order_work: 1,
          max_bytes: 1,
          max_nodes: 1,
          max_depth: 1,
        },
      },
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
  }
  let residual = @execution.execution_capacity(512L, 1024L).unwrap()
  let capacity = broad_capacity(l, residual).unwrap()
  // Independently enumerated: 11 retained structural allowances and 7 text
  // allowances, plus 13 scratch structural and 4 scratch text allowances.
  assert_eq(capacity.retained_bytes, 3384L)
  assert_eq(capacity.execution_bytes, 4384L)
  let wider_scan = broad_capacity(
    { ..l, physical: { ..l.physical, max_nodes: 2, }, },
    residual,
  ).unwrap()
  assert_eq(wider_scan.retained_bytes, 3640L)
  assert_eq(wider_scan.execution_bytes, 4384L)
  let wider_residual = broad_capacity(
    l,
    @execution.execution_capacity(1024L, 2048L).unwrap(),
  ).unwrap()
  assert_eq(wider_residual.retained_bytes, 3896L)
  assert_eq(wider_residual.execution_bytes, 5408L)
  assert_true(
    broad_capacity(
      { ..l, transport: { ..l.transport, max_columns: -1, }, },
      residual,
    )
    is None,
  )
  assert_true(
    broad_capacity(
      l,
      @execution.execution_capacity(9223372036854775807L, 9223372036854775807L).unwrap(),
    )
    is None,
  )
}
