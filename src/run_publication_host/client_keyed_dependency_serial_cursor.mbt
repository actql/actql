///|
// Reuse only the explicit cursor-root execution allowance between direct
// synchronous admissions in the same Request enumeration. The retained lane
// and mixed body, text, member and collection allowances are still additive.
// An emit, policy receiver or Catalog call can hold other constructor frames.
priv struct KeyedDependencySerialCursor {
  mut reusable : Int64
  // -1 outside an admitted parser call; zero can be a live call.
  mut pending : Int64
}

///|
fn KeyedDependencySerialCursor::retire(
  self : KeyedDependencySerialCursor,
) -> Unit {
  if self.pending >= 0L {
    self.reusable += self.pending
    self.pending = -1L
  }
}

///|
fn reserve_keyed_dependency_serial_controls(
  lookup : ClientKeyedLookupInput,
) -> Result[Unit, ClientKeyedRequestIssue] {
  // Scalar cursor state, option/tuple, callback closures, and the additional
  // Result/quote carriers. This frame ends before protocol settlement.
  let controls = @execution.preparation_representation_cost({
    record_headers: 12L,
    reference_slots: 20L,
    scalar_words: 12L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
  keyed_lookup_body_grow(
    lookup,
    lookup.retained_bytes,
    lookup.execution_bytes,
    controls,
    None,
  )
}

///|
fn grow_keyed_dependency_body(
  lookup : ClientKeyedLookupInput,
  bytes : Int,
  nodes : Int,
  depth : Int,
  serial : KeyedDependencySerialCursor?,
) -> Result[Unit, ClientKeyedRequestIssue] {
  if serial is Some(value) && value.pending >= 0L {
    return Err(Assembly("live_dependency_cursor"))
  }
  guard @execution.execution_capacity_inventory_bytes([
      { unit: ValueNodeSlots, count: nodes.to_int64(), copies: 3, },
      { unit: DecodedTextBytes, count: bytes.to_int64(), copies: 3, },
      { unit: CanonicalWireBytes, count: bytes.to_int64(), copies: 4, },
      { unit: QuotedBytes, count: 4096L, copies: 1, },
    ])
    is Some(retained) &&
    @execution.execution_capacity_inventory_add(
      0L,
      CursorRootSlots,
      depth.to_int64() + 1L,
      2,
    )
    is Some(cursor) else {
    return Err(Assembly("capacity_overflow"))
  }
  let reusable = match serial {
    Some(value) => value.reusable
    None => 0L
  }
  let extra = Int64::max(0L, cursor - reusable)
  guard @execution.checked_preparation_add_product(retained, extra, 1L)
    is Some(execution) &&
    @execution.execution_capacity(retained, execution) is Some(capacity) else {
    return Err(Assembly("capacity_overflow"))
  }
  match
    keyed_lookup_body_grow(
      lookup,
      lookup.retained_bytes,
      lookup.execution_bytes,
      0L,
      Some(capacity),
    ) {
    Err(issue) => Err(issue)
    Ok(_) => {
      if serial is Some(value) {
        value.pending = extra
      }
      Ok(())
    }
  }
}
