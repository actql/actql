///|
/// Fixed Common empty journal constructor dependency. No output sampling and no
/// grant. Caller proves one Values producer, no parameters/completions/sorts.
/// Original graph/catalog and immutable protocol schema are borrowed owners.
priv struct ClosedValuesNormalizationLayout {
  retained : @execution.PreparationRepresentationUnits
  temporary : @execution.PreparationRepresentationUnits
}

///|
fn closed_values_normalization_layout(
  original_root_fields : Int,
) -> ClosedValuesNormalizationLayout? {
  if original_root_fields < 0 {
    return None
  }
  let journal = @publication.empty_normalization_journal_retained_layout()
  let validation = @publication.empty_normalization_validation_layout()
  let facts : ClosedValuesLexicalFacts = {
    input_bytes: 151,
    node_upper: 4,
    objects: 1,
    arrays: 1,
    fields_upper: 3,
    quoted_tokens: 5,
    quoted_utf16_units: 130,
    longest_quoted_utf16: 71,
    longest_atom_utf16: 0,
    depth_upper: 2,
  }
  let source = closed_values_source_inventories(facts)
  guard closed_values_map_constructor_layout(3) is Some(seen) &&
    closed_values_map_constructor_layout(original_root_fields)
    is Some(audit_map) &&
    @encode.hash_writer_construction_inventory(5, 2) is Some(writer) else {
    return None
  }
  // Common inventory(4R1W), entries empty Array, Common variant, issued record,
  // owner Some. Evidence/tree/wire are the publication owner's retained vector.
  let wrappers : @execution.PreparationRepresentationUnits = {
    record_headers: 6L,
    reference_slots: 10L,
    scalar_words: 5L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  guard @execution.compose_preparation_representation([
      wrappers,
      {
        record_headers: journal.record_headers,
        reference_slots: journal.reference_slots,
        scalar_words: journal.scalar_words,
        owned_utf16_units: journal.owned_utf16_units,
        owned_wire_bytes: 0L,
      },
    ])
    is Some(retained) else {
    return None
  }
  // Canonical admission: old three-field root (variant/FrozenArray/Array),
  // InputBudget, two map closures, two sort comparators, any closure; two
  // MutArrayViews. Sort sizes3/4 use pinned small-array sort path, no runs/buffer.
  // Two live recursive from_source frames each four refs and two scalar locals.
  // Final child/field tuples are already in retained, not recreated here.
  let admission : @execution.PreparationRepresentationUnits = {
    record_headers: 4L + 1L + 5L + 2L + 2L,
    reference_slots: 6L + 6L + 2L + 8L,
    scalar_words: 3L + 3L + 4L + 4L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // Two synchronous canonical emissions (hash then complete render). Each has
  // one Array plus old backing, at most two parent variants and cursor records,
  // two pop Some carriers. String cursor storage is in shared writer recipe.
  let emit : @execution.PreparationRepresentationUnits = {
    record_headers: 2L * (3L + 4L + 2L),
    reference_slots: 2L * (1L + 18L + 4L + 2L),
    scalar_words: 2L * (2L + 4L + 2L),
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // Audit: Budget; root ObjectView; original root Cursor, lookup Some; empty
  // expression SlotCollector+ExpressionSlots and Array; iterator tuple for one
  // unit; one stage/producer/step accessor Some each; final sort Some(Int).
  // Values has no general expression slots (expression_slots.mbt Values arm).
  let audit : @execution.PreparationRepresentationUnits = {
    record_headers: 1L + 1L + 1L + 1L + 2L + 2L + 1L + 3L + 1L,
    reference_slots: 3L + 1L + 1L + 3L + 1L + 2L + 3L,
    scalar_words: 1L + 2L + 1L + 3L + 2L + 3L + 2L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // Three writer scopes: body material, canonical hash, sealed material.
  // Hash recipe deliberately upper-bounds structural ownership of material
  // writers; add JS StringBuilder and old/new text explicitly for both.
  // Body String + its UTF8 copy coexist during issuance. Output239 is retained.
  let writers : @execution.PreparationRepresentationUnits = {
    record_headers: 3L * writer.record_headers + 2L * 4L + 2L,
    reference_slots: 3L * writer.reference_slots + 2L * 2L,
    scalar_words: 3L * writer.scalar_words + 2L,
    owned_utf16_units: 3L * writer.owned_utf16_units + 2L * (151L + 239L) + 151L,
    owned_wire_bytes: 3L * writer.owned_wire_bytes + 151L,
  }
  // Result/failure issuance edges: parse, canonical conversion, shape1, hash,
  // append, shape2, stringify, body writer, audit, outer issuer. Sum10 packets,
  // each domain issue +result carrier; scalar/reference payload alternatives.
  let carriers : @execution.PreparationRepresentationUnits = {
    record_headers: 20L,
    reference_slots: 20L,
    scalar_words: 40L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  guard @execution.compose_preparation_representation([
      source.source_retained,
      source.source_growth_peak,
      source.indexed_additional,
      source.key_admission_peak,
      source.parser_ancestry_peak,
      source.decoder_ancestry_peak,
      source.parser_controls_peak,
      source.decoder_controls_peak,
      seen,
      audit_map,
      admission,
      emit,
      audit,
      writers,
      carriers,
      {
        record_headers: validation.record_headers,
        reference_slots: validation.reference_slots,
        scalar_words: validation.scalar_words,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
    ])
    is Some(temporary) else {
    return None
  }
  Some({ retained, temporary, })
}
