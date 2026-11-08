///|
#cfg(target="js")
fn measured_text_payload_bytes(utf16_units : Int) -> Int64 {
  utf16_units.to_int64() * 2L
}

///|
#cfg(not(target="js"))
fn measured_text_payload_bytes(utf16_units : Int) -> Int64 {
  Int::max(1, utf16_units).to_int64() * 2L
}

///|
#cfg(target="js")
fn measured_text_payload_copies() -> Int {
  2
}

///|
#cfg(not(target="js"))
fn measured_text_payload_copies() -> Int {
  1
}

///|
// The sizing pass has already established both quantities. Wire bytes remain
// a logical/value guard, not a count of nodes or an allocated wire buffer.
fn measured_text_capacity(utf16_units : Int, wire_bytes : Int) -> Int64? {
  if utf16_units < 0 ||
    utf16_units > 1073741823 ||
    wire_bytes < 2 ||
    utf16_units > wire_bytes - 2 {
    return None
  }
  // The pinned builder's size_hint is bytes. Native allocates this exact
  // UInt16 buffer and transfers it at full length (one element when empty).
  // JS concatenation keeps old prefix + new prefix + current character:
  // together <=two complete measured payloads. to_string returns that same
  // retained String, so it adds no third copy. Fixed headers are already in
  // the original Text frame's structural reservation.
  execution_capacity_inventory_bytes([
    { unit: ValueNodeSlots, count: 1L, copies: 1, },
    {
      unit: DecodedTextBytes,
      count: measured_text_payload_bytes(utf16_units),
      copies: measured_text_payload_copies(),
    },
  ])
}

///|
// Immediate constructor boundary on the SAME measured root and Task. No new
// resource owner or reusable permission escapes. Fixed frame/builder controls
// remain in the Text function's original structural reservation.
fn reserve_measured_text_buffer(
  root : ExpressionRootLease,
  workspace : RowWorkspace,
  utf16_units : Int,
  wire_bytes : Int,
) -> Result[Unit, LogicalBudgetIssue] {
  let budget = root.scope.budget
  guard !budget.failed &&
    !root.root.released &&
    physical_equal(root.root.owner, budget) &&
    root.scope.slots.get(root.slot) is Some(Some(original)) &&
    physical_equal(original, root.root) &&
    root.root.text_capacity == Some(0L) &&
    root.root.measurement is None &&
    root.root.bytes == wire_bytes.to_int64() &&
    budget.growth is Some(growth) &&
    workspace.growth is Some(same) &&
    physical_equal(growth, same) else {
    budget.failed = true
    return Err(InvalidRootLifetime)
  }
  guard measured_text_capacity(utf16_units, wire_bytes) is Some(bytes) &&
    bytes <= 9223372036854775807L - growth.text else {
    budget.failed = true
    return Err(ValueMeasure(WireMeasureFailure))
  }
  if !grow_workspace(
      growth,
      growth.slots,
      growth.logical,
      text=Some(growth.text + bytes),
    ) {
    budget.failed = true
    return Err(LiveValueLimit)
  }
  // A synchronous current callback may have cancelled this original. Grown
  // capacity remains with the same Task for cleanup; no builder may follow.
  guard !root.root.released &&
    !budget.failed &&
    root.scope.slots.get(root.slot) is Some(Some(still)) &&
    physical_equal(still, root.root) else {
    growth.failed = true
    budget.failed = true
    // No payload constructor ran. Return only the uncreated live extent;
    // the already grown reservation/peak remains owned by Task cleanup.
    growth.text -= bytes
    return Err(InvalidRootLifetime)
  }
  root.root.text_capacity = Some(bytes)
  Ok(())
}
