///|
/// Constructor inventory for an already completed original Result, BEFORE
/// snapshot emission/parsing. This does not fund the preceding execution or
/// output export: their same checked Plan remains independently responsible.
fn recursive_snapshot_layout(
  logical_bytes : Int,
  logical_nodes : Int,
  logical_depth : Int,
  fields : Int,
  name_bytes : Int,
) -> ScalarSnapshotLayout? {
  // The logical {sort:"relation",value:ROWS} adds two value nodes and one
  // open container to the bare rows Array. Keys are not value nodes. Byte
  // length is kept as a conservative bound, without re-emitting the rows.
  if logical_bytes < 1 ||
    logical_nodes < 3 ||
    logical_depth < 2 ||
    fields < 0 ||
    name_bytes < 0 {
    return None
  }
  let nodes = logical_nodes - 2
  let depth = logical_depth - 1
  let n = nodes.to_int64()
  let d = depth.to_int64() + 1L
  let edges = n - 1L
  let f = fields.to_int64()
  // Independent maxima for parser Arrays and Objects are intentional. Each
  // can be bounded by the original node count without guessing value types.
  // Fields <=edges; key lexemes add <=edges to the parser node envelope.
  if 2L * n - 1L > 2147483647L || depth > nodes {
    return None
  }
  let facts : ClosedValuesLexicalFacts = {
    input_bytes: logical_bytes,
    node_upper: (2L * n - 1L).to_int(),
    arrays: nodes,
    objects: nodes - 1,
    fields_upper: nodes - 1,
    quoted_tokens: (2L * n - 1L).to_int(),
    quoted_utf16_units: logical_bytes,
    longest_quoted_utf16: logical_bytes,
    longest_atom_utf16: 25,
    depth_upper: depth,
  }
  let source = closed_values_source_inventories(facts)
  // All containers share one node envelope; treating every non-root node as
  // an Object also bounds all canonical field tuples and duplicate-key maps.
  guard compilation_canonical_layout({
      nodes,
      arrays: 1,
      objects: nodes - 1,
      fields: nodes - 1,
      depth,
      largest_object: nodes - 1,
    })
    is Some(canonical) else {
    return None
  }
  let strings : @execution.PreparationRepresentationUnits = {
    record_headers: 2L * n - 1L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: logical_bytes.to_int64(),
    owned_wire_bytes: 0L,
  }
  let snapshot : @execution.PreparationRepresentationUnits = {
    record_headers: 1L,
    reference_slots: 5L,
    scalar_words: 3L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  guard @execution.compose_preparation_representation([
      canonical.tree,
      strings,
      snapshot,
      closed_values_program_arrays(1L, f, false),
    ])
    is Some(retained) &&
    closed_values_units_subtract(source.source_retained, strings)
    is Some(private_source) else {
    return None
  }
  // CursorAdmission retains at most three continuation variants per open
  // ancestor. Object key/tuple/sort holdings sum to <=all original edges;
  // parents remain held while a nested child is admitted.
  let live_objects = Int64::min(edges, d)
  let pending = 3L * d
  let admission : @execution.PreparationRepresentationUnits = {
    record_headers: 8L + pending + d + 6L * live_objects + n,
    reference_slots: 9L +
    6L * pending +
    2L * d +
    2L * live_objects +
    4L * n +
    edges,
    scalar_words: 17L + 4L * pending + d + 28L * live_objects + 6L * edges,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let keys = closed_values_program_arrays(
    live_objects + edges,
    2L * edges,
    true,
  )
  let maps = closed_values_program_maps(live_objects, edges, true)
  let frames = closed_values_program_arrays(1L, pending, true)
  // The original stepped cell emitter holds only active ancestry. Two further
  // canonical emitters produce snapshot text and its logical hash. All three
  // are summed, including the Export->Admit transition; no premature credit.
  guard compilation_canonical_emitter_layout(logical_depth) is Some(emitter) &&
    compilation_writer_ancestry_layout(
      logical_nodes,
      logical_depth,
      nodes - 1,
      3,
      2,
      logical_bytes,
    )
    is Some(writers) &&
    scalar_snapshot_name_normalization_layout(name_bytes) is Some(normalization) else {
    return None
  }
  let emit_frames = closed_values_program_arrays(3L, 6L * d + 6L, true)
  // Completed snapshot13/23/21, captured snapshot13/29/35, outer1/2/4,
  // decode/field/contract return carriers6/8/8. Borrowed row/schema owners
  // remain in their existing output reservation; no value copy is hidden here.
  let controls : @execution.PreparationRepresentationUnits = {
    record_headers: 33L,
    reference_slots: 62L,
    scalar_words: 68L,
    owned_utf16_units: logical_bytes.to_int64(),
    owned_wire_bytes: 0L,
  }
  guard @execution.compose_preparation_representation([
      private_source,
      source.source_growth_peak,
      source.indexed_additional,
      source.key_admission_peak,
      source.parser_ancestry_peak,
      source.decoder_ancestry_peak,
      source.parser_controls_peak,
      source.decoder_controls_peak,
      admission,
      keys,
      maps,
      frames,
      canonical.temporary,
      emitter,
      emitter,
      emitter,
      emit_frames,
      writers,
      normalization,
      controls,
      closed_values_program_arrays(2L + f, 2L * f, true),
    ])
    is Some(temporary) &&
    @execution.preparation_representation_cost(retained) is Some(_) &&
    @execution.preparation_representation_cost(temporary) is Some(_) else {
    return None
  }
  Some({ retained, temporary, })
}
