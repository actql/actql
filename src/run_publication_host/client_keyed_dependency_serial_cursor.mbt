///|
// The measured interval belongs to this exact collector Array. It accounts
// for only the direct admissions in the Request enumeration, not its
// surrounding policy/Catalog construction.
priv struct KeyedDependencyMeasuredBodies {
  bodies : Array[@publication.CapturedEffectDependencyBody]
  start : Int
  end : Int
  bytes : Int64
}

///|
// Reuse work only between synchronous admissions that have returned. Capacity
// stays on the original lookup until the existing adopted-protocol settlement.
priv struct KeyedDependencySerialCursor {
  mut available_retained : Int64
  mut available_execution : Int64
  mut pending_retained : Int64
  mut pending_execution : Int64
  mut measured : KeyedDependencyMeasuredBodies?
}

///|
fn new_keyed_dependency_serial_cursor() -> KeyedDependencySerialCursor {
  {
    available_retained: 0L,
    available_execution: 0L,
    pending_retained: -1L,
    pending_execution: 0L,
    measured: None,
  }
}

///|
fn KeyedDependencySerialCursor::record_body(
  self : KeyedDependencySerialCursor,
  bodies : Array[@publication.CapturedEffectDependencyBody],
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, ClientKeyedRequestIssue] {
  let end = bodies.length()
  guard self.pending_retained >= 0L && bodies.get(end - 1) is Some(body) else {
    return Err(Assembly("unavailable_dependency_body"))
  }
  let (start, previous) = match self.measured {
    None => (end - 1, 0L)
    Some(original) => {
      guard physical_equal(original.bodies, bodies) && original.end == end - 1 else {
        return Err(Assembly("foreign_dependency_body_extent"))
      }
      (original.start, original.bytes)
    }
  }
  let bytes = match
    keyed_dependency_body_extent_cost(body, max_nodes, max_depth) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard @execution.checked_preparation_add_product(previous, bytes, 1L)
    is Some(total) &&
    @execution.checked_preparation_add_product(
      bytes, keyed_dependency_member_bytes, 1L,
    )
    is Some(keep) else {
    return Err(Assembly("capacity_overflow"))
  }
  // The member allowance stays live through the last duplicate check. It
  // covers the new key, the Array/Map slots and transient growth backing;
  // the incoming wire comes from the still-live Request/page predecessor.
  // The measured body includes its admitted wire, even when a distinct
  // re-encoding replaced the input. No string equality proves a shared buffer.
  if keep > self.pending_retained {
    return Err(Assembly("dependency_body_extent_exceeds_quote"))
  }
  self.available_retained += self.pending_retained - keep
  self.available_execution += self.pending_execution - keep
  self.pending_retained = -1L
  self.pending_execution = 0L
  self.measured = Some({ bodies, start, end, bytes: total, })
  Ok(())
}

///|
fn reserve_keyed_dependency_serial_controls(
  lookup : ClientKeyedLookupInput,
  max_depth : Int,
) -> Result[Unit, ClientKeyedRequestIssue] {
  // The same bounded immutable extent walk used at protocol completion.
  // One body and one range certificate, plus the old/new certificate overlap
  // while updating the serial state. This funding is live throughout building.
  let frames = 4L * (max_depth.to_int64() + 1L) + 20L
  guard @execution.preparation_representation_cost({
      record_headers: 28L + frames,
      reference_slots: 44L + 4L * frames,
      scalar_words: 48L + 4L * frames,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(controls) else {
    return Err(Assembly("capacity_overflow"))
  }
  keyed_lookup_body_grow(
    lookup,
    lookup.retained_bytes,
    lookup.execution_bytes,
    controls,
    None,
  )
}

///|
let keyed_dependency_member_bytes : Int64 = 4096L

///|
fn grow_keyed_dependency_body(
  lookup : ClientKeyedLookupInput,
  bytes : Int,
  nodes : Int,
  depth : Int,
  serial : KeyedDependencySerialCursor?,
) -> Result[Unit, ClientKeyedRequestIssue] {
  if serial is Some(value) && value.pending_retained >= 0L {
    return Err(Assembly("live_dependency_cursor"))
  }
  guard @execution.execution_capacity_inventory_bytes([
      { unit: ValueNodeSlots, count: nodes.to_int64(), copies: 3, },
      { unit: DecodedTextBytes, count: bytes.to_int64(), copies: 3, },
      { unit: CanonicalWireBytes, count: bytes.to_int64(), copies: 4, },
      { unit: QuotedBytes, count: keyed_dependency_member_bytes, copies: 1, },
    ])
    is Some(retained) &&
    @execution.execution_capacity_inventory_add(
      retained,
      CursorRootSlots,
      depth.to_int64() + 1L,
      2,
    )
    is Some(execution) else {
    return Err(Assembly("capacity_overflow"))
  }
  let (available_r, available_e) = match serial {
    Some(value) => (value.available_retained, value.available_execution)
    None => (0L, 0L)
  }
  let grow_r = Int64::max(0L, retained - available_r)
  let needed_e = Int64::max(0L, execution - available_e)
  // ExecutionCapacity describes construction overlap, so its delta cannot
  // be smaller than retention. Any extra execution bytes remain available.
  let grow_e = Int64::max(grow_r, needed_e)
  guard @execution.execution_capacity(grow_r, grow_e) is Some(capacity) else {
    return Err(Assembly("capacity_overflow"))
  }
  match
    keyed_lookup_body_grow(
      lookup,
      lookup.retained_bytes,
      lookup.execution_bytes,
      0L,
      Some(capacity),
      check_unchanged=true,
    ) {
    Err(issue) => Err(issue)
    Ok(_) => {
      if serial is Some(value) {
        value.available_retained = Int64::max(0L, available_r - retained)
        value.available_execution = Int64::max(0L, available_e - execution) +
          (grow_e - needed_e)
        value.pending_retained = retained
        value.pending_execution = execution
      }
      Ok(())
    }
  }
}
