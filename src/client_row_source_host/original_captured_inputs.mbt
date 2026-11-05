///|
// Capability-free borrowed identity retained by the existing prefix. In
// particular cleanup keeps the exact tokens after Row clears its live holding.
// This object neither owns cleanup nor issues completion, resources or reads.
struct RowCapturedInputs {
  ledger : @resources.Ledger
  captures : Array[RowSourceCapture]
  originals : Array[(@resources.Reservation, @resources.Holding)]
}

///|
pub fn row_captured_inputs_construction_inventory(
  count : Int,
) -> @execution.PreparationRepresentationUnits? {
  if count < 1 {
    return None
  }
  guard @shape.reference_array_retained_extent(2L, 2L * count.to_int64())
    is Some(arrays) else {
    return None
  }
  Some({
    record_headers: 1L + count.to_int64() + arrays.record_headers,
    reference_slots: 3L + 2L * count.to_int64() + arrays.reference_slots,
    scalar_words: arrays.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}

///|
// The caller funds the inventory before entry. Snapshot every original before
// callbacks, then check all current pairs and the census after all callbacks.
pub fn retain_row_captured_inputs(
  captures : Array[RowSourceCapture],
  ledger : @resources.Ledger,
  max_work : Int,
) -> RowCapturedInputs? {
  if captures.is_empty() || max_work < 0 || captures.length() > max_work / 2 {
    return None
  }
  let captures = captures.copy()
  for capture in captures {
    guard capture.run.configuration is DirectConfiguration(_) &&
      !capture.run.closed &&
      capture.run.physical is Some(physical) &&
      physical_equal(physical.ledger, ledger) &&
      physical.dag is None &&
      physical.holding is Some(_) else {
      return None
    }
  }
  let originals = Array::makei(captures.length(), index => {
    let physical = captures[index].run.physical.unwrap()
    (physical.reservation, physical.holding.unwrap())
  })
  let value = RowCapturedInputs::{ ledger, captures, originals, }
  guard row_captured_inputs_current(value) &&
    @resources.original_captured_inputs_prefix_available(ledger, originals) else {
    return None
  }
  Some(value)
}

///|
fn row_captured_inputs_current(value : RowCapturedInputs) -> Bool {
  for capture in value.captures {
    guard capture.run.configuration is DirectConfiguration(configuration) &&
      row_capture_source(capture) is Ok(source) &&
      @query.captured_source_matches_query(
        source,
        @planning.query_material_owner(
          @planning.query_requirement_material(configuration.requirement),
        ),
      ) else {
      return false
    }
  }
  // No liveness callback is allowed after this fence and before the caller's
  // resource census. Reentrant close of an EARLIER capture is checked too.
  for index, capture in value.captures {
    let (reservation, original_holding) = value.originals[index]
    guard !capture.run.closed &&
      capture.run.physical is Some(physical) &&
      physical_equal(physical.ledger, value.ledger) &&
      physical.dag is None &&
      physical_equal(physical.reservation, reservation) &&
      physical.holding is Some(holding) &&
      physical_equal(holding, original_holding) else {
      return false
    }
  }
  true
}

///|
// Lifetime observation after the exact Row allocation is handed to its SAME
// DAG. New-construction helpers above retain their stricter no-DAG census.
pub fn row_captured_inputs_live(
  value : RowCapturedInputs,
  ledger : @resources.Ledger,
) -> Bool {
  if !physical_equal(value.ledger, ledger) {
    return false
  }
  for capture in value.captures {
    if row_capture_source(capture) is Err(_) {
      return false
    }
  }
  for index, capture in value.captures {
    let (reservation, original) = value.originals[index]
    guard !capture.run.closed &&
      capture.run.physical is Some(physical) &&
      physical_equal(physical.ledger, ledger) &&
      physical_equal(physical.reservation, reservation) else {
      return false
    }
    match (physical.dag, physical.holding) {
      (None, Some(holding)) =>
        if !physical_equal(holding, original) {
          return false
        }
      (Some((dag, task)), None) =>
        if !@strategy.captured_task_allocation_matches(dag, task, original) {
          return false
        }
      _ => return false
    }
  }
  true
}

///|
// Exact whole-input check after all callbacks, before the existing Local
// prefix reserves. Equal requirements cannot replace physical capture custody.
pub fn row_captures_original_prefix_available(
  value : RowCapturedInputs,
  ledger : @resources.Ledger,
  prefix? : @resources.Reservation? = None,
) -> Bool {
  physical_equal(value.ledger, ledger) &&
  row_captured_inputs_current(value) &&
  (match prefix {
    None =>
      @resources.original_captured_inputs_prefix_available(
        ledger,
        value.originals,
      )
    Some(prefix) =>
      @resources.original_captured_inputs_prefix_reservation_available(
        ledger,
        value.originals,
        prefix,
      )
  })
}

///|
pub fn row_captured_inputs_count(value : RowCapturedInputs) -> Int {
  value.captures.length()
}

///|
// Borrow only the exact opaque capture supplied by the caller, never tokens.
pub fn row_captured_input_at(
  value : RowCapturedInputs,
  index : Int,
) -> RowSourceCapture? {
  value.captures.get(index)
}

///|
pub fn row_captures_original_keyed_preparation_available(
  value : RowCapturedInputs,
  ledger : @resources.Ledger,
  identity : @resources.OriginalLedgerIdentity,
  prefix? : @resources.Reservation? = None,
) -> Bool {
  guard physical_equal(value.ledger, ledger) &&
    row_captured_inputs_current(value) else {
    return false
  }
  @resources.original_ledger_captured_inputs_preparation_available(
    identity,
    value.originals,
    prefix~,
  )
}

///|
pub fn row_captures_original_keyed_child_available(
  value : RowCapturedInputs,
  ledger : @resources.Ledger,
  identity : @resources.OriginalLedgerIdentity,
  assembly : @resources.Reservation,
  children : Int,
  prefix? : @resources.Reservation? = None,
) -> Bool {
  guard physical_equal(value.ledger, ledger) &&
    row_captured_inputs_current(value) else {
    return false
  }
  @resources.original_keyed_inputs_child_preparation_available(
    identity,
    ledger,
    value.originals,
    assembly,
    children,
    prefix~,
  )
}

///|
pub fn row_captures_original_keyed_serialization_available(
  value : RowCapturedInputs,
  ledger : @resources.Ledger,
  identity : @resources.OriginalLedgerIdentity,
  prefix : @resources.Reservation,
  assembly : @resources.Reservation,
  children : Int,
) -> Bool {
  guard physical_equal(value.ledger, ledger) &&
    row_captured_inputs_current(value) else {
    return false
  }
  @resources.original_keyed_inputs_serialization_preparation_available(
    identity,
    ledger,
    value.originals,
    prefix,
    assembly,
    children,
  )
}

///|
// Cleanup facts stay available after scope cancellation. A true result says
// nothing about this prefix's own pending physical cleanup acknowledgement.
pub fn row_captures_original_keyed_prefix_dependents_retired(
  value : RowCapturedInputs,
  ledger : @resources.Ledger,
  prefix : @resources.Reservation,
) -> Bool {
  guard physical_equal(value.ledger, ledger) else { return false }
  @resources.original_keyed_inputs_prefix_dependents_retired(
    ledger,
    value.originals,
    prefix,
  )
}

///|
pub fn row_captures_original_keyed_lookup_dependents_retired(
  value : RowCapturedInputs,
  ledger : @resources.Ledger,
  assembly : @resources.Reservation,
  prefix? : @resources.Reservation? = None,
) -> Bool {
  guard physical_equal(value.ledger, ledger) else { return false }
  @resources.original_keyed_inputs_lookup_dependents_retired(
    ledger,
    value.originals,
    assembly,
    prefix~,
  )
}

///|
// Immutable original query DATA only. Availability is a separate final fence.
pub fn row_captured_input_requirement_at(
  value : RowCapturedInputs,
  index : Int,
) -> @planning.QueryRequirement? {
  guard value.captures.get(index) is Some(capture) &&
    capture.run.configuration is DirectConfiguration(configuration) else {
    return None
  }
  Some(configuration.requirement)
}
