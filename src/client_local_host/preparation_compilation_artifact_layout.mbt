///|
/// Final direct Values compilation owner packet, excluding metadata-owned
/// fact-manifest/template/compiled-contract payloads. Shared PreparedProgram,
/// Result names and node id are borrowed, never recharged as copied strings.
/// Caller proves no Result transformation before selecting this dependency.
fn compilation_artifact_retained_layout(
  plan_bytes : Int,
  fragment_bytes : Int,
  output_contract_bytes : Int,
) -> @execution.PreparationRepresentationUnits? {
  if plan_bytes < 0 || fragment_bytes < 0 || output_contract_bytes < 0 {
    return None
  }
  // Compilation6ref, Plan7slots +two None tags, Fragment5ref; empty
  // transformations and one-entry result_names Arrays (backing upper8); owner
  // Some wrapper. Three output Strings and three distinct71-unit CID Strings.
  // The initial owner-slot reference is funded by initial_control_units, not
  // repeated here. Metadata independently owns fact-manifest/template/contract.
  let value : @execution.PreparationRepresentationUnits = {
    record_headers: 14L,
    reference_slots: 29L,
    scalar_words: 7L,
    owned_utf16_units: plan_bytes.to_int64() +
    fragment_bytes.to_int64() +
    output_contract_bytes.to_int64() +
    213L,
    owned_wire_bytes: 0L,
  }
  guard @execution.preparation_representation_cost(value) is Some(_) else {
    return None
  }
  Some(value)
}

///|
/// Named compiler-local packets beside separately priced trees/writers. These
/// immutable parts are passed within one invocation, never globally cached.
fn compilation_parts_control_layout() -> @execution.PreparationRepresentationUnits {
  {
    // AoAIdentity, AoAParts, PlanGraph, ExecutionMaterial, ExecutablePlanParts,
    // ReadOriginals and its Some, ExecutablePlanBody:8records. Four graph
    // arrays with optional old backing:12headers. Three direct returned parts
    // tuples (3,2,2 refs), and measurement tuple (3scalarwords).
    record_headers: 8L + 12L + 4L,
    reference_slots: 2L + 2L + 2L + 5L + 4L + 5L + 1L + 10L + 4L * 9L + 7L,
    scalar_words: 3L + 3L + 1L + 4L * 2L + 3L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
}

///|
/// value_contract::emit_checked for a flat nonnullable Number Object. Root
/// members4 and active Number members2 coexist; FieldsAt is lazy, so this is
/// independent of row/field count. Number-only schema emission is smaller.
fn compilation_number_contract_emitter_layout() -> @execution.PreparationRepresentationUnits? {
  // CheckedEmission; pending Array+old backing; two members Arrays+old
  // backings; eight pending variants and current pop Some; six member tuples
  // and six payload Emissions; active key/text Option wrappers. Pending bound
  // follows End/Members/FieldsAt/Value/Key progression, not max_frames=Intmax.
  let packet : @execution.PreparationRepresentationUnits = {
    record_headers: 33L,
    reference_slots: 80L,
    scalar_words: 40L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  guard closed_values_sort_scratch_layout(4) is Some(sort) else { return None }
  closed_values_sum_layouts([packet, sort])
}

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
  closed_values_sum_layouts([repeated, material])
}
