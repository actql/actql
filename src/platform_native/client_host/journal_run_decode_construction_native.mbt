///|
// Native raw allocations remain target-specific. The Run/request/Definition
// logical constructor recipe has one shared owner for Native and Wasm reads.
fn journal_run_decode_working(
  stage : @host.ClientRunJournalConstruction,
) -> (Int64, Int64, Int64)? {
  guard @host.client_run_journal_decode_construction(stage)
    is Some((retained, execution)) else {
    return None
  }
  let (bytes, parsing) = match stage {
    @host.RunJournalParse(bytes) => (bytes, true)
    @host.RunJournalCanonical(bytes, _, _, _)
    | @host.RunJournalRetained(bytes, _, _, _) => (bytes, false)
  }
  let (header, unit, terminator, array_header, pointer) = @bootstrap.native_managed_value_layout()
  if header <= 0L || unit != 2L || terminator != unit || pointer < 4L {
    return None
  }
  // Pinned UTF16 builder doubling; normalization's largest text is <=4U.
  // Canonical decomposition uses <=4U scalars, each <=pointer bytes. Its
  // Array old/new growth bound12+3N also bounds any single allocation.
  let normalized_units = if parsing { 0L } else { 4L * 65536L }
  let max_text = Int64::max(bytes.to_int64(), normalized_units)
  let mut capacity = 1L
  while capacity < max_text {
    capacity *= 2L
  }
  let scalar_items = if parsing { 0L } else { 12L + 3L * 4L * 65536L }
  // The full Map bucket/backing bound18+11N covers a single allocation too;
  // these are actual pointer slots, not an R/E quantity recast as raw bytes.
  let map_items = 18L + 11L * (if parsing { 32L } else { 4096L })
  let raw = Int64::max(
    header + (capacity + 1L) * unit,
    array_header + Int64::max(scalar_items, map_items) * pointer,
  )
  Some((retained, execution, raw))
}
