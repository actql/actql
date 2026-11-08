///|
// Native Store alone supplies the actual originals/layouts to this private
// arithmetic. Keep shared parser/Map inventories in one portable body; the
// unsupported Store method still returns None and never calls this helper.
#warnings("-unused_value")
fn captured_content_custody_inventory(
  max_record_bytes : Int,
  active_writers : Int,
  chunk_bytes : Int,
  diagnostics : Int,
  read : @filesystem.NativeFilesystemReadLayout,
  write : @filesystem.NativeFilesystemWriteLayout,
  canonical_record_bytes? : Int? = None,
) -> @execution.PreparationRepresentationUnits? {
  if max_record_bytes <= 0 ||
    active_writers < 0 ||
    chunk_bytes <= 0 ||
    chunk_bytes > 1048576 ||
    diagnostics <= 0 {
    return None
  }
  let record = canonical_record_bytes.unwrap_or(max_record_bytes)
  if record <= 0 || record > max_record_bytes {
    return None
  }
  guard read.reader_payload_bytes > 0L &&
    read.external_object_overhead_bytes > 0L &&
    write.writer_payload_bytes > 0L &&
    write.external_object_overhead_bytes > 0L &&
    @encode.text_writer_construction_inventory(record, 64, 2) is Some(text) &&
    @decode.preserving_json_admission_construction_inventory(record, 8, 2)
    is Some(parsed) &&
    @shape.map_construction_extent(1L, active_writers.to_int64() + 1L)
    is Some(registration) else {
    return None
  }
  // C payloads include neither the two existing external-object headers nor
  // owned names/diagnostics. Four encoded/copied leaf frontiers of at most128
  // bytes and their terminators cover staging, final and verification names.
  // Four retained C diagnostics, replacement and one returned Bytes overlap;
  // decoded/builder detail below adds eight UTF16 copies. Reader frees its old
  // C chunk BEFORE the next allocation; one C and one returned chunk overlap.
  guard @execution.checked_preparation_add_product(
      read.reader_payload_bytes,
      write.writer_payload_bytes,
      1L,
    )
    is Some(native) &&
    @execution.checked_preparation_add_product(
      native,
      read.external_object_overhead_bytes,
      1L,
    )
    is Some(native) &&
    @execution.checked_preparation_add_product(
      native,
      write.external_object_overhead_bytes,
      1L,
    )
    is Some(native) &&
    @execution.checked_preparation_add_product(native, 129L, 4L) is Some(native) &&
    @execution.checked_preparation_add_product(native, 128L, 4L) is Some(native) &&
    @execution.checked_preparation_add_product(
      native,
      diagnostics.to_int64() + 1L,
      6L,
    )
    is Some(native) &&
    @execution.checked_preparation_add_product(
      native,
      chunk_bytes.to_int64(),
      2L,
    )
    is Some(native) else {
    return None
  }
  @execution.compose_preparation_representation([
    {
      record_headers: parsed.record_headers,
      reference_slots: parsed.reference_slots,
      scalar_words: parsed.scalar_words,
      owned_utf16_units: parsed.owned_utf16_units,
      owned_wire_bytes: 0L,
    },
    {
      // SAME Store registration, with actual existing entry multiplicity. The
      // common Map owner includes old/new bucket backing; no private Map tariff.
      record_headers: registration.record_headers,
      reference_slots: registration.reference_slots,
      scalar_words: registration.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    {
      record_headers: 4L * text.record_headers,
      reference_slots: 4L * text.reference_slots,
      scalar_words: 4L * text.scalar_words,
      owned_utf16_units: 4L * text.owned_utf16_units,
      // Malformed/raw database bodies can still reach the configured bound.
      // Only canonical output and prechecked parser geometry use `record`.
      owned_wire_bytes: 5L * max_record_bytes.to_int64(),
    },
    {
      // Custody H1/R15/W8 plus closed purpose H1/R1/W1; five Some slots H5/R5/W5; failures + their Some
      // H4/R6/W4; generation H1/W3; chunk H1/R1/W1; four fields-array growth
      // peaks H8/R48; five retained/returned record Bytes H5; four names plus
      // suffix/replacement builder H7/R2/W2. Four record field sequences keep
      // at most three 20-character decimal originals apiece (240 UTF16).
      // Two SHA states/digest/hex construction peaks H18/R10/W186/B192/T526
      // cover persist's one-shot hash and confirm's SAME incremental hasher.
      // Fixed nested Store/FS calls, closure/Result/refusal/return controls
      // H32/R40/W32 also cover the original routing-return pending carrier.
      record_headers: 2L + 5L + 4L + 1L + 1L + 8L + 5L + 7L + 18L + 32L,
      reference_slots: 16L + 5L + 6L + 1L + 48L + 2L + 10L + 40L,
      scalar_words: 9L + 5L + 4L + 3L + 1L + 2L + 186L + 32L,
      // The original holding CID is71 characters; all private names are ASCII
      // <=128. No original candidate wire or Source content buffer is copied.
      owned_utf16_units: 4L * 128L + 240L + 526L + 8L * diagnostics.to_int64(),
      owned_wire_bytes: native + 192L,
    },
  ])
}
