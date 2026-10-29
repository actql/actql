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
  @execution.compose_preparation_representation([
    arrays, payload, sort, arrays, payload, sort,
  ])
}
