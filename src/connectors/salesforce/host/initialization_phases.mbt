///|
// Closed recovery retains ResourceMetadata and its primitive text, never the
// Parser/JsonDocument, Cursor/ObjectView, lookup Results or normalization
// cursors. Keep the original conservative three metadata-copy field roles;
// literal value text and its borrowed source backing stay charged; normalized
// keys and the parser/normalizer workspaces are not metadata fields.
// ReferenceTo may retain many strings per field: preserve their node-bound
// String headers and the original plus two copied reference-array item roles.
fn sf_initialization_metadata_retained(
  fields : Int64,
  nodes : Int64,
  text : Int64,
) -> @execution.PreparationRepresentationUnits? {
  guard @shape.collection_construction_extent({
      records: 32L + 96L * fields + 2L * nodes,
      record_references: 64L + 160L * fields + 2L * nodes,
      record_words: 32L + 96L * fields + 2L * nodes,
      reference_arrays: 24L + 8L * fields,
      reference_items: 48L + 24L * fields + 4L * nodes,
      scalar_arrays: 2L,
      scalar_items: 0L,
      maps: 4L + 2L * fields,
      map_entries: 2L * fields,
    })
    is Some(metadata) else {
    return None
  }
  let retained = sf_initialization_collection_units(metadata)
  Some({ ..retained, owned_utf16_units: text, })
}

///|
fn sf_initialization_observation_capacity(
  parts : Array[@execution.PreparationRepresentationUnits],
  retained : Array[@execution.PreparationRepresentationUnits],
  encoded_units : Int,
  observation_units : Int,
  binding_units : Int,
  total_names : Int64,
  total_fields : Int64,
  count : Int,
  max_observation_bytes : Int,
) -> @execution.ExecutionCapacity? {
  let resources = count.to_int64()
  let observation_bytes = 512L +
    6L * binding_units.to_int64() +
    256L * resources +
    6L * total_names
  if observation_bytes > 2147483647L {
    return None
  }
  guard sf_initialization_writer_units(
      Int64::min(observation_bytes, max_observation_bytes.to_int64()).to_int(),
      (24L + 5L * resources).to_int(),
      4,
    )
    is Some(writer) &&
    sf_initialization_decoded_construction(
      Int::max(1, observation_units * 3),
      Int::max(1, observation_units),
      Int::max(1, observation_units),
      false,
    )
    is Some(binding_parse) &&
    @encode.hash_writer_live_key_inventory(0, 0) is Some(digest) &&
    @shape.collection_construction_extent({
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
    is Some(carriers) else {
    return None
  }
  let hash : @execution.PreparationRepresentationUnits = {
    record_headers: digest.record_headers,
    reference_slots: digest.reference_slots,
    scalar_words: digest.scalar_words,
    owned_utf16_units: digest.owned_utf16_units + 71L,
    owned_wire_bytes: digest.owned_wire_bytes,
  }
  let text : @execution.PreparationRepresentationUnits = {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: encoded_units.to_int64() +
    observation_units.to_int64() +
    binding_units.to_int64() +
    total_names,
    owned_wire_bytes: observation_bytes,
  }
  for
    part in [
      writer,
      hash,
      binding_parse,
      binding_parse,
      binding_parse,
      sf_initialization_collection_units(carriers),
      text,
    ] {
    parts.push(part)
  }
  // restoreDeclaration's outer binding remains live until its second phase
  // returns. recoverNamed's binding parser has returned, and generate's parse
  // belongs to the separately funded declaration phase. Typed binding strings
  // fit the original observation text envelope above; no parser/lookup tree
  // is stored in CatalogObservation. Keep ONE complete binding envelope here.
  for
    part in [
      writer,
      hash,
      binding_parse,
      sf_initialization_collection_units(carriers),
      text,
    ] {
    retained.push(part)
  }
  sf_initialization_closed_capacity(parts, retained)
}

///|
fn sf_initialization_closed_capacity(
  parts : Array[@execution.PreparationRepresentationUnits],
  retained : Array[@execution.PreparationRepresentationUnits],
) -> @execution.ExecutionCapacity? {
  guard @execution.compose_preparation_representation(parts) is Some(peak) &&
    @execution.compose_preparation_representation(retained) is Some(kept) &&
    @execution.preparation_representation_cost(peak) is Some(peak_bytes) &&
    @execution.preparation_representation_cost(kept) is Some(retained_bytes) else {
    return None
  }
  @execution.execution_capacity(retained_bytes, peak_bytes)
}

///|
/// Dimensions come from the SAME recovered typed observation. They are
/// representation DATA, not a new Describe, observation or authority. No
/// parser runs here and no input body/identity is reconstructed from them.
pub fn initialization_declaration_construction_capacity(
  dimensions : Array[Int],
  observation_units : Int,
  name_lengths : Array[Int],
  binding_units : Int,
  connector_units : Int,
  revision_units : Int,
  describe : @catalog.DescribeLimits,
  max_observation_bytes : Int,
  limits : @catalog.DeclarationLimits,
) -> @execution.ExecutionCapacity? {
  if dimensions.length() != 2 * name_lengths.length() {
    return None
  }
  let fields = []
  let text = []
  let nodes = []
  for index in 0..<name_lengths.length() {
    fields.push(dimensions[2 * index])
    text.push(dimensions[2 * index + 1])
    nodes.push(1)
  }
  // The existing declaration/export inventory is unchanged. Its source text
  // bound now describes admitted metadata strings, not ignored Describe JSON.
  // Closed outputs retain their complete native graph/text and typed arrays.
  // Fixed evidence projection keeps its original writer envelopes prepaid;
  // failed constructors still hold the complete original phase peak.
  sf_initialization_construction_capacity(
    text,
    nodes,
    0,
    observation_units,
    name_lengths,
    binding_units,
    connector_units,
    revision_units,
    describe,
    max_observation_bytes,
    limits,
    phase=Declaration(fields),
  )
}
