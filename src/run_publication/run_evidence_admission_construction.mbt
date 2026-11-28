///|
/// Constructor quantities for ONE bounded admit_run_evidence_value call.
/// This is DATA in the existing preparation units, not capacity or authority.
/// The caller separately retains its input and prices these original units.
pub(all) struct RunEvidenceAdmissionConstruction {
  retained : @shape.CollectionConstructionExtent
  retained_utf16_units : Int64
  record_headers : Int64
  reference_slots : Int64
  scalar_words : Int64
  owned_utf16_units : Int64
  owned_wire_bytes : Int64
} derive(Eq, Debug)

///|
/// Actual nonpreserving parse_contract_wire, generated shape, complete and
/// self-CID canonical views, hash and final text. Input bounds must describe
/// the supplied wire, not merely a policy ceiling on a larger supplied value.
/// Both canonical forests and both serializer stacks are summed deliberately.
pub fn run_evidence_admission_construction_inventory(
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> RunEvidenceAdmissionConstruction? {
  // This closed inventory serves the unchanged saved-evidence reader limits.
  // Refusal here does not change that reader's syntax or admission limits.
  if bytes < 1 ||
    bytes > 131072 ||
    nodes < 1 ||
    nodes > 8192 ||
    depth < 1 ||
    depth > 64 {
    return None
  }
  run_evidence_admission_construction_for_bounds(bytes, nodes, depth)
}

///|
/// Same constructor geometry for the saved Model CaptureBundle role, whose
/// existing settlement reader admits up to 1 MiB, 100,000 nodes and depth 100.
/// Its preserving byte parser and canonical conversion keep exact data keys.
pub fn model_capture_bundle_read_construction_inventory(
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> RunEvidenceAdmissionConstruction? {
  if bytes < 1 ||
    bytes > 1048576 ||
    nodes < 1 ||
    nodes > 100000 ||
    depth < 1 ||
    depth > 100 {
    return None
  }
  run_evidence_admission_construction_for_bounds(
    bytes,
    nodes,
    depth,
    data_keys=true,
  ).map(quote => {
    // Storage, reader and retained optional bundle/records: 4H/5R/4W.
    // Selecting the array and returning the reader add two transient carriers.
    ..quote,
    retained: {
      record_headers: quote.retained.record_headers + 4L,
      reference_slots: quote.retained.reference_slots + 5L,
      scalar_words: quote.retained.scalar_words + 4L,
    },
    record_headers: quote.record_headers + 6L,
    reference_slots: quote.reference_slots + 7L,
    scalar_words: quote.scalar_words + 6L,
  })
}

///|
fn run_evidence_admission_construction_for_bounds(
  bytes : Int,
  nodes : Int,
  depth : Int,
  data_keys? : Bool = false,
) -> RunEvidenceAdmissionConstruction? {
  let parser = if data_keys {
    @decode.preserving_json_parser_construction_inventory(bytes, nodes, depth)
  } else {
    @source.json_source_grammar_construction_extent(bytes, nodes, depth)
  }
  let conversion_text = if data_keys { 0 } else { bytes }
  guard parser is Some(parser) &&
    @json.source_conversion_construction_extent(
      nodes, nodes, nodes, nodes, depth, conversion_text,
    )
    is Some(conversion) &&
    @shape.add_collection_construction_extents(
      conversion.retained,
      conversion.scratch,
    )
    is Some(canonical) &&
    protocol_wire_validation_construction_extent(nodes.to_int64())
    is Some(validation) &&
    @encode.hash_writer_construction_inventory(nodes, depth) is Some(hash) &&
    @encode.text_writer_construction_inventory(bytes, nodes, depth)
    is Some(text) &&
    @shape.collection_construction_extent({
      // TWO emit_value parents arrays. Each depth owns a SyncEmitParent
      // variant and its one-reference/index cursor; growth backing12+3D is
      // supplied by the existing collection constructor, not writer units.
      records: 4L * depth.to_int64(),
      record_references: 4L * depth.to_int64(),
      record_words: 4L * depth.to_int64(),
      reference_arrays: 2L,
      reference_items: 2L * depth.to_int64(),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(emit) else {
    return None
  }
  // Domain carriers, co-counted even when their branches are sequential:
  // identity-kind Some, parse Ok, supplied-identity Some, preimage Some:
  // 4H/4R/4W; expected self-CID String:1H/71UTF16;
  // RunEvidenceValue:1H/5R; wire_usage Some+tuple:2H/1R/4W;
  // final Ok:1H/1R/1W; typed/nested error:2H/2R/2W;
  // the two serializer pop Somes:2H/2R/2W;
  // returned sizing record/Some:2H/2R/7W. Total15H/17R/20W.
  Some({
    // The returned evidence keeps ONE complete canonical forest, its final
    // wire String, supplied CID and registered kind. The second forest is
    // self-CID construction scratch, not an escaping retained tree.
    retained: {
      record_headers: conversion.retained.record_headers + 6L,
      reference_slots: conversion.retained.reference_slots + 7L,
      scalar_words: conversion.retained.scalar_words + 5L,
    },
    // Exact data keys borrow decoded input Strings, whose lifetime also
    // reaches the returned canonical value. Normalized keys are charged by
    // the conversion's own text inventory.
    retained_utf16_units: conversion.retained_utf16_units +
    (if data_keys { 2L } else { 1L }) * bytes.to_int64() +
    71L +
    Int::max("prepared_invocation".length(), "run_authorization".length()).to_int64(),
    record_headers: parser.record_headers +
    2L * canonical.record_headers +
    validation.record_headers +
    hash.record_headers +
    text.record_headers +
    emit.record_headers +
    15L,
    reference_slots: parser.reference_slots +
    2L * canonical.reference_slots +
    validation.reference_slots +
    hash.reference_slots +
    text.reference_slots +
    emit.reference_slots +
    17L,
    scalar_words: parser.scalar_words +
    2L * canonical.scalar_words +
    validation.scalar_words +
    hash.scalar_words +
    text.scalar_words +
    emit.scalar_words +
    20L,
    owned_utf16_units: parser.owned_utf16_units +
    2L * (conversion.retained_utf16_units + conversion.scratch_utf16_units) +
    hash.owned_utf16_units +
    text.owned_utf16_units +
    71L,
    // Original UTF8 encode(wire), separate from the incremental hash sink.
    owned_wire_bytes: bytes.to_int64() + hash.owned_wire_bytes,
  })
}
