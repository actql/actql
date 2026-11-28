///|
// Exact evidence vectors from the original inputs and one measuring writer.
// The receipt emitter opens only its root and small binding/evidence records
// as unordered objects; borrowed canonical subtrees use ordered frames.
pub fn installed_effect_public_receipt_inventory(
  slots : Int64,
  depth : Int,
) -> Int64? {
  let levels = depth.to_int64()
  guard @shape.collection_construction_extent({
      // Receipt and root validation carriers, evidence vectors/copies and
      // sort scratch; original CIDs/values are borrowed by all these arrays.
      records: 50L + 4L * slots + 9L * levels,
      record_references: 90L + 6L * slots + 16L * levels,
      record_words: 55L + 4L * slots + 12L * levels,
      reference_arrays: 19L,
      reference_items: 5L * slots + 3L * levels,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(input) &&
    @encode.measuring_writer_construction_extent(27, depth) is Some(writer) &&
    @encode.hash_writer_live_key_inventory(0, depth) is Some(comparison) else {
    return None
  }
  @execution.preparation_representation_cost({
    record_headers: input.record_headers +
    writer.record_headers +
    comparison.record_headers,
    reference_slots: input.reference_slots +
    writer.reference_slots +
    comparison.reference_slots,
    scalar_words: input.scalar_words +
    writer.scalar_words +
    comparison.scalar_words,
    owned_utf16_units: comparison.owned_utf16_units,
    owned_wire_bytes: comparison.owned_wire_bytes,
  })
}

///|
pub fn installed_effect_public_receipt_capacity(
  bytes : Int,
  nodes : Int,
  depth : Int,
  max_bytes : Int,
  max_nodes : Int,
  inventory : Int64,
) -> @execution.ExecutionCapacity? {
  // The existing run_receipt seal adds one fixed self-CID field. Unlike the
  // Manifest issuer, it reads the complete emitted body with the normalizing
  // parser. Retain that actual full returned tree and wire.
  let sealed_bytes = Int64::min(max_bytes.to_int64(), bytes.to_int64() + 100L).to_int()
  let sealed_nodes = Int64::min(max_nodes.to_int64(), nodes.to_int64() + 1L).to_int()
  guard installed_effect_canonical_body_capacity(
      sealed_bytes, sealed_nodes, depth,
    )
    is Some(body) &&
    @encode.text_writer_live_key_inventory(sealed_bytes, 27, depth)
    is Some(writer) &&
    @publication.protocol_wire_validation_construction_extent(
      sealed_nodes.to_int64(),
    )
    is Some(validation) &&
    @encode.hash_writer_live_key_inventory(0, depth) is Some(hash) &&
    @execution.preparation_representation_cost({
      record_headers: writer.record_headers +
      validation.record_headers +
      hash.record_headers,
      reference_slots: writer.reference_slots +
      validation.reference_slots +
      hash.reference_slots,
      scalar_words: writer.scalar_words +
      validation.scalar_words +
      hash.scalar_words,
      owned_utf16_units: writer.owned_utf16_units + hash.owned_utf16_units,
      owned_wire_bytes: hash.owned_wire_bytes,
    })
    is Some(canonical) &&
    @execution.checked_preparation_add_product(inventory, canonical, 1L)
    is Some(workspace) &&
    @execution.execution_capacity(0L, workspace) is Some(extra) else {
    return None
  }
  @execution.add_execution_capacity(body, extra)
}

///|
/// Cover the original empty-binding proof and Template check before the
/// Receipt issuer asks for its evidence vector. Both bodies are temporary.
pub fn installed_effect_public_receipt_entry(
  materials : @publication_host.ClientEffectRunMaterials,
) -> Int64? {
  let root = @syntax.program_body(
    @publication_host.prepared_client_effect_computation_source(
      materials.prepared,
    ),
  )
  guard @decode.object_length(root) is Some(fields) &&
    @decode.open_object_construction_extent(fields) is Some(object) else {
    return None
  }
  let mut bindings = 0L
  for index in 0..<fields {
    if @decode.field_at(root, index) is Some(("bindings", binding)) {
      bindings = @decode.object_length(binding).unwrap_or(0).to_int64()
      break
    }
  }
  let template = @publication_host.client_effect_compilation_template(
    materials.compilation,
  )
  guard @publication.run_evidence_value_wire_usage(template)
    is Some((bytes, nodes, depth)) &&
    installed_effect_normalized_dependency_capacity(bytes, nodes, depth)
    is Some(template) &&
    // The only issued binding body has a version, empty object and self CID.
    installed_effect_canonical_body_capacity(512, 16, 4) is Some(empty) &&
    @execution.preparation_array_representation(1L, bindings, true)
    is Some(names) &&
    @execution.preparation_representation_cost({
      record_headers: object.record_headers + names.record_headers + 31L,
      reference_slots: object.reference_slots + names.reference_slots + 57L,
      scalar_words: object.scalar_words + names.scalar_words + 29L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(controls) &&
    @execution.checked_preparation_add_product(
      controls,
      @execution.execution_capacity_execution_bytes(template),
      1L,
    )
    is Some(active) else {
    return None
  }
  @execution.checked_preparation_add_product(
    active,
    @execution.execution_capacity_execution_bytes(empty),
    1L,
  )
}
