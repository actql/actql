///|
test "materializing transport starts independently of unallocated future wire storage" {
  let imports : LocalImportLimits = {
    max_rows: 100,
    values: {
      max_work: 10000,
      max_nodes: 1000,
      max_text_bytes: 10000,
      max_depth: 8,
    },
    wire: {
      max_columns: 8,
      max_order_work: 10000,
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 8,
    },
    row: {
      max_bytes: 1000,
      max_nodes: 1000,
      max_depth: 8,
      max_text_bytes: 1000,
    },
    max_batch_bytes: 1000,
  }
  let larger : LocalImportLimits = {
    max_rows: 100000,
    values: { ..imports.values, max_nodes: 100000, max_text_bytes: 1000000, },
    wire: { ..imports.wire, max_bytes: 1000000, max_nodes: 100000, },
    row: {
      ..imports.row,
      max_bytes: 1000000,
      max_nodes: 100000,
      max_text_bytes: 1000000,
    },
    max_batch_bytes: 1000000,
  }
  assert_eq(
    local_materializing_import_start_capacity(imports),
    local_materializing_import_start_capacity(larger),
  )
  assert_true(
    local_import_retention_capacity(imports).unwrap() <
    local_import_retention_capacity(larger).unwrap(),
  )
  let first = local_import_next_retention_extent(larger, 0L, 0L, 0L, 13L).unwrap()
  let second = local_import_next_retention_extent(
    larger,
    first.0,
    first.1,
    first.2,
    13L,
  ).unwrap()
  assert_eq((first.0, first.1, first.2), (1L, 13L, 13L))
  // One additional row header, one admitted-value node per wire byte and
  // retained text; independent parser/frame peak is reused, not summed.
  assert_eq(second.3 - first.3, 64L * 14L + 8L * 13L)
  assert_true(
    local_import_next_retention_extent(larger, -1L, 0L, 0L, 13L) is None,
  )
  assert_true(
    local_materializing_import_start_capacity({
      ..larger,
      wire: { ..larger.wire, max_columns: -1, },
    })
    is None,
  )
  let exported : LocalExportLimits = {
    max_rows: imports.max_rows,
    values: imports.values,
    wire: imports.wire,
    max_batch_bytes: 1000,
  }
  let wider : LocalExportLimits = {
    ..exported,
    wire: { ..exported.wire, max_bytes: 1000000, },
    max_batch_bytes: 1000000,
  }
  assert_eq(
    local_materializing_export_start_capacity(exported),
    local_materializing_export_start_capacity(wider),
  )
  assert_eq(
    local_export_retention_capacity(wider).unwrap() -
    local_export_retention_capacity(exported).unwrap(),
    990000L + 8L * 999000L,
  )
  // Authority/reference roots are real backing even before file emission.
  assert_eq(
    local_materializing_export_start_capacity({
      ..exported,
      values: { ..exported.values, max_nodes: exported.values.max_nodes + 1, },
    }).unwrap() -
    local_materializing_export_start_capacity(exported).unwrap(),
    128L,
  )
  assert_true(
    local_materializing_export_start_capacity({
      ..exported,
      wire: { ..exported.wire, max_nodes: 0, },
    })
    is None,
  )
}
