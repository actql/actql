///|
// Geometry DATA of an already retained String. This scan neither parses JSON
// nor decodes nested strings. Punctuation inside strings deliberately counts
// too, so malformed input and detached JSON cannot understate the node bound.
priv struct RelationRestoreWireGeometry {
  bytes : Int
  units : Int
  nodes : Int
  depth : Int
}

///|
fn relation_restore_wire_geometry(
  wire : String,
) -> RelationRestoreWireGeometry? {
  guard @scalar.admit_utf8_length(wire, declaration_limits.max_bytes)
    is Ok(bytes) else {
    return None
  }
  let mut nodes = 1
  let mut depth = 0
  let mut maximum = 0
  let mut quoted = false
  let mut escaped = false
  for index in 0..<wire.length() {
    let unit = wire.code_unit_at(index).to_int()
    if unit == 123 || unit == 91 {
      nodes = Int::min(declaration_limits.max_nodes, nodes + 2)
    } else if unit == 58 || unit == 44 || unit == 92 {
      nodes = Int::min(declaration_limits.max_nodes, nodes + 1)
    }
    if quoted {
      if escaped {
        escaped = false
      } else if unit == 92 {
        escaped = true
      } else if unit == 34 {
        quoted = false
      }
    } else if unit == 34 {
      quoted = true
    } else if unit == 123 || unit == 91 {
      depth += 1
      maximum = Int::max(maximum, depth)
    } else if unit == 125 || unit == 93 {
      depth = Int::max(0, depth - 1)
    }
  }
  Some({
    bytes,
    units: wire.length(),
    nodes,
    depth: Int::min(declaration_limits.max_depth, Int::max(1, maximum)),
  })
}

///|
fn relation_restore_add(
  parts : Array[@execution.PreparationRepresentationUnits],
  value : @execution.PreparationRepresentationUnits?,
) -> Bool {
  match value {
    Some(value) => {
      parts.push(value)
      true
    }
    None => false
  }
}

///|
fn relation_restore_scale(
  value : @execution.PreparationRepresentationUnits,
  count : Int64,
) -> @execution.PreparationRepresentationUnits? {
  if count < 0L ||
    value.record_headers < 0L ||
    value.reference_slots < 0L ||
    value.scalar_words < 0L ||
    value.owned_utf16_units < 0L ||
    value.owned_wire_bytes < 0L {
    return None
  }
  // The shared arithmetic takes a nonnegative count and positive coefficient.
  // Representation components may be zero; they belong in its count operand.
  if count == 0L {
    return @execution.compose_preparation_representation([])
  }
  guard @execution.checked_preparation_add_product(
      0L,
      value.record_headers,
      count,
    )
    is Some(record_headers) &&
    @execution.checked_preparation_add_product(0L, value.reference_slots, count)
    is Some(reference_slots) &&
    @execution.checked_preparation_add_product(0L, value.scalar_words, count)
    is Some(scalar_words) &&
    @execution.checked_preparation_add_product(
      0L,
      value.owned_utf16_units,
      count,
    )
    is Some(owned_utf16_units) &&
    @execution.checked_preparation_add_product(
      0L,
      value.owned_wire_bytes,
      count,
    )
    is Some(owned_wire_bytes) else {
    return None
  }
  Some({
    record_headers,
    reference_slots,
    scalar_words,
    owned_utf16_units,
    owned_wire_bytes,
  })
}

///|
fn relation_restore_shape_validator(
  geometry : RelationRestoreWireGeometry,
) -> @execution.PreparationRepresentationUnits? {
  @environment.source_view_shape_validation_construction_extent(
    geometry.nodes,
    geometry.nodes,
    geometry.nodes,
    geometry.depth,
  ).map(relation_construction_collection_units)
}

///|
fn relation_restore_source(
  geometry : RelationRestoreWireGeometry,
  indexed : Bool,
) -> @execution.PreparationRepresentationUnits? {
  if indexed {
    return relation_construction_decoded_construction(
      Int::max(1, geometry.bytes),
      geometry.nodes,
      geometry.depth,
      true,
    )
  }
  guard @source.json_construction_extent(
      Int::max(1, geometry.bytes),
      geometry.nodes,
      geometry.depth,
      normalize_keys=true,
    )
    is Some(value) else {
    return None
  }
  Some({
    record_headers: value.record_headers,
    reference_slots: value.reference_slots,
    scalar_words: value.scalar_words,
    owned_utf16_units: value.owned_utf16_units,
    owned_wire_bytes: 0L,
  })
}

///|
// The pinned stdlib parser creates Json values, numeric spelling Options,
// Maps/arrays and decoded literals. It does not construct a Source/index.
fn relation_restore_raw_json(
  geometry : RelationRestoreWireGeometry,
) -> @execution.PreparationRepresentationUnits? {
  guard row_contract_raw_json_shape(geometry.nodes.to_int64()) is Some(tree) &&
    @shape.collection_construction_extent({
      records: 12L + 3L * geometry.depth.to_int64(),
      record_references: 10L + 4L * geometry.depth.to_int64(),
      record_words: 16L + 4L * geometry.depth.to_int64(),
      reference_arrays: 0L,
      reference_items: 0L,
      scalar_arrays: 2L,
      scalar_items: 3L * geometry.units.to_int64() + 24L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(controls) else {
    return None
  }
  @execution.compose_preparation_representation([
    relation_construction_collection_units(tree),
    relation_construction_collection_units(controls),
    {
      record_headers: 2L * geometry.nodes.to_int64(),
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: 3L * geometry.units.to_int64() + 24L,
      owned_wire_bytes: 0L,
    },
  ])
}

///|
// Both canonical from_source and from_json own a frozen forest, normalized
// member names, duplicate-key Maps and traversal/sort controls. Data Strings
// borrow the original parser backing already counted by their constructor.
fn relation_restore_canonical(
  geometry : RelationRestoreWireGeometry,
) -> @execution.PreparationRepresentationUnits? {
  guard relation_construction_json_forest(geometry.nodes.to_int64())
    is Some(tree) &&
    @canonical.nfc_lf_construction_extent(geometry.units) is Some(keys) &&
    @shape.collection_construction_extent({
      records: 12L + 5L * geometry.depth.to_int64(),
      record_references: 24L + 12L * geometry.depth.to_int64(),
      record_words: 12L + 6L * geometry.depth.to_int64(),
      reference_arrays: 3L,
      reference_items: geometry.nodes.to_int64() +
      4L * geometry.depth.to_int64(),
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
    {
      record_headers: keys.record_headers + geometry.nodes.to_int64(),
      reference_slots: keys.reference_slots,
      scalar_words: keys.scalar_words,
      owned_utf16_units: keys.owned_utf16_units + keys.max_output_utf16_units,
      owned_wire_bytes: 0L,
    },
  ])
}

///|
fn relation_restore_emission(
  bytes : Int64,
  nodes : Int64,
  depth : Int,
  hash : Bool,
) -> @execution.PreparationRepresentationUnits? {
  let bytes = Int64::min(bytes, declaration_limits.max_bytes.to_int64()).to_int()
  let nodes = Int64::min(nodes, declaration_limits.max_nodes.to_int64()).to_int()
  let depth = Int::min(depth, declaration_limits.max_depth)
  guard relation_construction_writer_units(
      Int::max(0, bytes),
      Int::max(1, nodes),
      depth,
    )
    is Some(writer) else {
    return None
  }
  if !hash {
    return Some(writer)
  }
  guard @encode.hash_writer_construction_inventory(Int::max(1, nodes), depth)
    is Some(hasher) else {
    return None
  }
  @execution.compose_preparation_representation([
    writer,
    {
      record_headers: hasher.record_headers,
      reference_slots: hasher.reference_slots,
      scalar_words: hasher.scalar_words,
      owned_utf16_units: hasher.owned_utf16_units,
      owned_wire_bytes: hasher.owned_wire_bytes,
    },
  ])
}

///|
fn relation_restore_canonical_bytes(
  value : RelationRestoreWireGeometry,
) -> Int64 {
  // JSON escaping is at most six units per original unit; finite Double text
  // is at most 25. A failed bounded emitter cannot retain more than its limit.
  Int64::min(
    declaration_limits.max_bytes.to_int64(),
    6L * value.bytes.to_int64() + 25L * value.nodes.to_int64(),
  )
}

///|
fn relation_restore_body(
  parts : Array[@execution.PreparationRepresentationUnits],
  value : RelationRestoreWireGeometry,
  request_contract : Bool,
) -> Bool {
  // Source+index; stdlib Json; canonical tree; measuring writer; canonical
  // text writer; stdlib canonical-body reconstruction all remain co-counted.
  let output = relation_restore_canonical_bytes(value)
  let emitted = { ..value, bytes: output.to_int(), units: output.to_int(), }
  if !relation_restore_add(parts, relation_restore_source(value, true)) ||
    !relation_restore_add(parts, relation_restore_raw_json(value)) ||
    !relation_restore_add(parts, relation_restore_canonical(value)) ||
    !relation_restore_add(
      parts,
      relation_restore_emission(
        output,
        value.nodes.to_int64(),
        value.depth,
        false,
      ),
    ) ||
    !relation_restore_add(
      parts,
      relation_restore_emission(
        output,
        value.nodes.to_int64(),
        value.depth,
        false,
      ),
    ) ||
    !relation_restore_add(parts, relation_restore_raw_json(emitted)) {
    return false
  }
  !request_contract ||
  relation_restore_add(
    parts,
    relation_construction_contract_units(value.nodes, value.units, value.depth),
  )
}

///|
/// One original full Relation restore and its DeclarationJson export. All
/// borrowed arrays/Strings must be the saved descriptors of that same call.
/// This quantity is DATA, not admission or proof that descriptors match wire.
/// No JSON parse, nested-string decode, canonicalization or hash is performed.
/// The existing fixed restore limits and every failed constructor prefix are
/// included; repeated initial/final/physical restores must be added by caller.
pub fn relation_restore_construction_inventory(
  connector_id : String,
  registration : String,
  version : String,
  views_wire : String,
  resources : Array[String],
  resource_kinds : Array[String],
  schema_wires : Array[String],
  request_wires : Array[String?],
  facts_wires : Array[String?],
  acquisition_wires : Array[String?],
  identity_wires : Array[String?],
) -> @execution.PreparationRepresentationUnits? {
  let count = resources.length()
  if count < 1 ||
    count > declaration_limits.max_views ||
    resource_kinds.length() != count ||
    schema_wires.length() != count ||
    request_wires.length() != count ||
    facts_wires.length() != count ||
    acquisition_wires.length() != count ||
    identity_wires.length() != count ||
    connector_id.length() > 128 ||
    registration.length() > 64 ||
    version.length() > declaration_limits.max_bytes {
    return None
  }
  guard relation_restore_wire_geometry(views_wire) is Some(outer) else {
    return None
  }
  let parts = []
  if !relation_restore_add(parts, relation_restore_source(outer, true)) ||
    !relation_restore_add(parts, relation_restore_raw_json(outer)) {
    return None
  }
  let cid = 71L
  let connector = connector_id.length().to_int64()
  let revision = version.length().to_int64()
  let mut catalog_bytes = "{\"schema\":\"actql.connector_catalog/0.1\",\"connector_id\":\"\",\"connector_version\":\"\",\"source_views\":[],\"commands\":[],\"contracts\":[],\"catalog_cid\":\"\"}"
    .length()
    .to_int64() +
    6L * (connector + revision + cid)
  let mut catalog_nodes = 8L
  let mut input_bytes = 0L
  let mut field_count = 0L
  let mut export_text = connector +
    registration.length().to_int64() +
    revision +
    2L * cid
  let mut generated_names = 0L
  let mut largest_depth = 1
  for index in 0..<count {
    if resources[index].length() > 255 || resource_kinds[index].length() > 64 {
      return None
    }
    guard relation_restore_wire_geometry(schema_wires[index]) is Some(schema) &&
      relation_restore_wire_geometry(
        request_wires[index].unwrap_or(
          "{\"type\":\"object\",\"nullable\":false,\"additional_properties\":false,\"fields\":{}}",
        ),
      )
      is Some(request) &&
      relation_restore_wire_geometry(facts_wires[index].unwrap_or("{}"))
      is Some(facts) else {
      return None
    }
    input_bytes += schema.bytes.to_int64() +
      request.bytes.to_int64() +
      facts.bytes.to_int64()
    // The descriptor name output cannot exceed its original schema String.
    // Field admission happens before the final max_fields rejection. The
    // failed prefix can construct every input field, not only 1024 outputs.
    let fields = schema.nodes.to_int64()
    field_count += fields
    largest_depth = Int::max(
      largest_depth,
      Int::max(schema.depth, Int::max(request.depth, facts.depth)),
    )
    // validate_result_schema_wire: distinct Source parser, canonical tree,
    // SHA/text writers. The actual schema reader then parses/indexes again.
    if !relation_restore_add(parts, relation_restore_source(schema, false)) ||
      !relation_restore_add(parts, relation_restore_canonical(schema)) ||
      !relation_restore_add(
        parts,
        relation_restore_emission(
          relation_restore_canonical_bytes(schema),
          schema.nodes.to_int64(),
          schema.depth,
          true,
        ),
      ) ||
      !relation_restore_add(parts, relation_restore_source(schema, true)) ||
      !relation_restore_add(parts, relation_restore_raw_json(schema)) ||
      !relation_restore_add(parts, relation_restore_canonical(schema)) ||
      !relation_restore_add(
        parts,
        relation_restore_emission(
          relation_restore_canonical_bytes(schema),
          schema.nodes.to_int64(),
          schema.depth,
          false,
        ),
      ) ||
      !relation_restore_add(
        parts,
        relation_construction_contract_units(
          schema.nodes,
          schema.units,
          schema.depth,
        ),
      ) ||
      !relation_restore_body(parts, request, true) ||
      !relation_restore_body(parts, facts, false) {
      return None
    }
    // Each original field has its own read_checked_usage call. The aggregate
    // tree covers node-dependent work; add each call's fixed/path controls.
    guard relation_construction_contract_units(1, 0, schema.depth)
      is Some(per_field) &&
      relation_restore_scale(per_field, fields) is Some(field_controls) else {
      return None
    }
    parts.push(field_controls)
    guard @schema.unqualified_presence_construction_inventory(
        fields.to_int(),
        schema.units,
      )
      is Some(schema_assembly) else {
      return None
    }
    parts.push(relation_construction_collection_units(schema_assembly.retained))
    parts.push(relation_construction_collection_units(schema_assembly.scratch))
    parts.push({
      record_headers: 0L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: schema_assembly.scratch_utf16_units,
      owned_wire_bytes: 0L,
    })
    let resource = resources[index].length().to_int64()
    let kind = resource_kinds[index].length().to_int64()
    let id = connector + resource + "/records/pushdown".length().to_int64() + 1L
    let source_ref = connector +
      resource +
      "connector:///#records".length().to_int64()
    let reference = "{\"id\":\"\",\"version\":\"\",\"cid\":\"\"}"
      .length()
      .to_int64() +
      6L * (id + revision + cid)
    let policy = "{\"version\":\"actql-source-data-policy/0.1\",\"source_ref\":\"\",\"classification\":\"confidential\"}"
      .length()
      .to_int64() +
      6L * source_ref
    let pushdown = "{\"version\":\"actql-source-view-pushdown/0.1\",\"carrier\":\"relation\",\"operations\":[\"projection\"]}"
      .length()
      .to_int64()
    let envelope_base = "{\"schema\":\"actql.contract/0.1\",\"id\":\"\",\"version\":\"\",\"kind\":\"\",\"body\":{},\"cid\":\"\"}"
      .length()
      .to_int64() -
      2L +
      6L * (id + revision + cid + 16L)
    let carrier_bytes = relation_restore_canonical_bytes(schema) +
      "{\"fields\":{},\"version\":\"actql-relation-schema/0.1\"}"
      .length()
      .to_int64() -
      2L
    let envelope_bodies = [
      (relation_restore_canonical_bytes(request), request.nodes.to_int64()),
      (carrier_bytes, schema.nodes.to_int64() + 2L),
      (relation_restore_canonical_bytes(facts), facts.nodes.to_int64()),
      (policy, 4L),
      (pushdown, 5L),
    ]
    for (body_bytes, body_nodes) in envelope_bodies {
      let bytes = envelope_base + body_bytes
      let nodes = 6L + body_nodes
      catalog_bytes += bytes + 1L
      catalog_nodes += nodes
      export_text += Int64::min(bytes, declaration_limits.max_bytes.to_int64())
      if !relation_restore_add(
          parts,
          relation_restore_emission(bytes, nodes, largest_depth + 2, true),
        ) {
        return None
      }
    }
    let mut acquisition_bytes = "{\"default_mode\":\"snapshot\",\"request_schema\":{},\"modes\":[{\"bounded\":true,\"mode\":\"snapshot\"}],\"kind\":\"scan\",\"authority\":\"read_content\"}"
      .length()
      .to_int64() -
      2L +
      reference
    let mut acquisition_nodes = 12L
    if acquisition_wires[index] is Some(wire) {
      guard relation_restore_wire_geometry(wire) is Some(value) else {
        return None
      }
      input_bytes += value.bytes.to_int64()
      largest_depth = Int::max(largest_depth, value.depth)
      if !relation_restore_body(parts, value, false) {
        return None
      }
      acquisition_bytes += relation_restore_canonical_bytes(value)
      acquisition_nodes += value.nodes.to_int64()
    }
    let acquisition_geometry = {
      bytes: Int64::min(
        acquisition_bytes,
        declaration_limits.max_bytes.to_int64(),
      ).to_int(),
      units: Int64::min(
        acquisition_bytes,
        declaration_limits.max_bytes.to_int64(),
      ).to_int(),
      nodes: Int64::min(
        acquisition_nodes,
        declaration_limits.max_nodes.to_int64(),
      ).to_int(),
      depth: Int::min(largest_depth + 2, declaration_limits.max_depth),
    }
    if !relation_restore_add(
        parts,
        relation_restore_emission(
          acquisition_bytes,
          acquisition_nodes,
          largest_depth + 2,
          false,
        ),
      ) ||
      !relation_restore_add(
        parts,
        relation_restore_source(acquisition_geometry, true),
      ) ||
      !relation_restore_add(
        parts,
        relation_restore_shape_validator(acquisition_geometry),
      ) {
      return None
    }
    let mut identity_bytes = 0L
    let mut identity_nodes = 0L
    if identity_wires[index] is Some(wire) {
      guard relation_restore_wire_geometry(wire) is Some(value) else {
        return None
      }
      input_bytes += value.bytes.to_int64()
      largest_depth = Int::max(largest_depth, value.depth)
      if !relation_restore_body(parts, value, false) ||
        !relation_restore_add(parts, relation_restore_shape_validator(value)) {
        return None
      }
      identity_bytes = relation_restore_canonical_bytes(value) +
        "\"resource_identity\":".length().to_int64() +
        1L
      identity_nodes = value.nodes.to_int64()
    }
    let view_bytes = "{\"schema\":\"actql.source_view/0.1\",\"connector_id\":\"\",\"connector_version\":\"\",\"resource_kind\":\"\",\"view_id\":\"records\",\"view_version\":\"\",\"acquisition\":{},\"request_processing\":{\"mutates_business_state\":false},\"output\":{\"carrier\":\"relation\",\"schema\":{},\"facts\":{},\"data_policy\":{}},\"pushdown\":{\"contract\":{},\"operations\":[\"projection\"]},\"contract_cid\":\"\"}"
      .length()
      .to_int64() -
      10L +
      acquisition_bytes +
      4L * reference +
      identity_bytes +
      6L * (connector + 2L * revision + kind + cid)
    let view_nodes = 43L + acquisition_nodes + identity_nodes
    catalog_bytes += view_bytes + 1L
    catalog_nodes += view_nodes
    export_text += Int64::min(
        view_bytes,
        declaration_limits.max_bytes.to_int64(),
      ) +
      resource +
      source_ref +
      3L * cid +
      schema.units.to_int64()
    generated_names += 5L * (id + revision + cid) + source_ref
    if !relation_restore_add(
        parts,
        relation_restore_emission(
          view_bytes,
          view_nodes,
          largest_depth + 3,
          true,
        ),
      ) {
      return None
    }
    // Existing evidence export has two separately bounded fixed writers/view.
    for _ in 0..<2 {
      if !relation_restore_add(
          parts,
          relation_construction_writer_units(4096, 64, 8),
        ) {
        return None
      }
      export_text += 4096L
    }
  }
  // The actual saved outer wire already contains all explicit inner bodies.
  // Defaults add at most these two literal bodies per view. This bound prevents
  // an unrelated descriptor array from making quoting itself unbounded work.
  if input_bytes >
    declaration_limits.max_bytes.to_int64() + 96L * count.to_int64() {
    return None
  }
  let manifest = "{\"connector\":\"\",\"connector_id\":\"\",\"connector_version\":\"\"}"
    .length()
    .to_int64() +
    6L * (connector + registration.length().to_int64() + revision)
  if !relation_restore_add(
      parts,
      relation_restore_emission(
        catalog_bytes,
        catalog_nodes,
        largest_depth + 4,
        true,
      ),
    ) ||
    !relation_restore_add(
      parts,
      relation_restore_emission(manifest, 4L, 1, true),
    ) {
    return None
  }
  export_text += Int64::min(
      catalog_bytes,
      declaration_limits.max_bytes.to_int64(),
    ) +
    Int64::min(manifest, declaration_limits.max_bytes.to_int64())
  let view_count = count.to_int64()
  let export_nodes = 13L + 16L * view_count + field_count
  let export_bytes = 6L * export_text +
    512L +
    256L * view_count +
    3L * field_count
  if export_bytes > 2147483647L || catalog_nodes > 2147483647L {
    return None
  }
  // Assembly precedes bounded writers. Pre/post-CID seal objects, envelopes,
  // references, Catalog and export Json cannot be capped at writer limits.
  guard relation_construction_json_forest(2L * catalog_nodes + export_nodes)
    is Some(assembled) &&
    @shape.collection_construction_extent({
      // Saved-spec/optional/classification arrays; typed geometry and inventory
      // records created while quoting; RowField/RowDeclaredView descriptors;
      // ordering/index tuples, callback controls and their array growth.
      records: 32L + 128L * view_count + 8L * field_count,
      record_references: 64L + 256L * view_count + 16L * field_count,
      record_words: 32L + 128L * view_count + 8L * field_count,
      reference_arrays: 24L + 16L * view_count,
      reference_items: 64L + 128L * view_count + 8L * field_count,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 2L * view_count,
      map_entries: field_count,
    })
    is Some(controls) &&
    // Pinned Json.stringify uses an explicit WriteFrame stack and one
    // StringBuilder, not recursive per-subtree rendered Strings. Add its raw
    // iterator/Some frames to the existing conservative text-writer backing.
    relation_construction_writer_units(
      export_bytes.to_int(),
      export_nodes.to_int(),
      4,
    )
    is Some(export_writer) else {
    return None
  }
  parts.push(relation_construction_collection_units(assembled))
  parts.push(relation_construction_collection_units(controls))
  parts.push(export_writer)
  parts.push({
    record_headers: 24L,
    reference_slots: 48L,
    scalar_words: 32L,
    owned_utf16_units: generated_names + export_text,
    owned_wire_bytes: 0L,
  })
  @execution.compose_preparation_representation(parts)
}
