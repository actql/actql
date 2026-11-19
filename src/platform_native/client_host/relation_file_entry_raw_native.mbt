///|
// The fixed constructor endpoint is computed once from the SAME entry unit
// recipe and the existing Native layout owner. No Request quotes itself.
// Both supported paths have at most16 items slots and16 key slots. All
// physical payload bodies are borrowed here; file buffers open later on the
// separate business Source owner and do not belong to this Read endpoint.
fn native_relation_file_entry_read_raw_layout() -> (Int64, Int64, Int64)? {
  let units = native_relation_file_entry_read_control_units(
    16L,
    14L + 3L * 16L,
    4L,
    3L,
    @row_file.native_relation_file_caller_evaluation_maximum_inventory(),
    3L,
  )
  let (header, width, terminator, array_header, pointer) = @bootstrap.native_managed_value_layout()
  guard header > 0L &&
    width == 2L &&
    terminator == width &&
    array_header > 0L &&
    pointer > 0L &&
    @execution.checked_preparation_add_product(
      0L,
      units.reference_slots,
      pointer,
    )
    is Some(references) &&
    @execution.checked_preparation_add_product(
      references,
      units.scalar_words,
      8L,
    )
    is Some(payload) &&
    @execution.checked_preparation_add_product(
      Int64::max(header, array_header),
      payload,
      1L,
    )
    is Some(records) else {
    return None
  }
  // Summing all owned field slots bounds every single fixed record/closure
  // and fixed Array backing in this closed Read constructor. It is physical
  // header+pointer+word geometry, never a conversion of logical tariff bytes.
  // Path String bodies stay borrowed. Only the existing bounded diagnostic
  // constructor owns text; retain its pinned doubling and UTF16 terminator.
  let mut backing = 1L
  while backing < units.owned_utf16_units {
    backing *= 2L
  }
  guard @execution.checked_preparation_add_product(header, backing + 1L, width)
    is Some(text) else {
    return None
  }
  Some((Int64::max(records, text), array_header, pointer))
}

///|
let native_relation_file_entry_read_raw : (Int64, Int64, Int64) = native_relation_file_entry_read_raw_layout().unwrap()

///|
/// Largest original Read entry/snapshot allocation, independent of its full
/// logical retention/execution sum. This quantity does not admit a Source,
/// allocate backing or issue any physical/current/cleanup acknowledgement.
pub fn native_relation_file_entries_read_raw_bytes(count : Int) -> Int64? {
  if count <= 0 {
    return None
  }
  let (fixed, array_header, pointer) = native_relation_file_entry_read_raw
  // Snapshot map/append uses the same pinned <=12+3N backing-slot bound.
  // Original source DTOs, path arrays and their elements are never serialized.
  guard @execution.checked_preparation_add_product(12L, count.to_int64(), 3L)
    is Some(slots) &&
    @execution.checked_preparation_add_product(array_header, slots, pointer)
    is Some(vector) else {
    return None
  }
  Some(Int64::max(fixed, vector))
}

///|
// Pre-admitted quote controls: two checked scalar Options, returned scalar
// Some (3H/6W), the caller's zero-capture refusal closure (1H), and the two
// checked additions of the geometry payload to its R/E quote (2H/4W). This
// is separate from the later entry payload and cannot be funded by its grow.
let native_relation_file_entry_raw_quote_controls : Int64 = @execution.preparation_representation_cost({
    record_headers: 6L,
    reference_slots: 0L,
    scalar_words: 10L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  },
).unwrap()

///|
/// Fixed constructor controls on the original initial Read before evaluating
/// any entry raw endpoint. No capacity is reserved or granted by this DATA.
pub fn native_relation_file_entry_raw_quote_control_bytes() -> Int64 {
  native_relation_file_entry_raw_quote_controls
}
