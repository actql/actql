///|
// The selected Credential Resource's OBSERVED binary reader owns a chunks
// Array, copies each nonempty admitted chunk, and concatenates at successful
// end. At most B one-byte chunks fit its B-byte body limit. Its current read
// has the same B+1 refusal window as the physical byte observer. Co-count the
// B copied bytes, B concat bytes and B+1 current bytes even on failure.
// This excludes parser/provider output, headers/secret/Journal/Node TLS/runtime
// backing and Host saved-response envelopes; it is not the full HTTP extent.
fn installed_effect_response_buffer_representation(
  max_response_bytes : Int,
) -> @execution.PreparationRepresentationUnits? {
  if max_response_bytes < 1 {
    return None
  }
  let b = max_response_bytes.to_int64()
  guard @shape.collection_construction_extent({
      records: b + 2L,
      record_references: 0L,
      record_words: 0L,
      reference_arrays: 1L,
      reference_items: b,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(buffers) else {
    return None
  }
  Some({
    record_headers: buffers.record_headers,
    reference_slots: buffers.reference_slots,
    scalar_words: buffers.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 3L * b + 1L,
  })
}

///|
/// Logical constructor/storage DATA for the same observed binary receiver.
/// Successful end severs copied chunks/listeners; the concat body remains.
/// The complete receive peak stays held on failed/pending paths until cleanup.
/// Not a transfer debit, permission, physical
/// cleanup observation or whole Host/secret/failed-child capacity. The caller
/// separately backs quotation and composes every other overlapping owner.
pub fn installed_effect_response_buffer_construction_capacity(
  max_response_bytes : Int,
) -> @execution.ExecutionCapacity? {
  guard installed_effect_response_buffer_representation(max_response_bytes)
    is Some(peak) else {
    return None
  }
  // SAME successful original receiver returns one binary body and severs its
  // copied prefix/Array/read listener before exposing it. Complete peak is
  // unchanged, including failed receive and concatenation prefixes.
  let retained : @execution.PreparationRepresentationUnits = {
    record_headers: 1L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: max_response_bytes.to_int64(),
  }
  @execution.preparation_execution_capacity({
    retained,
    workspace: {
      record_headers: peak.record_headers - retained.record_headers,
      reference_slots: peak.reference_slots,
      scalar_words: peak.scalar_words,
      owned_utf16_units: peak.owned_utf16_units,
      owned_wire_bytes: peak.owned_wire_bytes - retained.owned_wire_bytes,
    },
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}

///|
// Node's header counter charges field names/values, NOT CRLF/colon bytes;
// a valid field's nonempty name therefore permits up to H pairs, not H/4.
// It resets after initial headers, so header and trailer inventories coexist.
// See pinned node v22.22.0 src/node_http_parser.cc TrackHeader and
// on_headers_complete. No wrapper/VM/TLS tariff is defined here.
fn installed_effect_response_headers_representation(
  max_header_bytes : Int,
) -> @execution.PreparationRepresentationUnits? {
  if max_header_bytes < 1 {
    return None
  }
  let h = max_header_bytes.to_int64()
  // Two normalized dictionaries retain key/value references. Arrays include
  // raw headers/trailers, their cookie-value alternatives, selected pairs and
  // outer view, plus the two parser flush vectors. Co-count alternatives and
  // use the existing collection owner for growth, never another slot price.
  guard @shape.collection_construction_extent({
      records: 2L,
      record_references: 4L * h,
      record_words: 0L,
      reference_arrays: 7L + h,
      reference_items: 13L * h,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(headers) else {
    return None
  }
  // Both raw blocks <=2H units. Co-count lowercase/prefixed/sliced names for
  // both blocks (6H) and old/new joined values including duplicate separators
  // (12H). Selected values borrow those same strings. Parser span/concatenation
  // prefixes for both blocks add4H bytes. These are live constructor bounds,
  // not a per-wrapper quota or a claim about engine rope/GC storage.
  Some({
    record_headers: headers.record_headers,
    reference_slots: headers.reference_slots,
    scalar_words: headers.scalar_words,
    owned_utf16_units: (2L + 6L + 12L) * h,
    owned_wire_bytes: 4L * h,
  })
}

///|
/// Body and both raw/normalized header blocks coexist until this SAME
/// response owner severs them. This remains only response construction DATA;
/// native/provider output, requests, secrets, saved/failed overlap and control
/// backing must still be composed by the selected original implementation.
pub fn installed_effect_http_response_construction_capacity(
  max_response_bytes : Int,
  max_header_bytes : Int,
) -> @execution.ExecutionCapacity? {
  guard installed_effect_response_buffer_construction_capacity(
      max_response_bytes,
    )
    is Some(body) &&
    installed_effect_response_headers_representation(max_header_bytes)
    is Some(headers) else {
    return None
  }
  guard @execution.preparation_execution_capacity({
      retained: headers,
      workspace: {
        record_headers: 0L,
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
      retained_nodes: 0L,
      workspace_nodes: 0L,
      retained_bytes: 0L,
      workspace_bytes: 0L,
    })
    is Some(headers) else {
    return None
  }
  // Existing retainRunResponseOriginal optionally owns one independent
  // byte snapshot AFTER the successful receiver has severed copied chunks.
  // Co-fund both bodies in retention even for implementations that omit it.
  // That later two-body view fits the unchanged full receive peak; it never
  // overlaps the retired chunks/concat constructor/current-read envelope.
  @execution.execution_capacity(
    2L * @execution.execution_capacity_retained_bytes(body) +
    @execution.execution_capacity_retained_bytes(headers),
    @execution.execution_capacity_execution_bytes(body) +
    @execution.execution_capacity_execution_bytes(headers),
  )
}

///|
/// A necessary same-extent check before its original occurrence is borrowed
/// or bound. Transfer/attempt declarations alone cannot fund these buffers.
/// True says nothing about the remaining physical/Host/provider inventory.
pub fn installed_effect_operation_response_backing_fits(
  original : ClientInstalledEffectOperationExtent,
  max_response_bytes : Int,
  max_header_bytes : Int,
) -> Bool {
  if !original.physical_attempt {
    return false
  }
  guard installed_effect_http_response_construction_capacity(
      max_response_bytes, max_header_bytes,
    )
    is Some(required) else {
    return false
  }
  @execution.execution_capacity_retained_bytes(original.capacity) >=
  @execution.execution_capacity_retained_bytes(required) &&
  @execution.execution_capacity_execution_bytes(original.capacity) >=
  @execution.execution_capacity_execution_bytes(required)
}
