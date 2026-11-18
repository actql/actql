///|
priv struct RelationPublicProjectionGeometry {
  input : RelationRestoreWireGeometry
  body_bytes : Int
  output_bytes : Int
  output_nodes : Int
  output_depth : Int
  aggregate_depth : Int
}

///|
// SAME borrowed catalogue entry, not a policy maximum or a JSON admission.
// Count every punctuation/escape, including inside strings, before any parse.
fn relation_public_projection_geometry(
  wire : String,
) -> RelationPublicProjectionGeometry? {
  guard @scalar.admit_utf8_length(wire, 2147483647) is Ok(bytes) && bytes > 0 else {
    return None
  }
  let mut nodes = 1L
  let mut depth = 0
  let mut peak = 0
  let mut quoted = false
  let mut escaped = false
  for unit in wire.iter() {
    let code = unit.to_int()
    if code == 123 || code == 91 {
      nodes += 2L
    } else if code == 58 || code == 44 || code == 92 {
      nodes += 1L
    }
    if quoted {
      if escaped {
        escaped = false
      } else if code == 92 {
        escaped = true
      } else if code == 34 {
        quoted = false
      }
    } else if code == 34 {
      quoted = true
    } else if code == 123 || code == 91 {
      depth += 1
      peak = Int::max(peak, depth)
    } else if code == 125 || code == 93 {
      depth = Int::max(0, depth - 1)
    }
  }
  let u = wire.length().to_int64()
  // Disjoint public schema/request/facts/acquisition/identity bodies together
  // have <=U original units and <=N nodes. Escaping <=6U; Double text <=25N.
  guard @execution.checked_preparation_add_product(6L * u, nodes, 25L)
    is Some(body) else {
    return None
  }
  // Original keys/values, detached bodies escaped once more, schema CID and
  // private-destination spelling. Charge each possible input node, not a
  // guessed supported view count. No Native writer ceiling is imported.
  let introduced = "{\"schema_wire\":\"\",\"schema_cid\":\"sha256:\"}"
    .length()
    .to_int64() +
    64L +
    "_wirepublic_input_field:".length().to_int64()
  guard @execution.checked_preparation_add_product(
      6L * body + 6L * u + "{\"views\":[]}".length().to_int64(),
      nodes,
      introduced + 25L,
    )
    is Some(output) &&
    @execution.checked_preparation_add_product(4L, nodes, 3L)
    is Some(output_nodes) &&
    @execution.checked_preparation_add_product(0L, nodes, peak.to_int64() + 1L)
    is Some(frames) &&
    nodes <= 2147483647L &&
    body <= 2147483647L &&
    output <= 2147483647L &&
    output_nodes <= 2147483647L &&
    frames <= 2147483647L &&
    peak <= 2147483643 else {
    return None
  }
  Some({
    input: {
      bytes,
      units: wire.length(),
      nodes: nodes.to_int(),
      depth: Int::max(1, peak),
    },
    body_bytes: body.to_int(),
    output_bytes: output.to_int(),
    output_nodes: output_nodes.to_int(),
    output_depth: peak + 3,
    aggregate_depth: frames.to_int(),
  })
}

///|
// Exact dataKeys=true from_json families: text is borrowed, not normalized or
// copied. Sum every call's controls; all body subtrees are disjoint. The same
// existing canonical forest and Map/Array growth helpers own their layouts.
fn relation_public_projection_canonical(
  nodes : Int,
  frames : Int,
  calls : Int64,
) -> @execution.PreparationRepresentationUnits? {
  guard relation_construction_json_forest(nodes.to_int64()) is Some(tree) &&
    @shape.collection_construction_extent({
      records: 12L * calls + 5L * frames.to_int64(),
      record_references: 24L * calls + 12L * frames.to_int64(),
      record_words: 12L * calls + 6L * frames.to_int64(),
      reference_arrays: 3L * calls,
      reference_items: nodes.to_int64() + 4L * frames.to_int64(),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(controls) else {
    return None
  }
  @execution.compose_preparation_representation([
    relation_construction_collection_units(tree),
    relation_construction_collection_units(controls),
  ])
}

///|
/// Constructor demand BEFORE parsing one retained original public entry.
/// Parsed Json, every failure-prefix canonical forest/Map/writer/hash and the
/// returned wire coexist conservatively until SAME Source initialization
/// retirement. Host JS parsing/descriptors and later Relation restore remain
/// separate charges. No admission, capacity grant or physical read occurs.
pub fn relation_public_projection_construction_inventory(
  wire : String,
) -> @execution.PreparationRepresentationUnits? {
  guard relation_public_projection_geometry(wire) is Some(g) else {
    return None
  }
  let n = g.input.nodes.to_int64()
  guard relation_restore_raw_json(g.input) is Some(parsed) &&
    relation_public_projection_canonical(g.input.nodes, g.aggregate_depth, n)
    is Some(bodies) &&
    relation_public_projection_canonical(g.output_nodes, g.output_depth + 1, 1L)
    is Some(final_tree) &&
    relation_construction_writer_units(
      g.body_bytes,
      g.input.nodes,
      g.aggregate_depth,
    )
    is Some(body_writer) &&
    relation_construction_writer_units(0, 1, 0) is Some(fixed_writer) &&
    relation_restore_scale(fixed_writer, n) is Some(body_call_controls) &&
    relation_construction_writer_units(
      g.output_bytes,
      g.output_nodes,
      g.output_depth,
    )
    is Some(final_writer) &&
    @shape.collection_construction_extent({
      // Projected Json.String/Object wrappers, saved/output arrays, per-key
      // optional-name Array, original-map iteration and fixed return controls.
      records: 10L + 5L * n,
      record_references: 12L + 8L * n,
      record_words: 12L + 2L * n,
      reference_arrays: 3L + 2L * n,
      reference_items: 4L + 8L * n,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: n + 1L,
      map_entries: 2L * n + 1L,
    })
    is Some(projected) &&
    @shape.collection_construction_extent({
      // sha256.hasher state8/words64/block64 + hex digits16 + output32/length8; byte/digest
      // wrappers, iterators, builder and finish controls are co-held per call.
      records: 32L * n,
      record_references: 24L * n,
      record_words: 16L * n,
      reference_arrays: 0L,
      reference_items: 0L,
      scalar_arrays: 6L * n,
      scalar_items: 192L * n,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(hash) else {
    return None
  }
  @execution.compose_preparation_representation([
    parsed,
    bodies,
    final_tree,
    body_writer,
    body_call_controls,
    final_writer,
    relation_construction_collection_units(projected),
    relation_construction_collection_units(hash),
    {
      // Installed Host prepareNativeInput retains one own-data {wire} carrier.
      // This is the actual fixed return representation, not spare allowance.
      record_headers: 1L,
      reference_slots: 1L,
      scalar_words: 0L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    {
      // Optional/private destination keys; hex builder old/new/result64 each
      // plus prefixed CID71. UTF8 old/new backing and digest32 remain separate.
      record_headers: 6L * n,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: 263L * n +
      "_wirepublic_input_field:".length().to_int64() * n,
      owned_wire_bytes: 6L * g.body_bytes.to_int64() + 32L * n,
    },
  ])
}

///|
/// Thin wire adapter to the SAME mechanical projection. Original catalogue
/// admission belongs to its retained caller; this method grants no authority.
/// Its observed constructor geometry supplies encoding ceilings, not a new
/// supported profile. Actual Relation restoration keeps its existing limits.
pub fn project_relation_declaration_wire_input(
  wire : String,
) -> Result[String, RowHostIssue] {
  guard relation_public_projection_geometry(wire) is Some(g) else {
    return Err(InvalidSpecification)
  }
  let entry = @json.parse(wire) catch { _ => return Err(InvalidSpecification) }
  project_relation_declaration_input(
    entry,
    g.output_bytes,
    g.output_nodes,
    g.output_depth,
  )
}
