///|
// Quantities for the EXISTING installed UPDATE Mapping constructor. The
// declaration and input strings are borrowed originals, not restored here.
// Only lexical geometry is observed; parsing, schema checking and identity
// construction remain in prepare_row_update_mapping and its existing bridge.
fn update_mapping_original_geometry(
  declaration : RowDeclaration,
  view : String,
) -> RelationRestoreWireGeometry? {
  guard relation_restore_wire_geometry(view) is Some(first) else { return None }
  let mut bytes = first.bytes.to_int64()
  let mut units = first.units.to_int64()
  let mut nodes = first.nodes.to_int64()
  let mut depth = first.depth
  for wire in declaration.contracts {
    guard relation_restore_wire_geometry(wire) is Some(next) else {
      return None
    }
    bytes += next.bytes.to_int64()
    units += next.units.to_int64()
    nodes += next.nodes.to_int64()
    depth = Int::max(depth, next.depth)
  }
  // The actual original reader has these cumulative parser limits. Once
  // exhausted it refuses before the next parse; no output is manufactured.
  Some({
    bytes: Int64::min(bytes, declaration_limits.max_bytes.to_int64()).to_int(),
    units: Int64::min(units, declaration_limits.max_bytes.to_int64()).to_int(),
    nodes: Int64::min(nodes, declaration_limits.max_nodes.to_int64()).to_int(),
    depth,
  })
}

///|
pub fn row_update_mapping_construction_capacity(
  declaration : RowDeclaration,
  writes_json : String,
  resource : String,
  sources_json : String,
) -> @execution.ExecutionCapacity? {
  guard declaration.views.length() <= declaration_limits.max_views &&
    declaration.view_bodies.length() == declaration.views.length() &&
    declaration.contracts.length() <= declaration_limits.max_nodes &&
    relation_restore_wire_geometry(writes_json) is Some(writes) &&
    relation_restore_wire_geometry(sources_json) is Some(sources) else {
    return None
  }
  let parts = []
  // The bridge's preserving Source check and stdlib source-map parse, followed
  // by mapping_read_original's Source/index and stdlib writes tree coexist.
  for original in [sources, writes] {
    if !relation_restore_add(parts, relation_restore_source(original, true)) ||
      !relation_restore_add(parts, relation_restore_raw_json(original)) {
      return None
    }
  }
  let mut selected : RelationRestoreWireGeometry? = None
  for index, view in declaration.views {
    guard update_mapping_original_geometry(
        declaration,
        declaration.view_bodies[index],
      )
      is Some(geometry) &&
      relation_document_mapping_construction_inventory({
        max_bytes: Int::max(1, geometry.bytes),
        max_nodes: geometry.nodes,
        max_depth: geometry.depth,
        max_rows: 0,
      })
      is Some(validation) else {
      return None
    }
    // UPDATE validates every sibling's original schema before selection.
    // Count every possible original View, even if not named by the writes.
    // Do not multiply a full Declaration export or Environment per Mapping.
    parts.push(validation)
    if view.resource == resource {
      selected = Some(geometry)
    }
  }
  let geometry = selected.unwrap_or({ bytes: 0, units: 0, nodes: 1, depth: 1, })
  // The selected Mapping constructor reads its original relation once more.
  if selected is Some(_) &&
    !relation_restore_add(
      parts,
      relation_document_mapping_construction_inventory({
        max_bytes: Int::max(1, geometry.bytes),
        max_nodes: geometry.nodes,
        max_depth: geometry.depth,
        max_rows: 0,
      }),
    ) {
    return None
  }
  let input_nodes = geometry.nodes.to_int64() +
    writes.nodes.to_int64() +
    sources.nodes.to_int64()
  guard @scalar.admit_utf8_length(
      declaration.connector_id,
      declaration_limits.max_bytes,
    )
    is Ok(connector_bytes) &&
    @scalar.admit_utf8_length(
      declaration.connector_registration,
      declaration_limits.max_bytes,
    )
    is Ok(registration_bytes) &&
    @scalar.admit_utf8_length(
      declaration.connector_version,
      declaration_limits.max_bytes,
    )
    is Ok(version_bytes) &&
    @scalar.admit_utf8_length(resource, declaration_limits.max_bytes)
    is Ok(resource_bytes) else {
    return None
  }
  let names = connector_bytes.to_int64() +
    registration_bytes.to_int64() +
    version_bytes.to_int64() +
    resource_bytes.to_int64()
  // Schema emission and fixed Mapping/request/identity envelopes; source-map
  // fields and two copied/sorted field arrays. Escaping and finite numeric
  // spelling are bounded independently of the installed facility ceiling.
  let body_nodes = 256L + 12L * input_nodes
  let body_units = 4096L +
    6L *
    (
      geometry.bytes.to_int64() +
      writes.bytes.to_int64() +
      sources.bytes.to_int64() +
      names
    ) +
    25L * body_nodes
  // UTF8 byte extents bound emitted bytes and retained UTF16 units; Unicode
  // source/identity names must not be priced as ASCII code units.
  let metadata_units = 2048L + 6L * body_units + 6L * sources.bytes.to_int64()
  let depth = Int::min(declaration_limits.max_depth, geometry.depth + 8)
  // Pre/post-seal Mapping trees, checked target schema, source descriptors,
  // written/required/omittable arrays, identity strings and returned metadata
  // coexist. Their borrowed declaration backing stays with its original owner.
  guard relation_construction_json_forest(3L * body_nodes) is Some(trees) &&
    relation_construction_writer_units(
      Int64::min(body_units, declaration_limits.max_bytes.to_int64()).to_int(),
      Int64::min(body_nodes, declaration_limits.max_nodes.to_int64()).to_int(),
      depth,
    )
    is Some(schema_writer) &&
    relation_restore_canonical({
      bytes: Int64::min(body_units, declaration_limits.max_bytes.to_int64()).to_int(),
      units: Int64::min(body_units, declaration_limits.max_bytes.to_int64()).to_int(),
      nodes: Int64::min(body_nodes, declaration_limits.max_nodes.to_int64()).to_int(),
      depth,
    })
    is Some(canonical) &&
    relation_restore_emission(body_units, body_nodes, depth, true)
    is Some(writer) else {
    return None
  }
  parts.push(relation_construction_collection_units(trees))
  parts.push(schema_writer)
  parts.push(canonical)
  parts.push(writer)
  // canonical_cid returns only its digest. Each request/identity/schema hash
  // and final body writer has returned before the next is invoked; one worst
  // writer above covers them, while ALL persistent trees/strings remain here.
  // This synchronous logical-lifetime cut is not a GC/physical cleanup ACK.
  parts.push({
    record_headers: 96L + 8L * input_nodes,
    reference_slots: 256L + 24L * input_nodes,
    scalar_words: 96L + 8L * input_nodes,
    owned_utf16_units: 3L * body_units + 6L * metadata_units,
    owned_wire_bytes: body_units + metadata_units,
  })
  // Node parses the returned metadata and Mapping body to retain target_ref.
  // Its temporary parsed body is workspace; the returned wrapper/field arrays
  // and actual Mapping body remain retained after the synchronous call.
  guard relation_construction_json_forest(2L * body_nodes) is Some(node_trees) else {
    return None
  }
  parts.push(relation_construction_collection_units(node_trees))
  let retained : @execution.PreparationRepresentationUnits = {
    record_headers: 16L + 2L * sources.nodes.to_int64(),
    reference_slots: 32L + 4L * sources.nodes.to_int64(),
    scalar_words: 8L,
    owned_utf16_units: body_units +
    6L * sources.bytes.to_int64() +
    names +
    1024L,
    owned_wire_bytes: 0L,
  }
  guard @execution.compose_preparation_representation(parts) is Some(workspace) &&
    @execution.preparation_representation_cost(retained) is Some(r) &&
    @execution.compose_preparation_representation([retained, workspace])
    is Some(peak) &&
    @execution.preparation_representation_cost(peak) is Some(e) else {
    return None
  }
  @execution.execution_capacity(r, e)
}
