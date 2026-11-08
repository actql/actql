///|
// Owned writer/continuation state before one schema transition. Checked
// contracts and unqualified field strings remain borrowed. This neither
// traverses contracts nor emits/hash-parses a second schema to quote it.
fn relation_schema_identity_next_inventory(
  value : RelationSchemaIdentityPreparation,
) -> PreparationRepresentationUnits? {
  guard !value.closed &&
    !value.measurement_only &&
    value.hash_writer is Some(hash_writer) &&
    value.wire_writer is Some(wire_writer) &&
    value.schema is Some(schema) else {
    return None
  }
  // A checked emitter transition emits one bounded Text/key fragment or a
  // fixed vocabulary wrapper. Conditional fields add at most two nodes and
  // two container levels. Eight/four also cover final wrappers/refusal.
  let hash = if value.identity is Some(_) {
    let (_, nodes, depth) = @encode.observed_writer_usage(hash_writer)
    @encode.hash_writer_live_key_inventory(nodes, depth)
  } else {
    @encode.hash_writer_next_construction_inventory(hash_writer, 8, 4)
  }
  let text = if value.identity is Some(_) {
    let (bytes, nodes, depth) = @encode.observed_writer_usage(wire_writer)
    @encode.text_writer_construction_inventory(bytes, Int::max(1, nodes), depth)
  } else {
    @encode.text_writer_next_construction_inventory(
      wire_writer,
      @admitted.wire_emit_fragment_byte_bound(),
      8,
      4,
    )
  }
  let cursor = match value.contract {
    Some(cursor) => @contract.checked_emission_next_construction_extent(cursor)
    None => @contract.checked_emission_construction_extent(1)
  }
  guard hash is Some(hash) &&
    text is Some(text) &&
    cursor is Some(cursor) &&
    @shape.reference_array_push_construction_extent(
      value.names.length(),
      value.names.capacity(),
    )
    is Some(push) &&
    @shape.reference_array_retained_extent(
      1L,
      value.names.capacity().to_int64(),
    )
    is Some(retained_names) &&
    @shape.add_collection_construction_extents(push, retained_names)
    is Some(names) else {
    return None
  }
  // Qualification creates original reference-name Strings. Charge only
  // fields already reached plus the next one, independently for hash, wire
  // and retained-name phases; no max_fields/max_bytes allocation is assumed.
  let mut name_headers = value.name_headers
  let mut name_utf16 = value.name_utf16
  let next_name = if value.phase == 1 && value.field < value.fields {
    Some(value.field)
  } else if value.phase == 6 && value.names.length() < value.fields {
    Some(value.names.length())
  } else {
    None
  }
  if next_name is Some(index) {
    guard @schema.field_at(schema, index) is Some(field) else { return None }
    let name = @schema.reference_name_construction_extent(field.name)
    name_headers += name.scratch.record_headers
    name_utf16 += name.scratch_utf16_units
  }
  // Preparation, key/contract option carriers, receipt/finish tuple and the
  // fixed transient field/phase observations coexist with these constructors.
  Some({
    record_headers: 12L +
    hash.record_headers +
    text.record_headers +
    cursor.record_headers +
    names.record_headers +
    name_headers,
    reference_slots: 30L +
    hash.reference_slots +
    text.reference_slots +
    cursor.reference_slots +
    names.reference_slots,
    scalar_words: 20L +
    hash.scalar_words +
    text.scalar_words +
    cursor.scalar_words +
    names.scalar_words,
    owned_utf16_units: hash.owned_utf16_units +
    text.owned_utf16_units +
    name_utf16,
    owned_wire_bytes: hash.owned_wire_bytes,
  })
}
