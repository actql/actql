///|
/// DATA inventory for the existing bounded Mapping constructor, before it
/// copies fields or opens any writer. The provider Catalog remains in its
/// runtime; the caller supplies only captured counts to the Common issuer.
/// This quote grants no writable property or permission.
pub fn execution_mapping_construction_capacity(
  field_count : Int,
  source_count : Int,
  input_units : Int64,
  limits : MappingLimits,
) -> @execution.ExecutionCapacity? {
  if limits.max_properties <= 0 ||
    limits.max_fields <= 0 ||
    limits.max_name_bytes <= 0 ||
    limits.max_bytes <= 0 ||
    limits.max_nodes <= 0 ||
    limits.max_depth <= 0 ||
    field_count < 0 ||
    field_count > 1073741821 ||
    source_count < 0 ||
    input_units < 0L ||
    // Reject arithmetic demand that cannot have a finite Int64 composition.
    // This is not a provider field/value bound or permission decision.
    input_units > 2305843009213693951L ||
    field_count >= limits.max_fields ||
    source_count > limits.max_fields {
    return None
  }
  let f = field_count.to_int64()
  let s = source_count.to_int64()
  // HubSpot's supported property contracts are bounded primitive/Decimal
  // carriers or checkbox Arrays of String. This covers the constructor's
  // fixed keys, repeated schemas/sources, escaped names and identifiers.
  // Clamp demand, not the actual constructor limits: a tiny selected Mapping
  // must not initialize/retain every unused byte/node of a wider output cap.
  let bytes = Int64::min(
    limits.max_bytes.to_int64(),
    4096L +
    48L * Int64::min(input_units, limits.max_bytes.to_int64()) +
    2048L * f +
    1024L * s,
  ).to_int()
  let nodes = Int64::min(limits.max_nodes.to_int64(), 256L + 128L * f + 64L * s).to_int()
  let depth = Int::min(limits.max_depth, 16)
  // The result keeps the final document, selected names/sources, canonical
  // identifiers and its native/Host projection records. Original field text
  // and the immutable Catalog are references; the final document owns text.
  let retained : @execution.PreparationRepresentationUnits = {
    record_headers: 24L + 4L * f + 4L * s,
    reference_slots: 48L + 8L * f + 8L * s,
    scalar_words: 24L + 4L * f + 4L * s,
    owned_utf16_units: 2L * bytes.to_int64() + 512L,
    owned_wire_bytes: 0L,
  }
  // Checked Object contracts, selected/sorted name arrays, source maps and
  // the declaration's schema identity remain live with intermediate documents.
  guard @contract.object_construction_inventory(
      field_count + 2,
      limits.max_name_bytes,
    )
    is Some(object) &&
    @contract.checked_emission_construction_extent(field_count * 2 + 4)
    is Some(emission) &&
    initialization_writer_units(bytes, nodes, depth) is Some(writer) &&
    @encode.hash_writer_live_key_inventory(0, 0) is Some(hash) &&
    @shape.collection_construction_extent({
      records: 32L + 16L * f + 12L * s,
      record_references: 48L + 24L * f + 20L * s,
      record_words: 32L + 16L * f + 12L * s,
      reference_arrays: 12L,
      reference_items: 16L + 10L * f + 8L * s,
      scalar_arrays: 2L,
      scalar_items: 64L + 4L * f + 4L * s,
      maps: 4L,
      map_entries: 4L * f + 4L * s,
    })
    is Some(controls) else {
    return None
  }
  // Schema, row mapping, request identity, resource identity, preimage and
  // final document writers overlap. Completed output above remains retained;
  // these builders and hashing/UTF-8 scratch end at synchronous return.
  guard @execution.compose_preparation_representation([
      initialization_collection_units(object.retained),
      initialization_collection_units(object.scratch),
      initialization_collection_units(emission),
      initialization_collection_units(controls),
      writer,
      writer,
      writer,
      writer,
      writer,
      writer,
      {
        record_headers: hash.record_headers,
        reference_slots: hash.reference_slots,
        scalar_words: hash.scalar_words,
        owned_utf16_units: hash.owned_utf16_units +
        object.scratch_utf16_units +
        8L * bytes.to_int64(),
        owned_wire_bytes: hash.owned_wire_bytes + 2L * bytes.to_int64(),
      },
    ])
    is Some(workspace) else {
    return None
  }
  @execution.preparation_execution_capacity({
    retained,
    workspace,
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}
