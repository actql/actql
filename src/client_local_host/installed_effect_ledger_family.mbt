///|
// Closed existing frontier/intents constructors, not Receipt construction or a
// full-history quote. Frozen Host collection lengths are quantity DATA, never
// proof of Preview membership, a durable head or current authorization.
fn installed_effect_ledger_family_workspace(
  counts : Array[Int],
  max_entries : Int,
  max_entry_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Int64? {
  if counts.length() < 1 ||
    counts.length() > 1000 ||
    max_entries < 1 ||
    max_entries > 100000 ||
    max_entry_bytes < 1 ||
    max_entry_bytes > 1000000 ||
    max_nodes < 1 ||
    max_nodes > 64 ||
    max_depth < 1 ||
    max_depth > 4 {
    return None
  }
  let mut rows = 0
  for count in counts {
    if count < 0 || count > max_entries - rows {
      return None
    }
    rows += count
  }
  let m = counts.length().to_int64()
  let n = rows.to_int64()
  // Frontier: six outer and six per-member vectors, locator vector/Set,
  // requested physical snapshot, Core effect/policy/member/progress/ready
  // vectors and one-row slice admission. Intents additionally holds flat
  // claims/locators/operations and one entry vector per prepared append.
  // Price their union (including growth) rather than relying on head absence.
  guard @shape.collection_construction_extent({
      records: 16L + 8L * m + 16L * n,
      record_references: 48L + 16L * m + 48L * n,
      record_words: 24L + 8L * m + 24L * n,
      reference_arrays: 16L + 8L * m + 4L * n,
      reference_items: 12L * m + 24L * n,
      scalar_arrays: 2L,
      scalar_items: m + n,
      maps: 2L,
      map_entries: m + n,
    })
    is Some(collections) else {
    return None
  }
  // Requested currentSnapshot rows retain their complete entryJson Strings
  // while nested admit normalizes one of them. A prepared append can also
  // hold one new entry wire per row. Bound both, plus native CID/digest text
  // and the existing physical digest's UTF8 conversion. No historical row
  // count, native heap/page estimate or Receipt/data-key workspace is implied.
  let bytes = max_entry_bytes.to_int64()
  guard @execution.preparation_representation_cost({
      record_headers: collections.record_headers,
      reference_slots: collections.reference_slots,
      scalar_words: collections.scalar_words,
      owned_utf16_units: n * (2L * bytes + 8L * 71L + 64L),
      owned_wire_bytes: bytes,
    })
    is Some(body) &&
    installed_effect_operation_control_capacity(0) is Some(overhead) &&
    @execution.checked_preparation_add_product(
      body,
      @execution.execution_capacity_execution_bytes(overhead) -
      @execution.execution_capacity_retained_bytes(overhead),
      1L,
    )
    is Some(workspace) else {
    return None
  }
  Some(workspace)
}
