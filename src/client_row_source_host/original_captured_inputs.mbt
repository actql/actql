///|
// Capability-free borrowed identity retained by the existing prefix. In
// particular cleanup keeps the exact tokens after Row clears its live holding.
// This object neither owns cleanup nor issues completion, resources or reads.
struct RowCapturedInputs {
  ledger : @resources.Ledger
  captures : Array[RowCapturedInput]
  originals : Array[(@resources.Reservation, @resources.Holding)]
}

///|
pub fn row_captured_inputs_construction_inventory(
  count : Int,
) -> @execution.PreparationRepresentationUnits? {
  if count < 1 {
    return None
  }
  guard @shape.reference_array_retained_extent(3L, 3L * count.to_int64())
    is Some(arrays) else {
    return None
  }
  Some({
    record_headers: 1L + 2L * count.to_int64() + arrays.record_headers,
    reference_slots: 3L + 3L * count.to_int64() + arrays.reference_slots,
    scalar_words: count.to_int64() + arrays.scalar_words,
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
  guard captures.all(capture => {
      capture.run.configuration is DirectConfiguration(_)
    }) &&
    snapshot_row_captured_inputs(
      captures.map(capture => RowCapturedInput::{ original: Live(capture), }),
      ledger,
      max_work,
    )
    is Some(value) &&
    @resources.original_captured_inputs_prefix_available(
      ledger,
      value.originals,
    ) &&
    row_captured_inputs_fence(value, ledger, false) else {
    return None
  }
  Some(value)
}

///|
// Nominal borrowed input of the existing shared Run. This is not the old
// standalone prefix entrance and grants no new Source/read/retirement right.
pub fn borrow_row_captured_inputs(
  captures : Array[RowSourceCapture],
  ledger : @resources.Ledger,
  max_work : Int,
) -> RowCapturedInputs? {
  guard captures.all(capture => {
      capture.run.configuration is DirectConfiguration(_)
    }) &&
    snapshot_row_captured_inputs(
      captures.map(capture => RowCapturedInput::{ original: Live(capture), }),
      ledger,
      max_work,
    )
    is Some(value) &&
    @resources.original_borrowed_captured_inputs_available(
      ledger,
      value.originals,
    ) &&
    row_captured_inputs_fence(value, ledger, false) else {
    return None
  }
  Some(value)
}

///|
fn snapshot_row_captured_inputs(
  captures : Array[RowCapturedInput],
  ledger : @resources.Ledger,
  max_work : Int,
) -> RowCapturedInputs? {
  if captures.is_empty() || max_work < 0 || captures.length() > max_work / 2 {
    return None
  }
  let captures = captures.copy()
  let originals = []
  for capture in captures {
    guard row_captured_input_pair(capture, ledger) is Some(pair) else {
      return None
    }
    originals.push(pair)
  }
  let value = RowCapturedInputs::{ ledger, captures, originals, }
  guard row_captured_inputs_current(value) else { return None }
  Some(value)
}

///|
pub fn row_captured_inputs_borrowed_available(
  value : RowCapturedInputs,
  ledger : @resources.Ledger,
) -> Bool {
  row_captured_inputs_live(value, ledger) &&
  @resources.original_borrowed_captured_inputs_available(
    ledger,
    value.originals,
  ) &&
  row_captured_inputs_fence(value, ledger, true)
}

///|
fn row_captured_inputs_current(value : RowCapturedInputs) -> Bool {
  for capture in value.captures {
    if row_captured_input_source(capture) is None {
      return false
    }
  }
  for index, capture in value.captures {
    let (reservation, holding) = value.originals[index]
    if !row_captured_input_fence(
        capture,
        value.ledger,
        reservation,
        holding,
        false,
      ) {
      return false
    }
  }
  true
}

///|
pub fn row_captured_inputs_live(
  value : RowCapturedInputs,
  ledger : @resources.Ledger,
) -> Bool {
  if !physical_equal(value.ledger, ledger) {
    return false
  }
  for capture in value.captures {
    if row_captured_input_source(capture) is None {
      return false
    }
  }
  for index, capture in value.captures {
    let (reservation, holding) = value.originals[index]
    if !row_captured_input_fence(capture, ledger, reservation, holding, true) {
      return false
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
  match value.captures.get(index) {
    Some({ original: Live(capture), }) => Some(capture)
    _ => None
  }
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
  guard row_captured_input_at(value, index) is Some(capture) &&
    capture.run.configuration is DirectConfiguration(configuration) else {
    return None
  }
  Some(configuration.requirement)
}

///|
pub fn borrow_row_captured_input_originals(
  captures : Array[RowCapturedInput],
  ledger : @resources.Ledger,
  max_work : Int,
) -> RowCapturedInputs? {
  guard snapshot_row_captured_inputs(captures, ledger, max_work) is Some(value) &&
    @resources.original_borrowed_captured_inputs_available(
      ledger,
      value.originals,
    ) &&
    row_captured_inputs_fence(value, ledger, false) else {
    return None
  }
  Some(value)
}

///|
pub fn retain_row_captured_input_originals(
  captures : Array[RowCapturedInput],
  ledger : @resources.Ledger,
  max_work : Int,
) -> RowCapturedInputs? {
  guard snapshot_row_captured_inputs(captures, ledger, max_work) is Some(value) &&
    @resources.original_captured_inputs_prefix_available(
      ledger,
      value.originals,
    ) &&
    row_captured_inputs_fence(value, ledger, false) else {
    return None
  }
  Some(value)
}

///|
pub fn row_captured_inputs_source_at(
  value : RowCapturedInputs,
  index : Int,
) -> @query.CapturedInputSource? {
  match value.captures.get(index) {
    Some(capture) => row_captured_input_source(capture)
    None => None
  }
}

///|
pub fn row_captured_inputs_source_original_at(
  value : RowCapturedInputs,
  index : Int,
) -> @sourcequery.SourceAcquisition? {
  match value.captures.get(index) {
    Some(capture) => row_captured_input_source_original(capture)
    None => None
  }
}

///|
// No Source or current callback follows this fence before the caller's census.
fn row_captured_inputs_fence(
  value : RowCapturedInputs,
  ledger : @resources.Ledger,
  allow_dag : Bool,
) -> Bool {
  if !physical_equal(value.ledger, ledger) {
    return false
  }
  for index, capture in value.captures {
    let (reservation, holding) = value.originals[index]
    if !row_captured_input_fence(
        capture, ledger, reservation, holding, allow_dag,
      ) {
      return false
    }
  }
  true
}
