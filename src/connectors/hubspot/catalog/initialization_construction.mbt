///|
fn initialization_collection_units(
  value : @shape.CollectionConstructionExtent,
) -> @execution.PreparationRepresentationUnits {
  {
    record_headers: value.record_headers,
    reference_slots: value.reference_slots,
    scalar_words: value.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
}

///|
// One Catalog output model for both Source initialization and Effect metadata.
// Parser/index/sort/schema-writer forests do not escape with these originals.
fn property_catalog_retained_units(
  body_bytes : Int,
  object_units : Int,
  limits : PropertyLimits,
) -> @execution.PreparationRepresentationUnits {
  let n = Int::min(Int::max(1, body_bytes), limits.max_nodes).to_int64()
  let f = Int64::min(n, limits.max_properties.to_int64())
  {
    record_headers: 8L + 4L * f + n,
    reference_slots: 16L + 8L * f + 2L * n,
    scalar_words: 8L + 4L * f,
    owned_utf16_units: body_bytes.to_int64() + object_units.to_int64() + 64L,
    owned_wire_bytes: 0L,
  }
}

///|
// The preserving metadata parser and normalizing schema parser are distinct
// original operations. This inventory neither parses nor admits their input.
fn initialization_decoded_construction(
  bytes : Int,
  nodes : Int,
  depth : Int,
  normalize_keys : Bool,
) -> @execution.PreparationRepresentationUnits? {
  guard @source.json_construction_extent(bytes, nodes, depth, normalize_keys~)
    is Some(parsed) &&
    @decode.admission_construction_inventory(nodes, nodes, nodes, nodes, depth)
    is Some(index) else {
    return None
  }
  Some({
    record_headers: parsed.record_headers +
    index.indexed.record_headers +
    index.keys.record_headers +
    index.ancestry.record_headers +
    index.controls.record_headers,
    reference_slots: parsed.reference_slots +
    index.indexed.reference_slots +
    index.keys.reference_slots +
    index.ancestry.reference_slots +
    index.controls.reference_slots,
    scalar_words: parsed.scalar_words +
    index.indexed.scalar_words +
    index.keys.scalar_words +
    index.ancestry.scalar_words +
    index.controls.scalar_words,
    owned_utf16_units: parsed.owned_utf16_units,
    owned_wire_bytes: 0L,
  })
}

///|
fn initialization_writer_units(
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> @execution.PreparationRepresentationUnits? {
  guard @encode.text_writer_construction_inventory(bytes, nodes, depth)
    is Some(writer) else {
    return None
  }
  Some({
    record_headers: writer.record_headers,
    reference_slots: writer.reference_slots,
    scalar_words: writer.scalar_words,
    owned_utf16_units: writer.owned_utf16_units,
    owned_wire_bytes: 0L,
  })
}

///|
fn initialization_capacity(
  parts : Array[@execution.PreparationRepresentationUnits],
) -> @execution.ExecutionCapacity? {
  guard @execution.compose_preparation_representation(parts) is Some(peak) else {
    return None
  }
  @execution.preparation_execution_capacity({
    retained: peak,
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
/// Account response projection/recheck and its fixed native JSON export. Input
/// Bytes/base64 comparison are included; credential/physical Site are not.
pub fn account_initialization_construction_capacity(
  body_bytes : Int,
  encoded_units : Int,
  portal_units : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @execution.ExecutionCapacity? {
  if body_bytes < 0 ||
    encoded_units < 0 ||
    portal_units < 0 ||
    max_bytes < 1 ||
    body_bytes > max_bytes ||
    max_nodes < 1 ||
    max_depth < 1 {
    return None
  }
  let b = Int::max(1, body_bytes)
  let n = Int::min(b, max_nodes)
  guard initialization_decoded_construction(b, n, max_depth, false)
    is Some(parsed) &&
    @shape.collection_construction_extent({
      // One account ObjectView/Map, lookup cursor/Options and integer/decimal
      // Results; identity/recheck outcomes, fixed account-or-refusal export.
      records: 48L,
      record_references: 64L,
      record_words: 48L,
      reference_arrays: 8L,
      reference_items: 32L,
      // Decimal normalization digit builder and old/new backing; lexeme copy
      // and final canonical coefficient remain separate text units below.
      scalar_arrays: 2L,
      scalar_items: 3L * b.to_int64() + 32L,
      maps: 4L,
      map_entries: n.to_int64() + 8L,
    })
    is Some(account) &&
    @encode.hash_writer_live_key_inventory(0, 0) is Some(hash) &&
    initialization_writer_units(256, 8, 3) is Some(exported) else {
    return None
  }
  initialization_capacity([
    parsed,
    initialization_collection_units(account),
    exported,
    {
      record_headers: hash.record_headers,
      reference_slots: hash.reference_slots,
      scalar_words: hash.scalar_words,
      owned_utf16_units: hash.owned_utf16_units +
      4L * b.to_int64() +
      encoded_units.to_int64() +
      portal_units.to_int64() +
      256L,
      owned_wire_bytes: hash.owned_wire_bytes + body_bytes.to_int64(),
    },
  ])
}

///|
/// ProjectProperties + names snapshot + ObjectSchemaWire for ONE original
/// properties body. Aggregate options belong to its input N, not F*N. The
/// native catalog stays in the provider runtime; only its schema DATA crosses
/// to the separately funded common declaration restore. No parse occurs here.
pub fn object_initialization_construction_capacity(
  body_bytes : Int,
  encoded_units : Int,
  object_units : Int,
  limits : PropertyLimits,
  max_columns : Int,
  max_name_bytes : Int,
  max_schema_bytes : Int,
  max_schema_nodes : Int,
  max_schema_depth : Int,
) -> @execution.ExecutionCapacity? {
  guard object_initialization_peak_capacity(
      body_bytes, encoded_units, object_units, limits, max_columns, max_name_bytes,
      max_schema_bytes, max_schema_nodes, max_schema_depth,
    )
    is Some((peak, schema_bytes)) else {
    return None
  }
  let n = Int::min(Int::max(1, body_bytes), limits.max_nodes).to_int64()
  let f = Int64::min(n, limits.max_properties.to_int64())
  guard @execution.compose_preparation_representation([
      property_catalog_retained_units(body_bytes, object_units, limits),
      {
        // Host result/view/Buffer records and the copied names Array escape.
        // The Array and view borrow the Catalog names and schema String.
        record_headers: 8L,
        reference_slots: 24L + f,
        scalar_words: 8L,
        owned_utf16_units: schema_bytes.to_int64() + 71L,
        owned_wire_bytes: body_bytes.to_int64(),
      },
    ])
    is Some(output) &&
    hubspot_effect_capacity(output, []) is Some(retained) &&
    @execution.add_execution_capacity(
      retained,
      @execution.execution_capacity(
        0L,
        @execution.execution_capacity_execution_bytes(peak),
      ).unwrap(),
    )
    is Some(result) else {
    return None
  }
  // The existing parent composer holds this complete peak until the original
  // successful-return cut selects retained-only. Failure never spends it.
  Some(result)
}

///|
// Preserve the complete old constructor peak, including malformed prefixes.
// The schema extent is the same already-computed output bound, not another
// parse, copied String or a maximum newly treated as initialized storage.
fn object_initialization_peak_capacity(
  body_bytes : Int,
  encoded_units : Int,
  object_units : Int,
  limits : PropertyLimits,
  max_columns : Int,
  max_name_bytes : Int,
  max_schema_bytes : Int,
  max_schema_nodes : Int,
  max_schema_depth : Int,
) -> (@execution.ExecutionCapacity, Int)? {
  if body_bytes < 0 ||
    encoded_units < 0 ||
    object_units < 0 ||
    limits.max_bytes < 1 ||
    body_bytes > limits.max_bytes ||
    limits.max_nodes < 1 ||
    limits.max_depth < 1 ||
    limits.max_properties < 1 ||
    limits.max_name_units < 1 ||
    max_columns < 1 ||
    max_name_bytes < 1 ||
    max_schema_bytes < 1 ||
    max_schema_nodes < 1 ||
    max_schema_depth < 1 {
    return None
  }
  let b = Int::max(1, body_bytes)
  let n = Int::min(b, limits.max_nodes)
  let f = Int::min(n, limits.max_properties)
  if f > 1073741822 {
    return None
  }
  // Number's fixed38/10 decimal has five JSON nodes; checkbox emits an array
  // with three-node String item (six total). All other carriers have three.
  let primitive = "{\"nullable\":false,\"type\":\"timestamp\"}"
    .length()
    .to_int64()
  let decimal = "{\"nullable\":true,\"precision\":38,\"scale\":10,\"type\":\"decimal\"}"
    .length()
    .to_int64()
  let array = "{\"items\":{},\"nullable\":true,\"type\":\"array\"}"
    .length()
    .to_int64() -
    2L +
    primitive
  let sb = Int64::min(
    max_schema_bytes.to_int64(),
    2L +
    primitive +
    5L +
    6L * body_bytes.to_int64() +
    f.to_int64() * (Int64::max(decimal, array) + 4L),
  ).to_int()
  let sn = Int64::min(max_schema_nodes.to_int64(), 4L + 6L * f.to_int64()).to_int()
  let child = @decode.indexed_child_construction_extent()
  guard initialization_decoded_construction(b, n, limits.max_depth, true)
    is Some(parsed) &&
    @shape.collection_construction_extent({
      // PropertyMetadata1H6R; scalar text/flag/Presence/Some/Result families
      // <=32H40R32W per property. Each option owns view/lookup/text outcomes
      // <=8H10R8W. Counts co-cover malformed prefixes and modificationMetadata.
      records: 16L +
      33L * f.to_int64() +
      8L * n.to_int64() +
      child.record_headers * (10L * f.to_int64() + 3L * n.to_int64() + 4L),
      record_references: 24L +
      46L * f.to_int64() +
      10L * n.to_int64() +
      child.reference_slots * (10L * f.to_int64() + 3L * n.to_int64() + 4L),
      record_words: 16L +
      32L * f.to_int64() +
      8L * n.to_int64() +
      child.scalar_words * (10L * f.to_int64() + 3L * n.to_int64() + 4L),
      reference_arrays: 3L + f.to_int64(),
      reference_items: 3L * f.to_int64() + n.to_int64(),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 2L + 3L * f.to_int64() + n.to_int64(),
      map_entries: 2L * n.to_int64() + 2L * f.to_int64(),
    })
    is Some(metadata) &&
    @contract.object_construction_inventory(f + 1, Int::min(b, max_name_bytes))
    is Some(object) &&
    @contract.checked_emission_construction_extent(2 * f + 1) is Some(emission) &&
    initialization_writer_units(sb, sn, max_schema_depth) is Some(writer) &&
    @encode.hash_writer_live_key_inventory(0, 0) is Some(hash) &&
    @shape.collection_construction_extent({
      // Per selected property: primitive/TextLimits, Decimal or Array+item,
      // property lookup Some/Result and input tuple; alternatives co-counted.
      records: 8L + 12L * f.to_int64(),
      record_references: 12L + 20L * f.to_int64(),
      record_words: 8L + 12L * f.to_int64(),
      reference_arrays: 2L,
      reference_items: 2L * f.to_int64() + 1L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 1L,
      map_entries: f.to_int64(),
    })
    is Some(contracts) else {
    return None
  }
  initialization_capacity([
    parsed,
    initialization_collection_units(metadata),
    initialization_collection_units(object.retained),
    initialization_collection_units(object.scratch),
    initialization_collection_units(emission),
    initialization_collection_units(contracts),
    writer,
    {
      record_headers: hash.record_headers,
      reference_slots: hash.reference_slots,
      scalar_words: hash.scalar_words,
      owned_utf16_units: hash.owned_utf16_units +
      object.scratch_utf16_units +
      encoded_units.to_int64() +
      object_units.to_int64() +
      sb.to_int64(),
      owned_wire_bytes: hash.owned_wire_bytes + body_bytes.to_int64(),
    },
  ]).map(capacity => (capacity, sb))
}
