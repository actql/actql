///|
// Body-side framing overlaps the nested resume writer. Legacy measurement
// has the same field/node layout, but its measuring sink retains no body.
fn prepare_native_effect_checkpoint_companion_body(
  record : NativeClientCheckpointRecord,
  reserve : ((Int64, Int64, Int64) -> Result[Unit, NativeClientRunJournalIssue])?,
) -> Result[Unit, NativeClientRunJournalIssue] {
  guard reserve is Some(before) else { return Ok(()) }
  let mut units = record.artifact.wire.length().to_int64() +
    record.state.wire.length().to_int64() +
    record.updated_at.length().to_int64() +
    record.binding.authorization_context_cid.length().to_int64() +
    record.binding.environment_binding_cid.length().to_int64() +
    record.resolution_cid.map(value => value.length().to_int64()).unwrap_or(0L) +
    record.resume_intent_id
    .map(value => value.length().to_int64())
    .unwrap_or(0L) +
    record.verified_wire.map(value => value.length().to_int64()).unwrap_or(0L)
  for name in record.declared_results {
    units += name.length().to_int64()
  }
  for effect in record.unknown_effects {
    units += effect.length().to_int64()
  }
  let intent_bytes = if record.resume_intent is Some(_) { 4096L } else { 0L }
  // Field names, fixed values, delimiters, cardinality-bounded arrays and
  // immutable SHA-256 CIDs use ASCII. Other text can take six bytes per unit.
  let slots = record.declared_results.length() +
    record.unknown_effects.length() +
    record.effect_ledger.length()
  let bytes = Int64::min(
    262144L,
    640L +
    3L * slots.to_int64() +
    71L * record.effect_ledger.length().to_int64() +
    6L * (units + intent_bytes),
  ).to_int()
  guard native_metadata_string_writer_working(
      bytes,
      bytes.to_int64(),
      slots + 20,
      4,
    )
    is Some((retained, peak, raw)) else {
    return Err(CapacityExceeded)
  }
  if intent_bytes == 0L {
    return before(retained, peak, raw)
  }
  guard native_metadata_string_writer_working(4096, intent_bytes, 16, 2)
    is Some((_, resume_peak, resume_raw)) else {
    return Err(CapacityExceeded)
  }
  before(retained, peak + resume_peak, Int64::max(raw, resume_raw))
}

///|
// The compact row's parsing controls and ledger CID order are live while its
// exact entries are admitted. The remaining inner Checkpoint validators run
// with their original limits and original semantic/physical bindings.
fn prepare_native_effect_checkpoint_companion_read(
  wire : String,
  reserve : ((Int64, Int64, Int64) -> Result[Unit, NativeClientRunJournalIssue])?,
) -> Result[Unit, NativeClientRunJournalIssue] {
  guard reserve is Some(before) else { return Ok(()) }
  guard @scalar.admit_utf8_length(wire, 131072) is Ok(bytes) &&
    @decode.preserving_json_admission_construction_inventory(bytes, 1024, 4)
    is Some(parser) &&
    @source.json_tree_retained_construction_extent(
      1024,
      1023,
      1024,
      0,
      bytes.to_int64(),
    )
    is Some(tree) &&
    @execution.preparation_representation_cost({
      record_headers: tree.record_headers + 8L,
      reference_slots: tree.reference_slots + 2L * (12L + 3L * 128L),
      scalar_words: tree.scalar_words + 14L,
      owned_utf16_units: tree.owned_utf16_units,
      owned_wire_bytes: 0L,
    })
    is Some(retained) &&
    @execution.preparation_representation_cost({
      record_headers: parser.record_headers,
      reference_slots: parser.reference_slots,
      scalar_words: parser.scalar_words,
      owned_utf16_units: parser.owned_utf16_units,
      owned_wire_bytes: bytes.to_int64(),
    })
    is Some(scratch) else {
    return Err(CapacityExceeded)
  }
  let (header, unit, terminator, array_header, pointer) = @bootstrap.native_managed_value_layout()
  if header <= 0L || unit != 2L || terminator != unit || pointer < 4L {
    return Err(CapacityExceeded)
  }
  let mut capacity = 1L
  while capacity < bytes.to_int64() {
    capacity *= 2L
  }
  let raw = Int64::max(
    header + (capacity + 1L) * unit,
    array_header + (18L + 11L * 1024L) * pointer,
  )
  before(retained, retained + scratch, raw)
}
