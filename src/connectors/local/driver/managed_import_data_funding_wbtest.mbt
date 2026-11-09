///|
fn managed_import_funding_limits() -> @local.LocalImportLimits {
  {
    max_rows: 100,
    values: {
      max_nodes: 1000,
      max_text_bytes: 2000,
      max_depth: 20,
      max_work: 10000,
    },
    wire: {
      max_columns: 20,
      max_order_work: 1000,
      max_bytes: 1024,
      max_nodes: 1000,
      max_depth: 20,
    },
    row: {
      max_bytes: 1024,
      max_nodes: 1000,
      max_depth: 20,
      max_text_bytes: 1024,
    },
    max_batch_bytes: 1024,
  }
}

///|
test "managed import starts with full parser scratch and grows only copied DATA" {
  let limits = managed_import_funding_limits()
  let full = @local.local_import_retention_capacity(limits).unwrap()
  let start = local_managed_import_start_bytes(limits).unwrap()
  assert_true(start > 0L && start < full)
  // Saturating every original copied-data dimension recovers exactly the old
  // full recipe. No wire/parser/control ceiling has been removed or lowered.
  let (rows, nodes, text, copied) = local_managed_import_next_extent(
    limits, 99L, 900L, 1900L, 1000L,
  ).unwrap()
  assert_eq((rows, nodes, text), (100L, 1000L, 2000L))
  assert_eq(start + copied, full)
  let saturated = local_managed_import_next_extent(
    limits, rows, nodes, text, 1000L,
  ).unwrap()
  assert_eq(saturated, (rows, nodes, text, copied))
}

///|
test "managed import copies retain separate cumulative wire bounds" {
  let limits = managed_import_funding_limits()
  let (rows, nodes, text, first) = local_managed_import_next_extent(
    limits, 0L, 0L, 0L, 40L,
  ).unwrap()
  let (_, _, _, second_row) = local_managed_import_next_extent(
    limits, rows, nodes, text, 40L,
  ).unwrap()
  let (_, _, _, other_copy) = local_managed_import_next_extent(
    limits, 0L, 0L, 0L, 40L,
  ).unwrap()
  assert_eq(first, other_copy)
  assert_eq(second_row, first + other_copy)
  assert_true(first > 0L)
  // Neither identical row bytes nor identical producer backing credits a copy.
  assert_true(first + other_copy > first)
}

///|
test "managed import geometry refuses invalid or regressing counters" {
  let limits = managed_import_funding_limits()
  assert_true(local_managed_import_next_extent(limits, -1L, 0L, 0L, 1L) is None)
  assert_true(
    local_managed_import_next_extent(limits, 0L, 1001L, 0L, 1L) is None,
  )
  assert_true(
    local_managed_import_next_extent(limits, 0L, 0L, 2001L, 1L) is None,
  )
  assert_true(local_managed_import_next_extent(limits, 0L, 0L, 0L, -1L) is None)
}
