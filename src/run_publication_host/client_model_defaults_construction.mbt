///|
fn client_model_metadata_add(
  a : @environment.RegistryConstructionExtent,
  b : @environment.RegistryConstructionExtent,
) -> @environment.RegistryConstructionExtent {
  {
    record_headers: a.record_headers + b.record_headers,
    reference_slots: a.reference_slots + b.reference_slots,
    scalar_words: a.scalar_words + b.scalar_words,
    owned_utf16_units: a.owned_utf16_units + b.owned_utf16_units,
    owned_wire_bytes: a.owned_wire_bytes + b.owned_wire_bytes,
  }
}

///|
/// SAME three existing canonical binding originals plus one defaults-profile
/// read, before either constructor. Inputs stay with their Provider owner.
/// Source nodes, canonical fields and text have independent current-document
/// bounds; no subsequent Task/default document maximum is retained here.
pub fn client_model_provider_defaults_construction_extent(
  provider : String,
  installation : String,
  contract : String,
  configuration : String,
  limits : @environment.Limits,
) -> @environment.RegistryConstructionExtent? {
  let mut peak : @environment.RegistryConstructionExtent = {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  for wire in [installation, contract, configuration] {
    guard @scalar.admit_utf8_length(wire, 65536) is Ok(bytes) &&
      @source.json_literal_construction_extent(bytes, 4096, 32) is Some(source) &&
      @canonical.source_conversion_construction_extent(
        4096, 4096, 4096, 4096, 32, bytes,
      )
      is Some(canonical) &&
      @encode.text_writer_construction_inventory(65536, 4096, 32) is Some(text) &&
      @encode.hash_writer_construction_inventory(4096, 32) is Some(hash) else {
      return None
    }
    // from_source and its preserving Source parser are distinct trees.
    // Synchronous canonical emit_value owns one parent enum/cursor pair per
    // open container plus its parent Array. Bound those by the original depth.
    peak = client_model_metadata_add(peak, {
      record_headers: source.record_headers +
      canonical.retained.record_headers +
      canonical.scratch.record_headers +
      text.record_headers +
      hash.record_headers +
      68L,
      reference_slots: source.reference_slots +
      canonical.retained.reference_slots +
      canonical.scratch.reference_slots +
      text.reference_slots +
      hash.reference_slots +
      101L,
      scalar_words: source.scalar_words +
      canonical.retained.scalar_words +
      canonical.scratch.scalar_words +
      text.scalar_words +
      hash.scalar_words +
      72L,
      owned_utf16_units: source.owned_utf16_units +
      canonical.retained_utf16_units +
      canonical.scratch_utf16_units +
      text.owned_utf16_units +
      hash.owned_utf16_units +
      bytes.to_int64() +
      71L,
      owned_wire_bytes: bytes.to_int64() + hash.owned_wire_bytes,
    })
  }
  guard @scalar.admit_utf8_length(configuration, limits.max_bytes) is Ok(bytes) &&
    @decode.preserving_json_admission_construction_inventory(
      bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    is Some(profile) &&
    @encode.text_writer_construction_inventory(
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    is Some(envelope) &&
    measure_client_model_provider_binding_construction(provider)
    is Some((binding_bytes, binding_nodes, binding_depth)) &&
    @source.json_literal_construction_extent(
      binding_bytes, binding_nodes, binding_depth,
    )
    is Some(binding_source) &&
    @canonical.source_conversion_construction_extent(
      binding_nodes, binding_nodes, binding_nodes, binding_nodes, binding_depth,
      binding_bytes,
    )
    is Some(binding) &&
    @encode.text_writer_construction_inventory(
      binding_bytes, binding_nodes, binding_depth,
    )
    is Some(binding_writer) else {
    return None
  }
  let n = limits.max_nodes.to_int64()
  // Profile/models/handling/Generation, original entries/selector/region
  // collections and their growth. All string/cursor leaves borrow the one
  // checked configuration arena, retained beside its returned typed profile.
  let typed = @shape.collection_construction_extent({
    records: 8L + 7L * n,
    record_references: 12L + 14L * n,
    record_words: 9L + 8L * n,
    reference_arrays: 3L + 2L * n,
    reference_items: 6L * n,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 1L + n,
    map_entries: 2L * n,
  }).unwrap()
  Some(
    client_model_metadata_add(peak, {
      record_headers: profile.record_headers +
      2L * envelope.record_headers +
      typed.record_headers +
      binding_source.record_headers +
      binding.retained.record_headers +
      binding.scratch.record_headers +
      3L * binding_writer.record_headers +
      34L,
      reference_slots: profile.reference_slots +
      2L * envelope.reference_slots +
      typed.reference_slots +
      binding_source.reference_slots +
      binding.retained.reference_slots +
      binding.scratch.reference_slots +
      3L * binding_writer.reference_slots +
      42L,
      scalar_words: profile.scalar_words +
      2L * envelope.scalar_words +
      typed.scalar_words +
      binding_source.scalar_words +
      binding.retained.scalar_words +
      binding.scratch.scalar_words +
      3L * binding_writer.scalar_words +
      38L,
      owned_utf16_units: profile.owned_utf16_units +
      2L * envelope.owned_utf16_units +
      binding_source.owned_utf16_units +
      binding.retained_utf16_units +
      binding.scratch_utf16_units +
      3L * binding_writer.owned_utf16_units +
      4L * binding_bytes.to_int64(),
      owned_wire_bytes: bytes.to_int64() + 4L * binding_bytes.to_int64() + 71L,
    }),
  )
}

///|
/// Actual returned configuration/profile only. No limits or earlier registry
/// prefixes are inspected, serialized or revalidated to obtain this quantity.
pub fn client_model_provider_defaults_retained_extent(
  original : ClientModelProviderDefaults,
) -> @environment.RegistryConstructionExtent? {
  let wire = @publication.run_evidence_value_json(original.binding)
  client_model_provider_defaults_retained_bound(
    original.bytes,
    original.nodes,
    wire.length(),
  )
}

///|
/// Bound the escaping configuration before construction from its original
/// bytes, a node upper bound and the measured binding writer upper bound.
pub fn client_model_provider_defaults_retained_bound(
  bytes : Int,
  n : Int,
  binding_units : Int,
) -> @environment.RegistryConstructionExtent? {
  if bytes <= 0 || n <= 0 || binding_units <= 0 {
    return None
  }
  // Any nonempty original JSON tree has at most nodes-1 field edges. Its
  // complete actual UTF8 input bounds total decoded UTF16 units (escapes and
  // multibyte scalars cannot expand that count); this is a bound, not a text
  // observation or a claim of nodes/fields from its byte size.
  guard @source.json_index_borrowed_construction_extent(
      n,
      n - 1,
      bytes.to_int64(),
      keep_spans=true,
    )
    is Some(source) &&
    @decode.admission_construction_inventory(n, n, n, n, 64) is Some(index) else {
    return None
  }
  let count = n.to_int64()
  let typed = @shape.collection_construction_extent({
    records: 8L + 7L * count,
    record_references: 12L + 14L * count,
    record_words: 9L + 8L * count,
    reference_arrays: 3L + 2L * count,
    reference_items: 6L * count,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }).unwrap()
  // The binding's closed six-String body and its tiny canonical tree remain
  // with the original profile.
  Some({
    record_headers: source.record_headers +
    index.indexed.record_headers +
    typed.record_headers +
    32L,
    reference_slots: source.reference_slots +
    index.indexed.reference_slots +
    typed.reference_slots +
    44L,
    scalar_words: source.scalar_words +
    index.indexed.scalar_words +
    typed.scalar_words +
    12L,
    owned_utf16_units: source.owned_utf16_units + 3L * binding_units.to_int64(),
    owned_wire_bytes: bytes.to_int64(),
  })
}

///|
pub fn client_model_provider_defaults_resolution_extents(
  original : ClientModelProviderDefaults,
  tokens : Int64?,
) -> (
  @environment.RegistryConstructionExtent,
  @environment.RegistryConstructionExtent,
) {
  let controls : @environment.RegistryConstructionExtent = {
    // JS same-call binding/readUsage/result views and original Core Result.
    record_headers: 6L,
    reference_slots: 10L,
    scalar_words: 10L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  guard original.profile is Some(profile) else { return (controls, controls) }
  let inventory = @environment.model_provider_defaults_resolution_construction_inventory(
    profile, tokens,
  )
  let arrays = @shape.collection_construction_extent({
    records: inventory.resolved_records +
    inventory.generation_copies +
    inventory.work_cells +
    inventory.issue_tags +
    inventory.error_results +
    inventory.success_results,
    record_references: 4L * inventory.resolved_records +
    inventory.generation_copies +
    inventory.error_results +
    inventory.success_results,
    record_words: inventory.resolved_records +
    3L * inventory.generation_copies +
    inventory.work_cells +
    inventory.issue_tags +
    inventory.error_results +
    inventory.success_results,
    reference_arrays: 0L,
    reference_items: 0L,
    scalar_arrays: inventory.comparison_array_constructions,
    scalar_items: inventory.comparison_items *
    inventory.comparison_array_constructions,
    maps: 0L,
    map_entries: 0L,
  }).unwrap()
  let retained = @environment.model_provider_defaults_resolution_retained_extent(
    profile, tokens,
  )
  (
    client_model_metadata_add(controls, {
      record_headers: arrays.record_headers,
      reference_slots: arrays.reference_slots,
      scalar_words: arrays.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    }),
    client_model_metadata_add(controls, {
      record_headers: retained.record_headers,
      reference_slots: retained.reference_slots,
      scalar_words: retained.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    }),
  )
}
