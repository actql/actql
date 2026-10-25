///|
/// One parse_plan_identity_value call, before construction. `value` survives
/// that call; `temporary` is private parser/admission storage. Neither is a
/// final Run holding by itself. The caller owns original emitted wire text.
priv struct CompilationParseLayout {
  value : PreparationRepresentationUnits
  temporary : PreparationRepresentationUnits
}

///|
fn compilation_parse_layout(
  facts : ClosedValuesLexicalFacts,
  largest_object : Int,
) -> CompilationParseLayout? {
  if facts.input_bytes < 0 ||
    facts.node_upper < 1 ||
    facts.quoted_tokens < 0 ||
    facts.quoted_utf16_units < 0 ||
    facts.longest_quoted_utf16 < 0 ||
    facts.longest_atom_utf16 < 0 ||
    facts.fields_upper < 0 {
    return None
  }
  guard compilation_canonical_layout({
      nodes: facts.node_upper,
      arrays: facts.arrays,
      objects: facts.objects,
      fields: facts.fields_upper,
      depth: facts.depth_upper,
      largest_object,
    })
    is Some(canonical) else {
    return None
  }
  let source = closed_values_source_inventories(facts)
  // Only decoded keys/String values are borrowed by CanonicalValue; its source
  // Span/Field/Node/container records do not escape from_source. ASCII owner
  // keys pass NFC quick-check unchanged. No indexed Cursor exists on this path.
  let text : PreparationRepresentationUnits = {
    record_headers: facts.quoted_tokens.to_int64(),
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: facts.quoted_utf16_units.to_int64(),
    owned_wire_bytes: 0L,
  }
  guard closed_values_units_subtract(source.source_retained, text)
    is Some(private_ast) &&
    closed_values_js_bytes_document_layout(facts.input_bytes.to_int64(), 1)
    is Some(document) &&
    closed_values_sum_layouts([canonical.tree, text]) is Some(value) else {
    return None
  }
  // PinnedJS utf8.encode accepts a StringView and calls src.slice before
  // TextEncoder: retain view(1ref2words), possible sliceString and Bytes owner.
  // TextEncoder itself is a module singleton. Source parse-bytes also owns its
  // decoded document and views; that document is not the original emitter wire.
  let encoded : PreparationRepresentationUnits = {
    record_headers: 3L,
    reference_slots: 1L,
    scalar_words: 2L,
    owned_utf16_units: facts.input_bytes.to_int64(),
    owned_wire_bytes: facts.input_bytes.to_int64(),
  }
  guard closed_values_sum_layouts([
      private_ast,
      source.source_growth_peak,
      source.key_admission_peak,
      source.parser_ancestry_peak,
      source.parser_controls_peak,
      canonical.temporary,
      document,
      encoded,
    ])
    is Some(temporary) else {
    return None
  }
  Some({ value, temporary, })
}

///|
/// Metadata-stripped Program serializer, on the original one-stage/no-meta
/// source. Existing identity emitter storage already bounds two simultaneous
/// field-list/Cursor/sort ancestries; reuse it conservatively for this single
/// emitter, adding its recursive control arguments and annotation views.
fn compilation_program_emitter_layout(
  facts : ClosedValuesLexicalFacts,
  largest_object : Int,
) -> PreparationRepresentationUnits? {
  guard closed_values_identity_emitter_layout(
      facts.node_upper,
      largest_object,
      facts.depth_upper,
    )
    is Some(fields) &&
    closed_values_map_constructor_layout(4) is Some(view_map) &&
    closed_values_map_constructor_layout(0) is Some(omitted) else {
    return None
  }
  let d = facts.depth_upper.to_int64() + 1L
  // Twelve open_object sites/iterations on the fixed root/Stage/declaration/
  // step traversal; each has <=4fields. Result/lookup/Cursor carriers plus
  // ObjectView are counted beside their own map. Empty omissions never grow.
  // Three literal name arrays (root3, Stage3, fields of shared wrapper) are
  // bounded by three eight-slot arrays, including conservative growth backing.
  let controls : PreparationRepresentationUnits = {
    record_headers: 12L * 4L + 3L * 3L + d,
    reference_slots: 12L * 5L + 3L * 9L + 6L * d,
    scalar_words: 12L * 3L + 3L * 2L + 3L * d,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let maps : PreparationRepresentationUnits = {
    record_headers: 12L * view_map.record_headers,
    reference_slots: 12L * view_map.reference_slots,
    scalar_words: 12L *
    (view_map.scalar_words + view_map.reference_slots - 2L - 24L),
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let empty_tags : PreparationRepresentationUnits = {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: omitted.reference_slots - 2L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  closed_values_sum_layouts([fields, maps, omitted, empty_tags, controls])
}
