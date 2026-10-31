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
/// Logical constructor/storage DATA for the same observed binary receiver,
/// held through output retirement. Not a transfer debit, permission, physical
/// cleanup observation or whole Host/secret/failed-child capacity. The caller
/// separately backs quotation and composes every other overlapping owner.
pub fn installed_effect_response_buffer_construction_capacity(
  max_response_bytes : Int,
) -> @execution.ExecutionCapacity? {
  guard installed_effect_response_buffer_representation(max_response_bytes)
    is Some(retained) else {
    return None
  }
  @execution.preparation_execution_capacity({
    retained,
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
}

///|
/// A necessary same-extent check before its original occurrence is borrowed
/// or bound. Transfer/attempt declarations alone cannot fund these buffers.
/// True says nothing about the remaining physical/Host/provider inventory.
pub fn installed_effect_operation_response_backing_fits(
  original : ClientInstalledEffectOperationExtent,
  max_response_bytes : Int,
) -> Bool {
  if !original.physical_attempt {
    return false
  }
  guard installed_effect_response_buffer_construction_capacity(
      max_response_bytes,
    )
    is Some(required) else {
    return false
  }
  @execution.execution_capacity_retained_bytes(original.capacity) >=
  @execution.execution_capacity_retained_bytes(required) &&
  @execution.execution_capacity_execution_bytes(original.capacity) >=
  @execution.execution_capacity_execution_bytes(required)
}
