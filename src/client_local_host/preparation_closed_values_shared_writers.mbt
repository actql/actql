///|
/// Shared encoder dependency. Hashing structurally dominates measuring/text
/// writers; the latter also require their own JS builder old/new text owners.
fn closed_values_writer_layout(
  nodes : Int,
  depth : Int,
  count : Int,
  material_count : Int,
  material_bytes : Int,
) -> PreparationRepresentationUnits? {
  if count < 0 ||
    material_count < 0 ||
    material_count > count ||
    material_bytes < 0 {
    return None
  }
  guard @encode.hash_writer_construction_inventory(nodes, depth) is Some(w) else {
    return None
  }
  let c = count.to_int64()
  let m = material_count.to_int64()
  let b = material_bytes.to_int64()
  // Count is internal today, but preserve checked arithmetic if reused.
  guard preparation_cost_add(4L * m, w.record_headers, c + 1L) is Some(h_plus) &&
    preparation_cost_add(2L * m, w.reference_slots, c + 1L) is Some(r_plus) &&
    preparation_cost_add(m, w.scalar_words, c + 1L) is Some(s_plus) &&
    preparation_cost_add(2L * m * b, w.owned_utf16_units, c + 1L)
    is Some(t_plus) &&
    preparation_cost_add(0L, w.owned_wire_bytes, c + 1L) is Some(b_plus) else {
    return None
  }
  let output : PreparationRepresentationUnits = {
    record_headers: h_plus - w.record_headers,
    reference_slots: r_plus - w.reference_slots,
    scalar_words: s_plus - w.scalar_words,
    owned_utf16_units: t_plus - w.owned_utf16_units,
    owned_wire_bytes: b_plus - w.owned_wire_bytes,
  }
  guard preparation_representation_cost(output) is Some(_) else { return None }
  Some(output)
}

///|
/// Policy read: Capacity/TextTime each material writer, byte integrity hash
/// twice, canonical hash once; Lookup hashes once directly. Byte hashes use
/// the same stronger encoder+SHA recipe. Scalar policy emitter peak is2pending
/// frames plus the popped one, never an input-dependent recursive walk.
fn closed_values_policy_writer_layout() -> PreparationRepresentationUnits? {
  guard closed_values_writer_layout(28, 1, 4, 1, 1436) is Some(capacity) &&
    closed_values_writer_layout(7, 1, 4, 1, 279) is Some(text) &&
    closed_values_writer_layout(8, 1, 1, 0, 0) is Some(lookup) &&
    closed_values_js_bytes_document_layout(1715L, 2) is Some(decoded) else {
    return None
  }
  let emit : PreparationRepresentationUnits = {
    // Per emitter Array wrapper/new+oldbacking3, frames3, previous-key Some3,
    // pop Some1. Both scalar/ref payload alternatives conservatively reserved.
    record_headers: 3L * (3L + 3L + 3L + 1L),
    reference_slots: 3L * (1L + 3L + 6L + 3L + 1L),
    scalar_words: 3L * (2L + 12L + 3L + 1L),
    // Two pinnedJS parse_json_bytes calls: each BytesView, subarray view,
    // result Array and new decodedString =5H3R6W plus B UTF16.
    // TextDecoder is a module singleton, not a new per-query owner.
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  closed_values_sum_layouts([capacity, text, lookup, emit, decoded])
}

///|
/// Values-capacity emitter callsites:14hash/9measure/4material; one measure
/// walks original Values rows, other26 owners are fixed metadata<=40nodes.
/// Three direct byte integrity SHA scopes use the stronger zero-node recipe.
fn closed_values_operation_writer_layout(
  fields : Int,
  rows : Int,
) -> PreparationRepresentationUnits? {
  if fields < 1 || rows < 0 {
    return None
  }
  let row_nodes = 1L + rows.to_int64() * (1L + fields.to_int64())
  if row_nodes > 2147483647L {
    return None
  }
  guard closed_values_writer_layout(40, 4, 26, 4, 1331) is Some(metadata) &&
    closed_values_writer_layout(row_nodes.to_int(), 2, 1, 0, 0) is Some(values) &&
    closed_values_writer_layout(0, 0, 3, 0, 0) is Some(byte_hashes) else {
    return None
  }
  closed_values_sum_layouts([metadata, values, byte_hashes])
}

///|
/// Node JS ClosedValues identity phase only, using the shared writer recipe.
/// Seven distinct writers still coexist conservatively; this is NOT a max of
/// lifetimes. Only StageSemantics contains the original source body. The other
/// six preimages are fixed by the one-stage/no-parameters/no-imports shape:
/// ProgramSemantics20 nodes/depth5, two definitions4/depth1, two parameter-value
/// envelopes3/depth2, and one empty declarations object1/depth1.
/// Template emitters remain authoritative; no identity wire or checking changes.
fn closed_values_identity_writer_layout(
  source_nodes : Int,
  source_depth : Int,
) -> PreparationRepresentationUnits? {
  if source_nodes < 1 ||
    source_nodes > 2147483639 ||
    source_depth < 0 ||
    source_depth == 2147483647 {
    return None
  }
  guard closed_values_writer_layout(
      Int::max(source_nodes + 8, 20),
      Int::max(source_depth + 1, 5),
      1,
      0,
      0,
    )
    is Some(stage) &&
    closed_values_writer_layout(20, 5, 1, 0, 0) is Some(program) &&
    closed_values_writer_layout(4, 1, 2, 0, 0) is Some(definitions) &&
    closed_values_writer_layout(3, 2, 2, 0, 0) is Some(values) &&
    closed_values_writer_layout(1, 1, 1, 0, 0) is Some(declarations) else {
    return None
  }
  closed_values_sum_layouts([stage, program, definitions, values, declarations])
}
