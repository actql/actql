///|
fn sf_initialization_collection_units(
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
// The normalizing metadata and schema parsers are distinct original
// operations. This inventory neither parses nor admits their input.
fn sf_initialization_decoded_construction(
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
fn sf_initialization_writer_units(
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
fn sf_initialization_capacity(
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
// declaration.mbt::object owns its Map, sorted input/copy arrays and tuples.
// Count raw Json before writer ceilings: an emitter refusal does not undo it.
fn sf_initialization_forest(
  nodes : Int64,
) -> @execution.PreparationRepresentationUnits? {
  guard @shape.collection_construction_extent({
      records: 3L * nodes,
      record_references: 4L * nodes,
      record_words: 2L * nodes,
      reference_arrays: 3L * nodes,
      reference_items: 4L * nodes,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: nodes,
      map_entries: nodes,
    })
    is Some(value) else {
    return None
  }
  Some(sf_initialization_collection_units(value))
}

///|
fn sf_initialization_emit(
  bytes : Int64,
  nodes : Int64,
  limits : @catalog.DeclarationLimits,
) -> @execution.PreparationRepresentationUnits? {
  if bytes < 1L || bytes > 2147483647L || nodes < 1L || nodes > 2147483647L {
    return None
  }
  let b = Int64::min(bytes, limits.max_bytes.to_int64()).to_int()
  let n = Int64::min(nodes, limits.max_nodes.to_int64()).to_int()
  guard sf_initialization_writer_units(b, n, limits.max_depth) is Some(text) &&
    @encode.hash_writer_construction_inventory(n, limits.max_depth)
    is Some(hash) else {
    return None
  }
  @execution.compose_preparation_representation([
    text,
    {
      record_headers: hash.record_headers,
      reference_slots: hash.reference_slots,
      scalar_words: hash.scalar_words,
      owned_utf16_units: hash.owned_utf16_units,
      owned_wire_bytes: hash.owned_wire_bytes,
    },
  ])
}

///|
/// ONE genuine Describe recovery/static-declaration pass, with native export,
/// Source evidence and row projection. Call independently for provider and
/// Common restores; the capacity is always issued by the Common runtime.
/// Extents come from the same bounded published original, before any decode.
/// No current Site, authorization, or replacement declaration is constructed.
pub fn initialization_construction_capacity(
  body_lengths : Array[Int],
  encoded_units : Int,
  observation_units : Int,
  name_lengths : Array[Int],
  binding_units : Int,
  connector_units : Int,
  revision_units : Int,
  describe : @catalog.DescribeLimits,
  max_observation_bytes : Int,
  limits : @catalog.DeclarationLimits,
) -> @execution.ExecutionCapacity? {
  sf_initialization_construction_capacity(
    body_lengths, body_lengths, encoded_units, observation_units, name_lengths, binding_units,
    connector_units, revision_units, describe, max_observation_bytes, limits,
  )
}

///|
fn sf_initialization_construction_capacity(
  body_lengths : Array[Int],
  body_nodes : Array[Int],
  encoded_units : Int,
  observation_units : Int,
  name_lengths : Array[Int],
  binding_units : Int,
  connector_units : Int,
  revision_units : Int,
  describe : @catalog.DescribeLimits,
  max_observation_bytes : Int,
  limits : @catalog.DeclarationLimits,
) -> @execution.ExecutionCapacity? {
  if body_lengths.is_empty() ||
    body_lengths.length() != name_lengths.length() ||
    body_lengths.length() != body_nodes.length() ||
    body_lengths.length() > 200 ||
    encoded_units < 0 ||
    observation_units < 0 ||
    binding_units < 0 ||
    connector_units < 0 ||
    revision_units < 0 ||
    describe.max_bytes < 1 ||
    describe.max_nodes < 1 ||
    describe.max_depth < 1 ||
    describe.max_fields < 1 ||
    describe.max_name_units < 1 ||
    max_observation_bytes < 1 ||
    observation_units > max_observation_bytes ||
    observation_units > 715827882 ||
    limits.max_bytes < 1 ||
    limits.max_nodes < 1 ||
    limits.max_depth < 1 {
    return None
  }
  let parts = []
  let mut total_fields = 0L
  let mut total_bytes = 0L
  let mut total_names = 0L
  let mut catalog_bytes = 256L +
    6L * (connector_units.to_int64() + revision_units.to_int64() + 71L)
  let mut catalog_nodes = 9L
  let mut member_bytes = 0L
  let child = @decode.indexed_child_construction_extent()
  for index, original_bytes in body_lengths {
    if original_bytes < 0 ||
      original_bytes > describe.max_bytes ||
      name_lengths[index] < 0 {
      return None
    }
    let b = Int::max(1, original_bytes)
    let n = Int::min(
      Int::min(b, Int::max(1, body_nodes[index])),
      describe.max_nodes,
    )
    // A completed field requires at least {"name":"a","type":"x"}
    // (23 bytes); one current failed field can allocate before this proof.
    let f = Int::min(describe.max_fields, original_bytes / 23 + 1).to_int64()
    let name = name_lengths[index].to_int64()
    total_fields += f
    total_bytes += original_bytes.to_int64()
    total_names += name
    let lookups = 24L * f + 16L + n.to_int64()
    guard sf_initialization_decoded_construction(b, n, describe.max_depth, true)
      is Some(parsed) &&
      @shape.collection_construction_extent({
        // project_field: required/optional lookup+scalar Results, precision,
        // scale, referenceTo and compound presence. Original plus TWO genuine
        // copy_resource passes each retain the 18-member metadata record.
        records: 32L +
        96L * f +
        4L * n.to_int64() +
        lookups * child.record_headers,
        record_references: 64L +
        160L * f +
        6L * n.to_int64() +
        lookups * child.reference_slots,
        record_words: 32L +
        96L * f +
        4L * n.to_int64() +
        lookups * child.scalar_words,
        reference_arrays: 24L + 8L * f,
        reference_items: 48L + 24L * f + 4L * n.to_int64(),
        scalar_arrays: 2L,
        scalar_items: 3L * b.to_int64(),
        maps: 4L + 2L * f,
        map_entries: 3L * n.to_int64() + 2L * f,
      })
      is Some(metadata) &&
      @encode.hash_writer_live_key_inventory(0, 0) is Some(digest) else {
      return None
    }
    parts.push(parsed)
    parts.push(sf_initialization_collection_units(metadata))
    // Recovery verifies an optional digest and project_describe hashes the
    // same original. Both SHA workspaces and UTF-8/decimal prefixes coexist.
    for _ in 0..<2 {
      parts.push({
        record_headers: digest.record_headers,
        reference_slots: digest.reference_slots,
        scalar_words: digest.scalar_words,
        owned_utf16_units: digest.owned_utf16_units + 71L,
        owned_wire_bytes: digest.owned_wire_bytes,
      })
    }
    parts.push({
      record_headers: 0L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: 4L * b.to_int64(),
      owned_wire_bytes: original_bytes.to_int64(),
    })
    // Compound association is unique by original field name. Across all
    // parents at most F component fields are reused, even for ten-role Address.
    // Scalar/decimal/multipicklist <=6 nodes, compound parent <=5 plus those
    // same component nodes: 12F+5 covers root and all legal compound shapes.
    let row_nodes = 12L * f + 5L
    let row_bytes = 96L + 180L * f + 12L * original_bytes.to_int64()
    let id_units = connector_units.to_int64() + name + 48L
    let envelope = 256L + 6L * (id_units + revision_units.to_int64() + 71L)
    let policy = 256L + 6L * (connector_units.to_int64() + name)
    let view_bytes = 2048L +
      6L * (6L * id_units + 8L * revision_units.to_int64() + 6L * 71L)
    let envelopes_bytes = 5L * envelope + 100L + row_bytes + 2L + policy + 180L
    let envelopes_nodes = 5L * 7L + 5L + row_nodes + 1L + 4L + 6L
    catalog_bytes += envelopes_bytes + view_bytes + 12L
    catalog_nodes += envelopes_nodes + 60L
    member_bytes += envelopes_bytes + view_bytes
    // Failed write-side contract attempts, exclusions, association maps and
    // retained read/writable arrays are independent of writer success.
    guard sf_initialization_forest(row_nodes + 6L * f + 160L) is Some(raw) &&
      @shape.collection_construction_extent({
        records: 48L + 24L * f,
        record_references: 96L + 48L * f,
        record_words: 32L + 24L * f,
        reference_arrays: 48L + 4L * f,
        reference_items: 128L + 40L * f,
        scalar_arrays: 0L,
        scalar_items: 0L,
        maps: 4L + f,
        map_entries: 4L * f,
      })
      is Some(declared) else {
      return None
    }
    parts.push(raw)
    parts.push(sf_initialization_collection_units(declared))
    for
      (bytes, nodes) in [
        (envelope + 100L, 12L),
        (envelope + row_bytes, 7L + row_nodes),
        (envelope + 2L, 8L),
        (envelope + policy, 11L),
        (envelope + 180L, 13L),
        (view_bytes, 60L),
      ] {
      guard sf_initialization_emit(bytes, nodes, limits) is Some(emission) else {
        return None
      }
      parts.push(emission)
    }
    // Shared evidence emits two independent bounded members per actual view.
    for _ in 0..<2 {
      guard sf_initialization_writer_units(4096, 64, 8) is Some(evidence) else {
        return None
      }
      parts.push(evidence)
    }
  }
  let resources = body_lengths.length().to_int64()
  let manifest_bytes = 128L +
    6L *
    (
      binding_units.to_int64() +
      connector_units.to_int64() +
      revision_units.to_int64()
    )
  // StaticDeclarationJson escapes catalog, envelope, view and manifest text;
  // arrays retain names in seven writable roles, views and exclusion reasons.
  let export_nodes = 16L + 32L * resources + 20L * total_fields
  let export_bytes = 512L +
    6L *
    (
      catalog_bytes +
      member_bytes +
      manifest_bytes +
      16L * total_bytes +
      8L * total_names +
      512L * resources
    ) +
    64L * total_fields
  let observation_bytes = 512L +
    6L * binding_units.to_int64() +
    256L * resources +
    6L * total_names
  if export_bytes > 2147483647L ||
    export_nodes > 2147483647L ||
    observation_bytes > 2147483647L {
    return None
  }
  guard sf_initialization_forest(16L + export_nodes) is Some(export_raw) &&
    @encode.hash_writer_live_key_inventory(0, 0) is Some(observation_digest) &&
    sf_initialization_emit(catalog_bytes, catalog_nodes, limits)
    is Some(catalog) &&
    sf_initialization_emit(manifest_bytes, 4L, limits) is Some(manifest) &&
    sf_initialization_emit(export_bytes, export_nodes, limits) is Some(exported) &&
    sf_initialization_writer_units(
      Int64::min(observation_bytes, max_observation_bytes.to_int64()).to_int(),
      (24L + 5L * resources).to_int(),
      4,
    )
    is Some(observation_writer) &&
    sf_initialization_decoded_construction(
      Int::max(1, observation_units * 3),
      Int::max(1, observation_units),
      Int::max(1, observation_units),
      false,
    )
    is Some(observation_parse) &&
    sf_initialization_decoded_construction(
      Int64::min(export_bytes, limits.max_bytes.to_int64()).to_int(),
      Int64::min(export_nodes, limits.max_nodes.to_int64()).to_int(),
      limits.max_depth,
      false,
    )
    is Some(export_parse) &&
    @shape.collection_construction_extent({
      // Recovery input arrays, observation outcomes, sorting, two genuine row
      // projections (one for evidence), duplicate maps and installed wrappers.
      records: 64L + 24L * resources,
      record_references: 128L + 64L * resources,
      record_words: 64L + 24L * resources,
      reference_arrays: 32L + 8L * resources,
      reference_items: 64L + 32L * resources + 4L * total_fields,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 8L,
      map_entries: 8L * resources,
    })
    is Some(projections) else {
    return None
  }
  parts.push(export_raw)
  parts.push(catalog)
  parts.push(manifest)
  parts.push(exported)
  parts.push(observation_writer)
  // prepare_owned_catalog_observation hashes the final UTF-8 observation,
  // independently of both per-Describe digest passes and declaration seals.
  parts.push({
    record_headers: observation_digest.record_headers,
    reference_slots: observation_digest.reference_slots,
    scalar_words: observation_digest.scalar_words,
    owned_utf16_units: observation_digest.owned_utf16_units + 71L,
    owned_wire_bytes: observation_digest.owned_wire_bytes,
  })
  // restoreDeclaration, recoverNamedSalesforceObservation and generate each
  // JSON.parse the original observation binding in the provider pass.
  parts.push(observation_parse)
  parts.push(observation_parse)
  parts.push(observation_parse)
  parts.push(export_parse)
  parts.push(sf_initialization_collection_units(projections))
  parts.push({
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: encoded_units.to_int64() +
    observation_units.to_int64() +
    binding_units.to_int64() +
    total_names +
    2L * (catalog_bytes + member_bytes + manifest_bytes) +
    Int64::min(export_bytes, limits.max_bytes.to_int64()),
    owned_wire_bytes: observation_bytes,
  })
  sf_initialization_capacity(parts)
}

///|
/// ONE actual execution Mapping. Fields/source names are original bounded
/// write inputs, not profile-wide maxima; Describe bytes bound required names.
/// The original StaticDeclaration and authorization remain in their issuer.
pub fn execution_mapping_construction_capacity(
  field_count : Int,
  field_units : Int,
  source_count : Int,
  source_units : Int,
  key_units : Int,
  resource_units : Int,
  connector_units : Int,
  revision_units : Int,
  describe_bytes : Int,
  max_fields : Int,
  limits : @catalog.DeclarationLimits,
) -> @execution.ExecutionCapacity? {
  if field_count < 0 ||
    field_units < 0 ||
    source_count < 0 ||
    source_units < 0 ||
    key_units < 0 ||
    resource_units < 0 ||
    connector_units < 0 ||
    revision_units < 0 ||
    describe_bytes < 0 ||
    max_fields < 1 ||
    limits.max_bytes < 1 ||
    limits.max_nodes < 1 ||
    limits.max_depth < 1 {
    return None
  }
  let f = field_count.to_int64() + source_count.to_int64()
  let required = Int::min(max_fields, describe_bytes / 23 + 1).to_int64()
  let names = field_units.to_int64() +
    source_units.to_int64() +
    key_units.to_int64()
  let schema_nodes = 5L + 6L * (f + 2L)
  let schema_bytes = 96L + 180L * (f + 2L) + 6L * names
  let mapping_nodes = 64L + schema_nodes + 4L * f + required
  let mapping_bytes = 2048L +
    schema_bytes +
    6L *
    (
      4L * names +
      describe_bytes.to_int64() +
      3L * connector_units.to_int64() +
      3L * resource_units.to_int64() +
      revision_units.to_int64() +
      6L * 71L
    ) +
    64L * f
  guard sf_initialization_forest(4L * mapping_nodes) is Some(raw) &&
    @shape.collection_construction_extent({
      // RowSource/ExecutionWrite tuples, unique/sort/filter arrays, optional
      // key/required/omittable paths and exact selected contract attempts.
      records: 32L + 24L * f,
      record_references: 64L + 40L * f,
      record_words: 32L + 24L * f,
      reference_arrays: 24L,
      reference_items: 64L + 16L * f + 4L * required,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 2L,
      map_entries: 2L * f,
    })
    is Some(controls) else {
    return None
  }
  let parts = [raw, sf_initialization_collection_units(controls)]
  // request identity, ResourceIdentity, target-schema identity, Mapping seal.
  // Text for the three hash-only families is conservative co-retention.
  for
    (bytes, nodes) in [
      (mapping_bytes, mapping_nodes),
      (512L, 7L),
      (schema_bytes, schema_nodes),
      (mapping_bytes, mapping_nodes),
    ] {
    guard sf_initialization_emit(bytes, nodes, limits) is Some(emitted) else {
      return None
    }
    parts.push(emitted)
  }
  parts.push({
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: names + 2L * mapping_bytes,
    owned_wire_bytes: 0L,
  })
  sf_initialization_capacity(parts)
}
