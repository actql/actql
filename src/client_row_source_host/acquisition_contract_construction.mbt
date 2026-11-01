///|
// These are the existing original admission limits, shared by admission and
// its constructor inventory. They are not caller capacity or new restrictions.
let row_contract_nodes : Int = 10000

///|
let row_contract_depth : Int = 100

///|
let row_contract_input_utf16 : Int = 100000

///|
// from_json input UTF16 and the later cumulative canonical UTF8/node writer
// budgets are different measures, even where their existing values match.
let row_contract_emit_limits : @planning.QueryEvidenceLimits = {
  max_bytes: 100000,
  max_nodes: 10000,
  max_depth: 100,
}

///|
fn row_contract_collection_units(
  value : @shape.CollectionConstructionExtent,
  text : Int64,
) -> @execution.PreparationRepresentationUnits {
  {
    record_headers: value.record_headers,
    reference_slots: value.reference_slots,
    scalar_words: value.scalar_words,
    owned_utf16_units: text,
    owned_wire_bytes: 0L,
  }
}

///|
// The actual stdlib Json parser owns mutable maps/arrays and literal Strings;
// it is not Source Parser/JsonDocument, nor a second generic node-byte tariff.
// Input punctuation bounds total values and cumulative object/array children.
// Componentwise endpoints avoid two impossible full collection populations.
fn row_contract_raw_json_shape(
  nodes : Int64,
) -> @shape.CollectionConstructionExtent? {
  guard @shape.collection_construction_extent({
      // Json.Number retains its optional original decimal spelling: the
      // SAME value record plus boxed Some can coexist for every number.
      records: 2L * nodes,
      record_references: 2L * nodes,
      record_words: nodes,
      reference_arrays: nodes,
      reference_items: nodes,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(arrays) &&
    @shape.collection_construction_extent({
      // Json.Number retains its optional original decimal spelling: the
      // SAME value record plus boxed Some can coexist for every number.
      records: 2L * nodes,
      record_references: 2L * nodes,
      record_words: nodes,
      reference_arrays: 0L,
      reference_items: 0L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: nodes,
      map_entries: nodes,
    })
    is Some(objects) else {
    return None
  }
  Some({
    record_headers: Int64::max(arrays.record_headers, objects.record_headers),
    reference_slots: Int64::max(arrays.reference_slots, objects.reference_slots),
    scalar_words: Int64::max(arrays.scalar_words, objects.scalar_words),
  })
}

///|
/// Native constructor peak of admit_row_acquisition_contracts, before entry.
/// Input Strings are borrowed from the SAME funded Source reader. Raw Json,
/// both canonical trees, normalized keys, pending/refusal frames, object sort
/// backing and the original synchronous hashing writer remain independent.
/// No protocol is parsed, admitted, issued or replaced by this quantity DATA.
pub fn row_acquisition_contracts_construction_capacity(
  query_units : Int,
  evidence_units : Int,
) -> @execution.ExecutionCapacity? {
  if query_units < 0 || evidence_units < 0 {
    return None
  }
  let raw_units = query_units.to_int64() + evidence_units.to_int64()
  // Each parser may refuse before producing even a root. Keep both fixed
  // contexts and their literal/number builder backing, including empty input.
  let raw_nodes = Int64::max(2L, raw_units)
  let canonical_nodes = Int::min(query_units, row_contract_nodes).to_int64() +
    Int::min(evidence_units, row_contract_nodes).to_int64()
  let text_units = Int64::min(
    raw_units,
    2L * row_contract_input_utf16.to_int64(),
  )
  let depth = row_contract_depth.to_int64()
  guard row_contract_raw_json_shape(raw_nodes) is Some(raw) &&
    @shape.collection_construction_extent({
      // Canonical values, object (key,value) tuples and frozen containers.
      // Canonical object output arrays coexist with their duplicate-key Map.
      records: 3L * canonical_nodes + 1L,
      record_references: 4L * canonical_nodes + 2L,
      record_words: canonical_nodes + 2L,
      reference_arrays: canonical_nodes,
      reference_items: canonical_nodes,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: canonical_nodes,
      map_entries: canonical_nodes,
    })
    is Some(canonical) &&
    @shape.collection_construction_extent({
      // from_json has at most three explicit pending frames per open level;
      // emit_value retains only its original open-container cursors. Object
      // sorting's borrowed-reference scratch is bounded by the same children.
      records: 5L * depth + 12L,
      record_references: 12L * depth + 24L,
      record_words: 6L * depth + 12L,
      reference_arrays: 3L,
      reference_items: 4L * depth + canonical_nodes,
      scalar_arrays: 2L,
      scalar_items: 3L * raw_units + 24L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(controls) &&
    @canonical.nfc_lf_retained_output_units(text_units) is Some(keys) &&
    @canonical.nfc_lf_construction_scratch_extent(
      Int::min(Int::max(query_units, evidence_units), row_contract_input_utf16),
    )
    is Some(normalization) &&
    @encode.hash_writer_construction_inventory(
      row_contract_emit_limits.max_nodes,
      row_contract_emit_limits.max_depth,
    )
    is Some(writer) else {
    return None
  }
  @execution.preparation_execution_capacity({
    retained: row_contract_collection_units(canonical, raw_units + keys),
    workspace: {
      record_headers: raw.record_headers +
      controls.record_headers +
      normalization.record_headers +
      writer.record_headers,
      reference_slots: raw.reference_slots +
      controls.reference_slots +
      normalization.reference_slots +
      writer.reference_slots,
      scalar_words: raw.scalar_words +
      controls.scalar_words +
      normalization.scalar_words +
      writer.scalar_words,
      owned_utf16_units: normalization.owned_utf16_units +
      writer.owned_utf16_units,
      owned_wire_bytes: writer.owned_wire_bytes,
    },
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}
