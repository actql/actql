///|
// The measured interval belongs to this exact collector Array. It accounts
// for original admissions whose direct or outer policy constructor returned.
// Earlier disjoint intervals remain on the same collector.
priv enum KeyedDependencyMeasuredBodies {
  ReturnedKeyedDependencyRange(
    bodies~ : Array[@publication.CapturedEffectDependencyBody],
    start~ : Int,
    end~ : Int,
    bytes~ : Int64,
    previous~ : KeyedDependencyMeasuredBodies?
  )
}

///|
// Reuse work only between synchronous admissions that have returned. Capacity
// stays on the original lookup until the existing adopted-protocol settlement.
priv struct KeyedDependencySerialCursor {
  lookup : ClientKeyedLookupInput
  reservation : @resources.Reservation
  mut finished : Bool
  mut available_retained : Int64
  mut available_execution : Int64
  mut pending_retained : Int64
  mut pending_execution : Int64
  mut pending_depth : Int
  mut extent_workspace_depth : Int
  mut batch_start : Int
  mut measured : KeyedDependencyMeasuredBodies?
}

///|
// Only a sealed cursor can issue this proof. It borrows the same lookup and
// reservation through settlement, with no reference back to its cursor.
priv struct KeyedDependencySerialCompletion {
  lookup : ClientKeyedLookupInput
  reservation : @resources.Reservation
  last : KeyedDependencyMeasuredBodies
}

///|
fn keyed_dependency_cursor_reservation_live(
  lookup : ClientKeyedLookupInput,
) -> Bool {
  !lookup.closed &&
  lookup.left.lookup_issue is None &&
  lookup.holding is None &&
  @resources.reservation_open(lookup.reservation) &&
  !@resources.reservation_pending(lookup.reservation)
}

///|
fn validate_keyed_dependency_cursor_owner(
  lookup : ClientKeyedLookupInput,
  original : ClientKeyedLookupInput,
  reservation : @resources.Reservation,
) -> Result[Unit, ClientKeyedRequestIssue] {
  if !physical_equal(lookup, original) ||
    !physical_equal(lookup.reservation, reservation) {
    return Err(Assembly("foreign_dependency_cursor"))
  }
  if !keyed_dependency_cursor_reservation_live(lookup) {
    return Err(Assembly("retired_dependency_cursor"))
  }
  Ok(())
}

///|
fn KeyedDependencySerialCursor::validate(
  self : KeyedDependencySerialCursor,
  lookup : ClientKeyedLookupInput,
) -> Result[Unit, ClientKeyedRequestIssue] {
  match
    validate_keyed_dependency_cursor_owner(
      lookup,
      self.lookup,
      self.reservation,
    ) {
    Err(issue) => Err(issue)
    Ok(_) if self.finished => Err(Assembly("retired_dependency_cursor"))
    Ok(_) => Ok(())
  }
}

///|
fn KeyedDependencySerialCursor::retire(
  self : KeyedDependencySerialCursor,
) -> Unit {
  self.finished = true
}

///|
fn KeyedDependencySerialCursor::seal(
  self : KeyedDependencySerialCursor,
  lookup : ClientKeyedLookupInput,
) -> Result[KeyedDependencySerialCompletion?, ClientKeyedRequestIssue] {
  match self.validate(lookup) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if self.pending_retained >= 0L || self.batch_start >= 0 {
    return Err(Assembly("live_dependency_cursor"))
  }
  self.retire()
  match self.measured {
    Some(last) =>
      Ok(Some({ lookup: self.lookup, reservation: self.reservation, last, }))
    None => Ok(None)
  }
}

///|
priv struct KeyedDependencySerialFunding {
  before : ((Int, Int, Int) -> Bool)?
  begin_batch : (Int) -> Bool
  record : (Array[@publication.CapturedEffectDependencyBody]) -> Bool
}

///|
fn KeyedDependencySerialCursor::begin_batch(
  self : KeyedDependencySerialCursor,
  lookup : ClientKeyedLookupInput,
  start : Int,
) -> Result[Unit, ClientKeyedRequestIssue] {
  match self.validate(lookup) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if self.pending_retained >= 0L || self.batch_start >= 0 {
    return Err(Assembly("live_dependency_cursor"))
  }
  self.batch_start = start
  Ok(())
}

///|
fn KeyedDependencySerialCursor::record_body(
  self : KeyedDependencySerialCursor,
  lookup : ClientKeyedLookupInput,
  bodies : Array[@publication.CapturedEffectDependencyBody],
  max_nodes : Int,
) -> Result[Unit, ClientKeyedRequestIssue] {
  match self.validate(lookup) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let end = bodies.length()
  let first = if self.batch_start >= 0 { self.batch_start } else { end - 1 }
  if self.batch_start == end && self.pending_retained < 0L {
    self.batch_start = -1
    return Ok(())
  }
  guard self.pending_retained >= 0L && first >= 0 && first <= end else {
    return Err(Assembly("unavailable_dependency_body"))
  }
  let mut bytes = 0L
  for index in first..<end {
    let extent = match
      keyed_dependency_body_extent_cost(
        bodies[index],
        max_nodes,
        self.pending_depth,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    guard @execution.checked_preparation_add_product(bytes, extent, 1L)
      is Some(next) else {
      return Err(Assembly("capacity_overflow"))
    }
    bytes = next
  }
  guard @execution.checked_preparation_add_product(
      bytes,
      keyed_dependency_member_bytes,
      (end - first).to_int64(),
    )
    is Some(keep) else {
    return Err(Assembly("capacity_overflow"))
  }
  // The enclosing collector keeps its adopted bodies, original incoming
  // wire aliases and member controls. Only this returned constructor's
  // excess quote becomes reusable; no reservation is returned here.
  if keep > self.pending_retained {
    return Err(Assembly("dependency_body_extent_exceeds_quote"))
  }
  if first < end {
    let (start, preceding, previous) = match self.measured {
      None => (first, 0L, None)
      Some(
        ReturnedKeyedDependencyRange(
          bodies=original,
          start=low,
          end=high,
          bytes=prior,
          previous~
        )
      ) => {
        guard physical_equal(original, bodies) && high <= first else {
          return Err(Assembly("foreign_dependency_body_extent"))
        }
        if high == first {
          (low, prior, previous)
        } else {
          (first, 0L, self.measured)
        }
      }
    }
    guard @execution.checked_preparation_add_product(preceding, bytes, 1L)
      is Some(total) else {
      return Err(Assembly("capacity_overflow"))
    }
    self.measured = Some(
      ReturnedKeyedDependencyRange(
        bodies~,
        start~,
        end~,
        bytes=total,
        previous~,
      ),
    )
  }
  self.available_retained += self.pending_retained - keep
  self.available_execution += self.pending_execution - keep
  self.pending_retained = -1L
  self.pending_execution = 0L
  self.pending_depth = -1
  self.batch_start = -1
  Ok(())
}

///|
fn begin_keyed_dependency_serial_cursor(
  lookup : ClientKeyedLookupInput,
) -> Result[KeyedDependencySerialCursor, ClientKeyedRequestIssue] {
  if !keyed_dependency_cursor_reservation_live(lookup) {
    return Err(Assembly("retired_dependency_cursor"))
  }
  // One body and one range certificate, plus the old/new certificate overlap
  // while updating the serial state. The extent stack is funded separately.
  // Keep the batch hooks and the checked range carriers until settlement.
  // Five live range records plus one replacement each reserve a variant tag.
  // Include two cursor aliases and its latch, the sealed owner's three
  // references, and the overlapping reserve result, seal result and Some.
  guard @execution.preparation_representation_cost({
      record_headers: 47L,
      reference_slots: 75L,
      scalar_words: 75L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(controls) else {
    return Err(Assembly("capacity_overflow"))
  }
  match
    keyed_lookup_body_grow(
      lookup,
      lookup.retained_bytes,
      lookup.execution_bytes,
      controls,
      None,
    ) {
    Err(issue) => Err(issue)
    Ok(_) =>
      Ok({
        lookup,
        reservation: lookup.reservation,
        finished: false,
        available_retained: 0L,
        available_execution: 0L,
        pending_retained: -1L,
        pending_execution: 0L,
        pending_depth: -1,
        extent_workspace_depth: -1,
        batch_start: -1,
        measured: None,
      })
  }
}

///|
// The Request interval, two policy invocations and the Catalog suffix. The
// Generic suffix can be split by at most one separately borrowed retention
// body, because its one original identity is inserted at most once.
let keyed_dependency_measured_range_capacity : Int = 5

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
  if serial is Some(value) {
    match value.validate(lookup) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    if value.pending_retained >= 0L && value.batch_start < 0 {
      return Err(Assembly("live_dependency_cursor"))
    }
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
  // Within a policy call its producer, wire, parser and receiver can overlap.
  // Reserve each quote until the entire call has unwound.
  let (pending_r, pending_e) = match serial {
    Some(value) =>
      (Int64::max(0L, value.pending_retained), value.pending_execution)
    None => (0L, 0L)
  }
  guard @execution.checked_preparation_add_product(pending_r, retained, 1L)
    is Some(total_r) &&
    @execution.checked_preparation_add_product(pending_e, execution, 1L)
    is Some(total_e) else {
    return Err(Assembly("capacity_overflow"))
  }
  let grow_r = Int64::max(0L, retained - available_r)
  let needed_e = Int64::max(0L, execution - available_e)
  // ExecutionCapacity describes construction overlap, so its delta cannot
  // be smaller than retention. Any extra execution bytes remain available.
  let grow_e = Int64::max(grow_r, needed_e)
  guard @execution.execution_capacity(grow_r, grow_e) is Some(capacity) else {
    return Err(Assembly("capacity_overflow"))
  }
  // The same conservative traversal recipe as protocol completion, bounded
  // by this admission's proved node/depth bound. A smaller later body reuses
  // the funded stack. A deeper body grows it before any constructor runs.
  let stack_growth = match serial {
    Some(value) if depth > value.extent_workspace_depth => {
      let frames = 4L *
        (depth.to_int64() - value.extent_workspace_depth.to_int64()) +
        (if value.extent_workspace_depth < 0 { 20L } else { 0L })
      guard @execution.preparation_representation_cost({
          record_headers: frames,
          reference_slots: 4L * frames,
          scalar_words: 4L * frames,
          owned_utf16_units: 0L,
          owned_wire_bytes: 0L,
        })
        is Some(bytes) else {
        return Err(Assembly("capacity_overflow"))
      }
      bytes
    }
    _ => 0L
  }
  match
    keyed_lookup_body_grow(
      lookup,
      lookup.retained_bytes,
      lookup.execution_bytes,
      stack_growth,
      Some(capacity),
      check_unchanged=true,
    ) {
    Err(issue) => Err(issue)
    Ok(_) => {
      if serial is Some(value) {
        value.available_retained = Int64::max(0L, available_r - retained)
        value.available_execution = Int64::max(0L, available_e - execution) +
          (grow_e - needed_e)
        value.pending_retained = total_r
        value.pending_execution = total_e
        value.pending_depth = Int::max(value.pending_depth, depth)
        value.extent_workspace_depth = Int::max(
          value.extent_workspace_depth,
          depth,
        )
      }
      Ok(())
    }
  }
}
