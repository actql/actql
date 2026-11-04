///|
/// Existing typed and nested reference-emission continuation constructors.
/// Values, FrozenArray backing and reference envelopes are borrowed. Writer,
/// output fragments and their final concatenation remain separate owners.
pub(all) struct WireEmitConstructionInventory {
  record_headers : Int64
  reference_slots : Int64
  scalar_words : Int64
  owned_utf16_units : Int64
} derive(Eq, Debug)

///|
fn wire_emit_construction_inventory(
  pending : Int64,
  decimal : DecimalValue?,
) -> WireEmitConstructionInventory? {
  if pending < 0 {
    return None
  }
  // Pending frames plus the popped current frame and one newly pushed frame.
  // Each frame can own one String/Key/ArrayRest/ObjectRest cursor. The largest
  // pair is KeyNext + OrderedKeyEmitCursor: 2H4R4W. ReferenceNext's canonical
  // child frames are included by wire_emit_pending_frames, not charged twice.
  let slots = pending + 2L
  let controls = @shape.collection_construction_extent({
    records: 2L + 2L * slots,
    record_references: 4L + 4L * slots,
    record_words: 1L + 4L * slots,
    reference_arrays: 2L,
    reference_items: slots,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }).unwrap()
  let mut decimal_units = 0L
  let mut decimal_headers = 0L
  let mut decimal_refs = 0L
  let mut decimal_words = 0L
  if decimal is Some(value) {
    if value.precision < 1 ||
      value.precision > 38 ||
      value.scale < 0 ||
      value.scale > value.precision ||
      value.coefficient.length() > value.precision + 1 {
      return None
    }
    if value.scale != 0 {
      // decimal_wire_text: detached digits, zero padding, padded digits,
      // two detached slices and three concatenation results. Three borrowed
      // slice views have 1R2W each. Each actual bounded spelling is <=P+3;
      // pinned concat/builder alternatives use <=3L+1 UTF16 backing slots.
      let length = (value.precision + 3).to_int64()
      decimal_units = 8L * (3L * length + 1L)
      decimal_headers = 11L
      decimal_refs = 3L
      decimal_words = 6L
    }
  }
  Some({
    record_headers: controls.record_headers + decimal_headers,
    reference_slots: controls.reference_slots + decimal_refs,
    scalar_words: controls.scalar_words + decimal_words,
    owned_utf16_units: decimal_units,
  })
}

///|
pub fn wire_emit_start_construction_inventory() -> WireEmitConstructionInventory {
  wire_emit_construction_inventory(1L, None).unwrap()
}

///|
pub fn wire_emit_next_construction_inventory(
  cursor : WireEmitCursor,
) -> WireEmitConstructionInventory? {
  let decimal = match cursor.pending.last() {
    Some(Read(Decimal(value))) => Some(value)
    _ => None
  }
  // Native arrays retain capacity after pop. Vacated slots are explicitly
  // payload-free, so only the current original reference child retains its
  // own backing. Inspect that one top frame, never rescan the Value tree.
  let reference = match cursor.pending.last() {
    Some(ReferenceNext(child)) =>
      @identity.emit_storage_frames(child).to_int64()
    _ => 0L
  }
  wire_emit_construction_inventory(
    cursor.pending.capacity().to_int64() + reference,
    decimal,
  )
}

///|
/// Existing typed/canonical steps emit at most64 UTF16 units. Each can escape
/// to six bytes, with at most four surrounding punctuation bytes. Decimal and
/// signed64 spellings are bounded leaves; references reuse canonical steps.
pub fn wire_emit_fragment_byte_bound() -> Int {
  64 * 6 + 4
}
