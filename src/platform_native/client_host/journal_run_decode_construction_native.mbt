///|
// Run rows do not contain a Submitted intent. Their only nested admission is
// the existing bounded request/Definition identity pair. Keep those dimensions
// independent of the potentially large observation String.
fn journal_run_units(
  headers : Int64,
  references : Int64,
  words : Int64,
  text : Int64,
  wire : Int64,
) -> @execution.PreparationRepresentationUnits {
  {
    record_headers: headers,
    reference_slots: references,
    scalar_words: words,
    owned_utf16_units: text,
    owned_wire_bytes: wire,
  }
}

///|
fn journal_run_request_construction() -> @execution.PreparationRepresentationUnits? {
  guard @decode.preserving_json_admission_construction_inventory(4096, 32, 2)
    is Some(parser) &&
    @canonical_value.nfc_lf_construction_extent(256) is Some(caller) &&
    @encode.hash_writer_construction_inventory(4, 1) is Some(scope) &&
    @encode.text_writer_construction_inventory(1024, 5, 1) is Some(intent) &&
    @encode.hash_writer_construction_inventory(0, 0) is Some(digest) &&
    @encode.text_writer_construction_inventory(4096, 32, 2) is Some(record) &&
    @shape.collection_construction_extent({
      // request and scope records; two copied CID Strings/UInt16 arrays;
      // seven field tuples and their Array; returned pair/Result carriers.
      records: 2L + 2L + 7L + 4L,
      record_references: 7L + 3L + 2L + 14L + 8L,
      record_words: 4L,
      reference_arrays: 1L,
      reference_items: 7L,
      scalar_arrays: 2L,
      scalar_items: 2L * 71L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(records) else {
    return None
  }
  @execution.compose_preparation_representation([
    journal_run_units(
      parser.record_headers,
      parser.reference_slots,
      parser.scalar_words,
      parser.owned_utf16_units,
      4096L,
    ),
    journal_run_units(
      caller.record_headers,
      caller.reference_slots,
      caller.scalar_words,
      caller.owned_utf16_units,
      3L * 256L,
    ),
    journal_run_units(
      scope.record_headers,
      scope.reference_slots,
      scope.scalar_words,
      scope.owned_utf16_units,
      scope.owned_wire_bytes,
    ),
    journal_run_units(
      intent.record_headers,
      intent.reference_slots,
      intent.scalar_words,
      intent.owned_utf16_units,
      1024L,
    ),
    // One-shot SHA uses the same Hasher/digest/hex family, no input copy.
    journal_run_units(
      digest.record_headers,
      digest.reference_slots,
      digest.scalar_words,
      digest.owned_utf16_units,
      digest.owned_wire_bytes,
    ),
    journal_run_units(
      record.record_headers,
      record.reference_slots,
      record.scalar_words,
      record.owned_utf16_units,
      0L,
    ),
    journal_run_units(
      records.record_headers,
      records.reference_slots,
      records.scalar_words,
      4L * 71L,
      0L,
    ),
  ])
}

///|
fn journal_run_definition_construction() -> @execution.PreparationRepresentationUnits? {
  // These are the unchanged decode_client_journal_definition limits, including
  // malformed input BEFORE the flat run_definition shape rejects it.
  let n = 4096L
  let d = 65L
  guard @source.json_source_grammar_construction_extent(65536, 4096, 64)
    is Some(parser) &&
    @canonical_value.nfc_lf_construction_extent(65536) is Some(keys) &&
    @encode.hash_writer_construction_inventory(4096, 64) is Some(identity) &&
    @encode.text_writer_construction_inventory(65536, 4096, 64) is Some(wire) &&
    @shape.collection_construction_extent({
      // from_source: value/field tuple, recursive control carriers, sorted
      // FrozenArray backing and one active duplicate-key Map per object.
      records: 2L * n + 8L * d + 1L,
      record_references: 4L * n + 16L * d,
      record_words: 3L * n + 12L * d,
      reference_arrays: 2L * n + 1L,
      reference_items: 3L * n,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: Int64::min(n, d),
      map_entries: n,
    })
    is Some(canonical) &&
    @shape.collection_construction_extent({
      // contract_spec's nine field/rule records, spec, detached object_fields,
      // allowed keys, identity preimage and returned PublicationContract.
      // Copies before shape rejection use n; successful preimage <=11 fields.
      records: 9L + 9L + 1L + n + 11L + 1L,
      record_references: 3L * 9L + 9L + 4L + 2L * n + 2L * 11L + 5L,
      record_words: 9L + 4L,
      reference_arrays: 4L,
      reference_items: 9L + n + 11L + 11L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(validation) else {
    return None
  }
  @execution.compose_preparation_representation([
    journal_run_units(
      parser.record_headers,
      parser.reference_slots,
      parser.scalar_words,
      parser.owned_utf16_units,
      0L,
    ),
    journal_run_units(
      canonical.record_headers,
      canonical.reference_slots,
      canonical.scalar_words,
      0L,
      0L,
    ),
    // Canonical conversion normalizes keys again, sequentially. Sum retained
    // normalized keys plus one maximum workspace, not one workspace per node.
    journal_run_units(
      keys.record_headers + n,
      keys.reference_slots,
      keys.scalar_words,
      keys.owned_utf16_units + keys.max_output_utf16_units,
      0L,
    ),
    journal_run_units(
      validation.record_headers,
      validation.reference_slots,
      validation.scalar_words,
      0L,
      0L,
    ),
    journal_run_units(
      identity.record_headers,
      identity.reference_slots,
      identity.scalar_words,
      identity.owned_utf16_units,
      identity.owned_wire_bytes,
    ),
    journal_run_units(
      wire.record_headers,
      wire.reference_slots,
      wire.scalar_words,
      wire.owned_utf16_units,
      0L,
    ),
  ])
}

///|
fn journal_run_decode_working(
  stage : @host.ClientRunJournalConstruction,
) -> (Int64, Int64, Int64)? {
  let (bytes, text, nodes, depth, parsing) = match stage {
    @host.RunJournalParse(bytes) => (bytes, 0L, 32, 4, true)
    @host.RunJournalCanonical(bytes, text, nodes, depth) =>
      (bytes, text, nodes, depth, false)
    @host.RunJournalRetained(bytes, text, nodes, depth) =>
      (bytes, text, nodes, depth, false)
  }
  if bytes <= 0 ||
    bytes >= 2147483519 ||
    nodes < 1 ||
    nodes > 32 ||
    depth < 0 ||
    depth > 4 ||
    text < 0L ||
    text > 2L * bytes.to_int64() {
    return None
  }
  guard @decode.preserving_json_admission_construction_inventory(bytes, 32, 4)
    is Some(outer) &&
    @encode.text_writer_construction_inventory(bytes, 32, 4) is Some(comparison) &&
    journal_run_request_construction() is Some(request) &&
    journal_run_definition_construction() is Some(definition) else {
    return None
  }
  // Accepted definition is a flat object of <=11 strings. Input/source rows
  // and request/definition returned text remain alive beside the row writer.
  let retained_units = journal_run_units(
    32L + 3L * 32L + 2L * 32L + 2L * 12L,
    64L + 4L * 32L + 4L * 32L + 4L * 12L,
    32L + 8L * 32L + 6L * 32L,
    2L * bytes.to_int64() +
    (if parsing { 0L } else { 4096L + 65536L + 4L * 71L }),
    bytes.to_int64(),
  )
  let outer_units = journal_run_units(
    outer.record_headers,
    outer.reference_slots,
    outer.scalar_words,
    outer.owned_utf16_units,
    0L,
  )
  let scratch = if parsing {
    Some(outer_units)
  } else {
    @execution.compose_preparation_representation([
      outer_units,
      request,
      definition,
      journal_run_units(
        comparison.record_headers + 1L,
        comparison.reference_slots + 3L,
        comparison.scalar_words + 2L,
        comparison.owned_utf16_units,
        bytes.to_int64(),
      ),
    ])
  }
  guard scratch is Some(scratch) &&
    @execution.preparation_representation_cost(retained_units) is Some(retained) &&
    @execution.compose_preparation_representation([retained_units, scratch])
    is Some(total) &&
    @execution.preparation_representation_cost(total) is Some(execution) else {
    return None
  }
  let (header, unit, terminator, array_header, pointer) = @bootstrap.native_managed_value_layout()
  if header <= 0L || unit != 2L || terminator != unit || pointer < 4L {
    return None
  }
  // Pinned UTF16 builder doubling; normalization's largest text is <=4U.
  // Canonical decomposition uses <=4U scalars, each <=pointer bytes. Its
  // Array old/new growth bound12+3N also bounds any single allocation.
  let normalized_units = if parsing { 0L } else { 4L * 65536L }
  let max_text = Int64::max(bytes.to_int64(), normalized_units)
  let mut capacity = 1L
  while capacity < max_text {
    capacity *= 2L
  }
  let scalar_items = if parsing { 0L } else { 12L + 3L * 4L * 65536L }
  // The full Map bucket/backing bound18+11N covers a single allocation too;
  // these are actual pointer slots, not an R/E quantity recast as raw bytes.
  let map_items = 18L + 11L * (if parsing { 32L } else { 4096L })
  let raw = Int64::max(
    header + (capacity + 1L) * unit,
    array_header + Int64::max(scalar_items, map_items) * pointer,
  )
  Some((retained, execution, raw))
}
