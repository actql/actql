///|
/// canonical_json::emit_value owns only its open-container ancestry. Each
/// parent is one payload variant plus EmitArray/ObjectCursor; frozen child
/// inventories and their Strings are borrowed. The synchronous loop retains
/// one pop Some, not one Visit continuation per emitted child. Writer-owned
/// key/text cursors are separately included in the shared writer recipe.
fn compilation_canonical_emitter_layout(
  depth : Int,
) -> @execution.PreparationRepresentationUnits? {
  if depth < 0 {
    return None
  }
  let d = depth.to_int64() + 1L
  let packet : @execution.PreparationRepresentationUnits = {
    record_headers: 4L + 2L * d,
    reference_slots: 14L + 5L * d,
    scalar_words: 3L + 2L * d,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  guard @execution.preparation_representation_cost(packet) is Some(_) else {
    return None
  }
  Some(packet)
}

///|
/// Quotation of the existing shared writer's live Map-key inventory, not its
/// max_nodes execution limit. end_object pops its exact Frame; on pinned JS
/// Array.pop removes the slot. Ordered frames own no Map. At most depth open
/// objects of bounded width can coexist. Closed backing capacity remains in
/// the shared depth-dependent packet. Writer limits still use full nodes.
fn compilation_writer_ancestry_layout(
  nodes : Int,
  depth : Int,
  largest_object : Int,
  count : Int,
  material_count : Int,
  bytes : Int,
) -> @execution.PreparationRepresentationUnits? {
  if nodes < 0 || depth < 0 || largest_object < 0 {
    return None
  }
  let keys = Int64::min(
    nodes.to_int64(),
    depth.to_int64() * largest_object.to_int64(),
  )
  if count < 0 || material_count < 0 || material_count > count || bytes < 0 {
    return None
  }
  guard @encode.hash_writer_live_key_inventory(keys.to_int(), depth) is Some(w) else {
    return None
  }
  let base : @execution.PreparationRepresentationUnits = {
    record_headers: w.record_headers,
    reference_slots: w.reference_slots,
    scalar_words: w.scalar_words,
    owned_utf16_units: w.owned_utf16_units,
    owned_wire_bytes: w.owned_wire_bytes,
  }
  guard compilation_metadata_repeat_units(base, count.to_int64())
    is Some(repeated) else {
    return None
  }
  let m = material_count.to_int64()
  let material : @execution.PreparationRepresentationUnits = {
    record_headers: 4L * m,
    reference_slots: 2L * m,
    scalar_words: m,
    owned_utf16_units: 2L * m * bytes.to_int64(),
    owned_wire_bytes: 0L,
  }
  @execution.compose_preparation_representation([repeated, material])
}
