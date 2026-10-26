///|
/// Fixed owned control family of the ordinary Node structural scanner. Its
/// source-owned inventory is independently checked in the adapter suite; byte
/// pricing remains exclusively this Common tariff, not a Node-issued grant.
fn preparation_node_own_data_scan_cost() -> Int64? {
  @execution.preparation_representation_cost({
    record_headers: 4L,
    reference_slots: 5L,
    scalar_words: 31L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}

///|
/// Valid narrow input traversal count from the original header's F/R facts.
/// UTF16 lengths are inspected in O(1), not characters, in this Node phase.
/// JSON byte bounds and the later Common lexical scan have distinct units.
fn preparation_node_own_data_scan_work(fields : Int, rows : Int) -> Int? {
  if fields < 1 || rows < 0 {
    return None
  }
  let f = fields.to_int64()
  let r = rows.to_int64()
  let maximum = 2147483647L
  if f > (maximum - 140L) / (f + 19L) {
    return None
  }
  let base = 140L + f * f + 19L * f
  let per_row = 4L + 6L * f
  if r > (maximum - base) / per_row {
    return None
  }
  Some((base + r * per_row).to_int())
}

///|
/// A nominal input-bound header survives into the full scan: one record with
/// input identity/F/R facts and private state. It is additional to the scanner
/// owned control family, not hidden in its 344-byte component quote.
fn preparation_node_own_data_header_cost() -> Int64? {
  @execution.preparation_representation_cost({
    record_headers: 1L,
    reference_slots: 3L,
    scalar_words: 3L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}
