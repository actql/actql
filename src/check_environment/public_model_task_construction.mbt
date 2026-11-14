///|
/// One current public Task document. Independent source/node/depth/contract
/// limits remain rejection bounds; no future Task's maximum is reserved here.
/// The input String is already retained by the original Host reader. This is
/// constructor DATA, not a Task issuer, capacity grant or physical VM claim.
pub fn public_model_task_document_construction_extent(
  wire : String,
  format : String,
  limits : ModelTaskLimits,
) -> RegistryConstructionExtent? {
  guard (format == "json" || format == "yaml") &&
    limits.bodies.max_nodes > 0 && limits.bodies.max_depth > 0 &&
    limits.contracts.max_nodes > 0 && limits.contracts.max_depth > 0 &&
    limits.contracts.max_text_bytes >= 0 &&
    @scalar.admit_utf8_length(wire, limits.bodies.max_bytes) is Ok(bytes) else {
    return None
  }
  let mut lines = 1
  for index in 0..<wire.length() {
    let unit = wire.code_unit_at(index).to_int()
    if unit == 10 || unit == 13 { lines += 1 }
  }
  let b = Int::max(1, bytes)
  let n = limits.bodies.max_nodes
  let d = limits.bodies.max_depth
  let source = if format == "yaml" {
    @source.yaml_literal_construction_extent(b, n, d, lines)
  } else { @source.json_literal_construction_extent(b, n, d) }
  guard source is Some(source) &&
    model_task_decode_construction(b, n, d) is Some(decode) &&
    model_task_contract_construction(limits) is Some(contract) else { return None }
  // PublicModelTaskDeclaration1H8R3W; two contract holders2H8R6W;
  // optional model tuple/Some2H3R; two limit Some2H2W; budget1H1R3W;
  // original limit records3H2R8W; Ok1H1R1W. Failure alternatives stay in
  // the existing fixed Host control group and original decoder inventory.
  let controls : RegistryConstructionExtent = {
    record_headers: 12L, reference_slots: 23L, scalar_words: 23L,
    owned_utf16_units: 142L, owned_wire_bytes: bytes.to_int64(),
  }
  let parsed : RegistryConstructionExtent = {
    record_headers: source.record_headers,
    reference_slots: source.reference_slots,
    scalar_words: source.scalar_words,
    // The preserving byte parser additionally owns its decoded input String.
    owned_utf16_units: source.owned_utf16_units + bytes.to_int64(),
    owned_wire_bytes: 0L,
  }
  Some(wire_admission_add(wire_admission_add(parsed, decode),
    wire_admission_add(controls, wire_admission_add(contract, contract))))
}

///|
fn model_task_decode_construction(
  bytes : Int, nodes : Int, depth : Int,
) -> RegistryConstructionExtent? {
  guard @decode.admission_construction_inventory(nodes, nodes, nodes, nodes, depth)
    is Some(value) else { return None }
  Some({
    record_headers: value.indexed.record_headers + value.keys.record_headers +
      value.ancestry.record_headers + value.controls.record_headers,
    reference_slots: value.indexed.reference_slots + value.keys.reference_slots +
      value.ancestry.reference_slots + value.controls.reference_slots,
    scalar_words: value.indexed.scalar_words + value.keys.scalar_words +
      value.ancestry.scalar_words + value.controls.scalar_words,
    owned_utf16_units: 0L, owned_wire_bytes: 0L,
  })
}

///|
fn model_task_contract_construction(
  limits : ModelTaskLimits,
) -> RegistryConstructionExtent? {
  let n = limits.bodies.max_nodes
  let d = limits.bodies.max_depth
  let c = limits.contracts.max_nodes
  let b = limits.bodies.max_bytes
  guard @decode.preserving_json_admission_construction_inventory(b, n, d)
    is Some(parsed) &&
    @value_contract.read_construction_inventory({
      nodes: c, objects: c, arrays: c, fields: c, max_fields: c,
      max_array_items: c - 1,
      max_selected_text_units: limits.contracts.max_text_bytes,
      outer_depth: limits.contracts.max_depth, work: 0L,
    }) is Some(checked) &&
    @encode.text_writer_construction_inventory(b, n, d) is Some(writer) &&
    @encode.hash_writer_construction_inventory(n, d) is Some(hash) &&
    @value_contract.checked_emission_construction_extent(c) is Some(emission) else {
    return None
  }
  // One normalized author body and one checked schema may coexist with the
  // parsed/indexed author and typed Contract. Their original writer/emitter,
  // hash/UTF8 and failure peaks are co-counted, never credited by an estimate.
  Some({
    record_headers: parsed.record_headers + checked.retained.record_headers +
      checked.scratch.record_headers + 2L * writer.record_headers +
      hash.record_headers + emission.record_headers,
    reference_slots: parsed.reference_slots + checked.retained.reference_slots +
      checked.scratch.reference_slots + 2L * writer.reference_slots +
      hash.reference_slots + emission.reference_slots,
    scalar_words: parsed.scalar_words + checked.retained.scalar_words +
      checked.scratch.scalar_words + 2L * writer.scalar_words +
      hash.scalar_words + emission.scalar_words,
    owned_utf16_units: parsed.owned_utf16_units + checked.scratch_utf16_units +
      2L * writer.owned_utf16_units + hash.owned_utf16_units + 2L * b.to_int64(),
    owned_wire_bytes: 2L * b.to_int64() + hash.owned_wire_bytes,
  })
}

///|
/// Successful immutable output only. Borrowed defaults and input originals
/// remain charged by their earlier holder. No constructor scratch is released
/// until the Host has observed the original synchronous return/current fence.
pub fn normalized_public_model_task_retained_extent(
  value : NormalizedPublicModelTask,
) -> RegistryConstructionExtent {
  // Normalized1H10R1W; resolved1H4R1W and a possible override generation
  // copy1H1R3W. Both final wires and their exact original CIDs remain owned.
  {
    record_headers: 7L, reference_slots: 15L, scalar_words: 5L,
    owned_utf16_units: value.task_wire.length().to_int64() +
      value.task_cid.length().to_int64() + value.prompt_wire.length().to_int64() +
      value.prompt_cid.length().to_int64(),
    owned_wire_bytes: 0L,
  }
}

///|
pub fn public_model_task_normalization_construction_extent(
  original : PublicModelTaskDeclaration,
  limits : ModelTaskLimits,
) -> RegistryConstructionExtent? {
  guard limits.bodies.max_bytes > 0 && limits.bodies.max_nodes > 0 &&
    limits.bodies.max_depth > 0 && limits.contracts.max_nodes > 0 &&
    @encode.text_writer_construction_inventory(limits.bodies.max_bytes,
      limits.bodies.max_nodes, limits.bodies.max_depth) is Some(writer) &&
    @encode.hash_writer_construction_inventory(limits.bodies.max_nodes,
      limits.bodies.max_depth) is Some(hash) &&
    @value_contract.checked_emission_construction_extent(limits.contracts.max_nodes)
      is Some(emission) else { return None }
  // Four actual writer calls: prompt preimage/final and Task preimage/final.
  // Each emitter is bounded independently from its output String policy. The
  // original Task/Contracts/defaults stay borrowed from their retained prefix.
  Some({
    record_headers: 4L * writer.record_headers + 2L * hash.record_headers +
      emission.record_headers + 7L,
    reference_slots: 4L * writer.reference_slots + 2L * hash.reference_slots +
      emission.reference_slots + 15L,
    scalar_words: 4L * writer.scalar_words + 2L * hash.scalar_words +
      emission.scalar_words + 5L,
    owned_utf16_units: 4L * writer.owned_utf16_units + 2L * hash.owned_utf16_units +
      2L * limits.bodies.max_bytes.to_int64() + 142L,
    owned_wire_bytes: 2L * limits.bodies.max_bytes.to_int64() +
      2L * hash.owned_wire_bytes,
  })
}
