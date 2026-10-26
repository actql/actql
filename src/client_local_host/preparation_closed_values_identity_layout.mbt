///|
/// Source-identity constructor component, not a resource grant. The caller
/// supplies extents of the SAME admitted one-stage Closed Values source and
/// combines this with the independently owned source/index, writer/hash and
/// failure-carrier components before opening the original preparation phase.
struct ClosedValuesIdentityLayout {
  fixed : @execution.PreparationRepresentationUnits
  preparation : @execution.PreparationRepresentationUnits
  emission : @execution.PreparationRepresentationUnits
  cid_strings : @execution.PreparationRepresentationUnits
} derive(Eq)

///|
/// The finite inventory in closed-values-identity-owner-inventory comprises
/// 33 records with 129 declared fields. Count each field in both eight-byte
/// slot categories conservatively; this is an upper projection, not an actual
/// charge. Thirty-six zero/one/four-entry Arrays each have capacity at most8.
/// Eleven empty Maps plus identifier Map1, and two distinct ObjectView Maps
/// (Stage4, Result declaration2), are separate owners. No identity-by-content
/// discount applies. The two Stage literal name-loop Arrays5/3 are additional.
fn closed_values_identity_fixed_layout() -> @execution.PreparationRepresentationUnits? {
  let records : @execution.PreparationRepresentationUnits = {
    record_headers: 33L + 2L + 5L,
    reference_slots: 129L + 4L + 10L,
    scalar_words: 129L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // Array wrappers/backing and old backing during growth; five copied export/
  // source-field tuples are included in records above. Literal loop Arrays
  // never grow and have eight occupied slots between them.
  let arrays : @execution.PreparationRepresentationUnits = {
    record_headers: 3L * 36L + 4L,
    reference_slots: 36L + 16L * 36L + 2L + 8L,
    scalar_words: 2L * 38L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let empty = closed_values_map_constructor_layout(0).unwrap()
  let one = closed_values_map_constructor_layout(1).unwrap()
  let stage = closed_values_map_constructor_layout(4).unwrap()
  let result = closed_values_map_constructor_layout(2).unwrap()
  closed_values_sum_layouts([
    records, arrays, empty, empty, empty, empty, empty, empty, empty, empty, empty,
    empty, empty, one, stage, result,
  ])
}

///|
/// pipeline_source.prepare and stage_source.prepare each retain a pending
/// Cursor traversal. Reuse the compiler's generic source walk convention;
/// summing both is conservative even though their preparation scopes are
/// sequential. Three parameter cursor_path Arrays own copied PathSegments.
/// Fixed nonrecursive VM frames are baseline; these are allocated containers.
fn closed_values_identity_preparation_layout(
  nodes : Int,
  fields : Int,
  depth : Int,
) -> @execution.PreparationRepresentationUnits? {
  guard closed_values_walk_storage_layout(nodes, fields) is Some(walk) else {
    return None
  }
  let d = depth.to_int64()
  if depth < 0 {
    return None
  }
  let paths = closed_values_program_arrays(3L, 3L * d, true)
  let segments : @execution.PreparationRepresentationUnits = {
    record_headers: 3L * d,
    reference_slots: 3L * d,
    scalar_words: 6L * d,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  closed_values_sum_layouts([walk, walk, paths, segments])
}

///|
/// Both source emitters use Value/ArrayRest/ObjectRest, not the generic walk's
/// tuple representation. An outer Stage emitter coexists with its Steps
/// emitter. Each has <=depth+2 live frames; each frame has <=1 reference and
/// two scalar payloads plus tag. Current field lists across its ancestors
/// contain <=nodes entries (distinct source child edges); each owns a tuple
/// and Cursor. Arrays include growth overlap. Sorting is the same pinned
/// builtin component used by compiler field sorting, not a second formula.
/// Strings and indexed subtrees are borrowed; no output wire is built here.
fn closed_values_identity_emitter_layout(
  nodes : Int,
  fields : Int,
  depth : Int,
) -> @execution.PreparationRepresentationUnits? {
  if nodes <= 0 || fields < 0 || fields > nodes || depth < 0 || depth > nodes {
    return None
  }
  let n = nodes.to_int64()
  let d = depth.to_int64() + 2L
  let arrays = closed_values_program_arrays(d + 1L, n + d, true)
  let payload : @execution.PreparationRepresentationUnits = {
    record_headers: d + 2L * n,
    reference_slots: d + 4L * n,
    scalar_words: 3L * d + n,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  guard closed_values_sort_scratch_layout(Int::max(fields, 1)) is Some(sort) else {
    return None
  }
  // Two original emitter owners, never max(Stage,Steps).
  closed_values_sum_layouts([arrays, payload, sort, arrays, payload, sort])
}

///|
/// Seven distinct CID String owners, each sha256 prefix7 + digest64. Digest
/// output Strings and writer internals are priced by the shared hash family.
/// StageDefinition borrows Descriptor.cid; it is not an eighth CID. Input
/// limits here are representation facts, never authority to allocate or run.
fn closed_values_identity_layout(
  nodes : Int,
  fields : Int,
  depth : Int,
) -> ClosedValuesIdentityLayout? {
  if nodes <= 0 || fields < 0 || fields > nodes || depth < 0 || depth > nodes {
    return None
  }
  guard closed_values_identity_fixed_layout() is Some(fixed) else {
    return None
  }
  guard closed_values_identity_preparation_layout(nodes, fields, depth)
    is Some(preparation) else {
    return None
  }
  guard closed_values_identity_emitter_layout(nodes, fields, depth)
    is Some(emission) else {
    return None
  }
  let cid_strings : @execution.PreparationRepresentationUnits = {
    record_headers: 7L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 497L,
    owned_wire_bytes: 0L,
  }
  guard closed_values_sum_layouts([fixed, preparation, emission, cid_strings])
    is Some(_) else {
    return None
  }
  Some({ fixed, preparation, emission, cid_strings, })
}
