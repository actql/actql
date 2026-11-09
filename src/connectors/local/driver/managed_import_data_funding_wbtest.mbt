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
test "managed import starts with empty buffers and funds each parser before decode" {
  let limits = managed_import_funding_limits()
  let full = @local.local_import_retention_capacity(limits).unwrap()
  let start = local_managed_import_start_bytes(limits).unwrap()
  assert_true(start > 0L && start < full)
  // Saturating every original copied-data dimension recovers exactly the old
  // full recipe. Parser/encoding limits themselves remain unchanged.
  let (rows, nodes, text, copied) = local_managed_import_next_extent(
    limits, 99L, 900L, 1900L, 1024L,
  ).unwrap()
  assert_eq((rows, nodes, text), (100L, 1000L, 2000L))
  assert_eq(start + copied, full)
  let saturated = local_managed_import_next_extent(
    limits, rows, nodes, text, 1024L,
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
  // A second row retains new copied DATA, while its parser scratch replaces
  // the previous row's scratch. A separate copy must fund both independently.
  assert_eq(second_row - first, 64L * (1L + 40L) + 8L * 40L)
  assert_true(second_row < first + other_copy)
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

///|
test "managed import parser extents follow each immutable row without refunding prior copies" {
  let limits = managed_import_funding_limits()
  let start = local_managed_import_start_bytes(limits).unwrap()
  // Only the schema-column view and positive empty row/batch envelope exist
  // before an input wire arrives; none of the parser arrays are constructed.
  assert_eq(start, 64L * limits.wire.max_columns.to_int64() + 16L)
  let (rows, nodes, text, first) = local_managed_import_next_extent(
    limits, 0L, 0L, 0L, 1000L,
  ).unwrap()
  let (next_rows, next_nodes, next_text, short) = local_managed_import_next_extent(
    limits, rows, nodes, text, 1L,
  ).unwrap()
  assert_eq((next_rows, next_nodes, next_text), (2L, 1000L, 1001L))
  assert_true(short < first)
  // The original fenced append uses max(previous, current). A shorter parse
  // never reduces the reservation or credits another equal producer copy.
  assert_eq(Int64::max(first, short), first)
  assert_true(
    start + first < @local.local_import_retention_capacity(limits).unwrap(),
  )
}
