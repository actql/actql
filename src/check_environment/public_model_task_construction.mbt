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
    limits.bodies.max_nodes > 0 &&
    limits.bodies.max_depth > 0 &&
    limits.contracts.max_nodes > 0 &&
    limits.contracts.max_depth > 0 &&
    limits.contracts.max_text_bytes >= 0 &&
    @scalar.admit_utf8_length(wire, limits.bodies.max_bytes) is Ok(bytes) else {
    return None
  }
  let mut lines = 1
  for index in 0..<wire.length() {
    let unit = wire.code_unit_at(index).to_int()
    if unit == 10 || unit == 13 {
      lines += 1
    }
  }
  let b = Int::max(1, bytes)
  let n = limits.bodies.max_nodes
  let d = limits.bodies.max_depth
  let source = if format == "yaml" {
    @source.yaml_literal_construction_extent(b, n, d, lines)
  } else {
    @source.json_literal_construction_extent(b, n, d)
  }
  guard source is Some(source) &&
    model_task_decode_construction(n, d) is Some(decode) &&
    model_task_contract_construction(limits) is Some(contract) else {
    return None
  }
  // PublicModelTaskDeclaration1H8R3W; two contract holders2H8R6W;
  // optional model tuple/Some2H3R; two limit Some2H2W; budget1H1R3W;
  // original limit records3H2R8W; Ok1H1R1W. Failure alternatives stay in
  // the existing fixed Host control group and original decoder inventory.
  let controls : RegistryConstructionExtent = {
    record_headers: 12L,
    reference_slots: 23L,
    scalar_words: 23L,
    owned_utf16_units: 142L,
    owned_wire_bytes: bytes.to_int64(),
  }
  let parsed : RegistryConstructionExtent = {
    record_headers: source.record_headers,
    reference_slots: source.reference_slots,
    scalar_words: source.scalar_words,
    // The preserving byte parser additionally owns its decoded input String.
    owned_utf16_units: source.owned_utf16_units + bytes.to_int64(),
    owned_wire_bytes: 0L,
  }
  Some(
    wire_admission_add(
      wire_admission_add(parsed, decode),
      wire_admission_add(controls, wire_admission_add(contract, contract)),
    ),
  )
}

///|
fn model_task_decode_construction(
  nodes : Int,
  depth : Int,
) -> RegistryConstructionExtent? {
  guard @decode.admission_construction_inventory(
      nodes, nodes, nodes, nodes, depth,
    )
    is Some(value) else {
    return None
  }
  Some({
    record_headers: value.indexed.record_headers +
    value.keys.record_headers +
    value.ancestry.record_headers +
    value.controls.record_headers,
    reference_slots: value.indexed.reference_slots +
    value.keys.reference_slots +
    value.ancestry.reference_slots +
    value.controls.reference_slots,
    scalar_words: value.indexed.scalar_words +
    value.keys.scalar_words +
    value.ancestry.scalar_words +
    value.controls.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
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
    model_task_contract_read_bounds(
      c,
      limits.contracts.max_depth,
      limits.contracts.max_text_bytes,
    )
    is Some(checked) &&
    @encode.text_writer_construction_inventory(b, n, d) is Some(writer) &&
    @encode.hash_writer_construction_inventory(n, d) is Some(hash) &&
    @value_contract.checked_emission_construction_extent(c) is Some(emission) else {
    return None
  }
  // One normalized author body and one checked schema may coexist with the
  // parsed/indexed author and typed Contract. Their original writer/emitter,
  // hash/UTF8 and failure peaks are co-counted, never credited by an estimate.
  Some({
    record_headers: parsed.record_headers +
    checked.retained.record_headers +
    checked.scratch.record_headers +
    2L * writer.record_headers +
    hash.record_headers +
    emission.record_headers,
    reference_slots: parsed.reference_slots +
    checked.retained.reference_slots +
    checked.scratch.reference_slots +
    2L * writer.reference_slots +
    hash.reference_slots +
    emission.reference_slots,
    scalar_words: parsed.scalar_words +
    checked.retained.scalar_words +
    checked.scratch.scalar_words +
    2L * writer.scalar_words +
    hash.scalar_words +
    emission.scalar_words,
    owned_utf16_units: parsed.owned_utf16_units +
    checked.scratch_utf16_units +
    2L * writer.owned_utf16_units +
    hash.owned_utf16_units +
    2L * b.to_int64(),
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
  // Normalized1H10R4W; resolved1H4R1W and a possible override generation
  // copy1H1R3W. Both final wires and their exact original CIDs remain owned.
  {
    record_headers: 7L,
    reference_slots: 15L,
    scalar_words: 8L,
    owned_utf16_units: value.task_wire.length().to_int64() +
    value.task_cid.length().to_int64() +
    value.prompt_wire.length().to_int64() +
    value.prompt_cid.length().to_int64(),
    owned_wire_bytes: 0L,
  }
}

///|
pub fn public_model_task_normalization_construction_extent(
  original : PublicModelTaskDeclaration,
  limits : ModelTaskLimits,
) -> RegistryConstructionExtent? {
  let nodes = original.input.nodes.to_int64() + original.output.nodes.to_int64()
  guard nodes > 0L && nodes <= 2147483647L else { return None }
  guard limits.bodies.max_bytes > 0 &&
    limits.bodies.max_nodes > 0 &&
    limits.bodies.max_depth > 0 &&
    limits.contracts.max_nodes > 0 &&
    @encode.text_writer_construction_inventory(
      limits.bodies.max_bytes,
      limits.bodies.max_nodes,
      limits.bodies.max_depth,
    )
    is Some(writer) &&
    @encode.hash_writer_construction_inventory(
      limits.bodies.max_nodes,
      limits.bodies.max_depth,
    )
    is Some(hash) &&
    @value_contract.checked_emission_construction_extent(nodes.to_int())
    is Some(emission) else {
    return None
  }
  // Four actual writer calls: prompt preimage/final and Task preimage/final.
  // Each emitter is bounded independently from its output String policy. The
  // original Task/Contracts/defaults stay borrowed from their retained prefix.
  Some({
    record_headers: 4L * writer.record_headers +
    2L * hash.record_headers +
    emission.record_headers +
    7L,
    reference_slots: 4L * writer.reference_slots +
    2L * hash.reference_slots +
    emission.reference_slots +
    15L,
    scalar_words: 4L * writer.scalar_words +
    2L * hash.scalar_words +
    emission.scalar_words +
    8L,
    owned_utf16_units: 4L * writer.owned_utf16_units +
    2L * hash.owned_utf16_units +
    2L * limits.bodies.max_bytes.to_int64() +
    142L,
    owned_wire_bytes: 2L * limits.bodies.max_bytes.to_int64() +
    2L * hash.owned_wire_bytes,
  })
}

///|
/// Quantities of THIS original admitted Task, not the document's unused limits.
/// One scalar inspection visits only this Task's original index and contracts;
/// it never revisits earlier registered Tasks or emits/hashes their bodies.
pub fn public_model_task_declaration_retained_extent(
  value : PublicModelTaskDeclaration,
) -> RegistryConstructionExtent? {
  let root = value.original
  let g = @decode.observe_subtree_geometry(root, [])
  let usage = @decode.admission_usage(root)
  guard @source.json_index_borrowed_construction_extent(
      g.nodes,
      g.fields,
      usage.total_string_bytes.to_int64(),
      keep_spans=true,
    )
    is Some(source) &&
    @decode.admission_construction_inventory(
      g.nodes,
      g.fields,
      g.objects,
      g.arrays,
      usage.depth,
    )
    is Some(index) else {
    return None
  }
  let mut retained : RegistryConstructionExtent = {
    record_headers: source.record_headers + index.indexed.record_headers + 9L,
    reference_slots: source.reference_slots +
    index.indexed.reference_slots +
    20L,
    scalar_words: source.scalar_words + index.indexed.scalar_words + 11L,
    owned_utf16_units: source.owned_utf16_units,
    owned_wire_bytes: 0L,
  }
  for original in [value.input, value.output] {
    let g = @value_contract.observe_read_construction_geometry(
      original.original,
    )
    guard @value_contract.read_construction_inventory(g) is Some(typed) &&
      @source.json_index_borrowed_construction_extent(
        g.nodes,
        g.fields,
        original.wire.length().to_int64(),
        keep_spans=false,
      )
      is Some(text) else {
      return None
    }
    retained = wire_admission_add(retained, {
      record_headers: typed.retained.record_headers + text.record_headers + 2L,
      reference_slots: typed.retained.reference_slots + text.reference_slots,
      scalar_words: typed.retained.scalar_words + text.scalar_words,
      // The checked Contract borrows canonical field/enum Strings. Keep those
      // Strings, its emitted schema wire and original CID, not parser scratch.
      owned_utf16_units: text.owned_utf16_units +
      original.wire.length().to_int64() +
      original.cid.length().to_int64(),
      owned_wire_bytes: 0L,
    })
  }
  Some(retained)
}

///|
fn model_task_contract_read_bounds(
  nodes : Int,
  depth : Int,
  text : Int,
) -> @value_contract.ReadConstructionInventory? {
  if nodes < 1 || depth < 0 || text < 0 {
    return None
  }
  // Independent valid all-object and all-array envelopes. Co-count both full
  // nonnegative recipes; do not submit an impossible observed tree with N
  // objects AND N arrays in N nodes. This is a current constructor bound,
  // never an observation/semantic-admission witness.
  guard @value_contract.read_construction_inventory({
      nodes,
      objects: nodes,
      arrays: 0,
      fields: nodes - 1,
      max_fields: nodes - 1,
      max_array_items: 0,
      max_selected_text_units: text,
      outer_depth: depth,
      work: 0L,
    })
    is Some(objects) &&
    @value_contract.read_construction_inventory({
      nodes,
      objects: 0,
      arrays: nodes,
      fields: 0,
      max_fields: 0,
      max_array_items: nodes - 1,
      max_selected_text_units: text,
      outer_depth: depth,
      work: 0L,
    })
    is Some(arrays) &&
    @shape.add_collection_construction_extents(
      objects.retained,
      arrays.retained,
    )
    is Some(retained) &&
    @shape.add_collection_construction_extents(objects.scratch, arrays.scratch)
    is Some(scratch) else {
    return None
  }
  Some({
    retained,
    scratch,
    scratch_utf16_units: objects.scratch_utf16_units +
    arrays.scratch_utf16_units,
  })
}
