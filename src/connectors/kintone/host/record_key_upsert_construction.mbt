///|
/// Price the native proposal and its original lookup construction. The
/// physical caller separately adds ingress, Form/target replies and transport.
pub fn record_key_upsert_proposal_construction_capacity(
  mapping : RecordKeyUpsertMapping,
  max_input_bytes : Int,
  write : @catalog.RecordWriteLimits,
  request : @catalog.RecordMutationLimits,
  lookup : @catalog.RecordLookupLimits,
) -> @execution.ExecutionCapacity? {
  guard mapping.self is Some(original) && physical_equal(mapping, original) else {
    return None
  }
  let names = mapping.original.names
  if !names.contains(mapping.key) ||
    lookup.max_key_bytes < 1 ||
    lookup.max_columns < names.length() ||
    lookup.max_columns > 998 ||
    lookup.max_comparison_work < 1 ||
    lookup.max_request_bytes < 1 ||
    lookup.max_request_nodes < 1 ||
    lookup.max_request_depth < 1 {
    return None
  }
  guard record_mutation_proposal_values_inventory(
      mapping.original,
      mapping.fields.length(),
      max_input_bytes,
      write,
      request,
    )
    is Some(values) else {
    return None
  }
  let n = names.length().to_int64()
  let f = mapping.fields.length().to_int64()
  let key = mapping.key.length().to_int64()
  let input = lookup.max_key_bytes.to_int64()
  // The pinned nonempty-pattern replacements borrow StringView slices and
  // allocate a next-match Option. Charge both passes at up to N+1 segments
  // each, with their successive views, match controls and cursor words.
  let escape_segments = 2L * (input + 1L)
  // The exact declaration already contains the key. Each String is quoted in
  // one place; JSON escapes take at most six bytes per original UTF16 unit.
  // The provider's query escapes the input first, using at most two units per
  // original unit. The fixed envelope and query grammar fit 128 bytes.
  let mut query_bound = 128L +
    6L * (key + 2L * input) +
    6L * mapping.original.catalog.app_id.length().to_int64()
  for name in names {
    query_bound += 3L + 6L * name.length().to_int64()
  }
  let wire = Int64::min(lookup.max_request_bytes.to_int64(), query_bound).to_int()
  // LookupRequest, encoded body and selected field array survive. The App,
  // key, input identity and field-code backing remain with their original owner.
  // Derive the backing bound from the actual selected count and the pinned
  // grow-only Array rule. The replaced backing stays in workspace below.
  guard @shape.reference_array_push_construction_extent(
      names.length() - 1,
      names.length() - 1,
    )
    is Some(growth) &&
    @shape.reference_array_retained_extent(1L, growth.reference_slots)
    is Some(retained_array) &&
    @shape.collection_construction_extent({
      // Selected-name checks own per-field singleton paths and metadata Options.
      // Checked-cell field iteration owns one Option and pair per visited cell.
      // Include the typed failure and all intermediate query/String controls.
      records: 24L + 5L * n + 4L * f + 6L * escape_segments,
      record_references: 30L + 8L * n + 5L * f + 6L * escape_segments,
      record_words: 22L + 4L * n + 4L * f + 12L * escape_segments,
      reference_arrays: n + 3L,
      reference_items: 2L * n + 4L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 1L,
      map_entries: n,
    })
    is Some(controls) &&
    @encode.text_writer_live_key_inventory(
      wire,
      4,
      Int::min(lookup.max_request_depth, 2),
    )
    is Some(writer) else {
    return None
  }
  guard @execution.compose_preparation_representation([
      values.retained,
      {
        record_headers: retained_array.record_headers + 6L,
        reference_slots: retained_array.reference_slots + 9L,
        scalar_words: retained_array.scalar_words + 6L,
        owned_utf16_units: wire.to_int64(),
        owned_wire_bytes: 0L,
      },
    ])
    is Some(retained) &&
    @execution.compose_preparation_representation([
      values.workspace,
      record_read_collection_units(controls),
      {
        record_headers: writer.record_headers,
        reference_slots: writer.reference_slots,
        scalar_words: writer.scalar_words,
        // Two replacement passes plus the bounded concatenations of the query
        // can overlap the writer. The separate UTF8 validation may use 3 bytes
        // per input UTF16 unit before its positive byte-bound check returns.
        owned_utf16_units: writer.owned_utf16_units + 24L * (key + input + 12L),
        owned_wire_bytes: 3L * input,
      },
    ])
    is Some(workspace) else {
    return None
  }
  update_construction_capacity({ retained, workspace, })
}

///|
/// Parse the bounded lookup response and retain only the established before
/// state. The lookup request and mapped values remain with the proposal owner.
pub fn record_key_upsert_before_construction_capacity(
  mapping : RecordKeyUpsertMapping,
  body_bytes : Int,
  pages : @catalog.RecordPageLimits,
  values : @catalog.RecordValueLimits,
  limits : @catalog.RecordMutationLimits,
) -> @execution.ExecutionCapacity? {
  guard mapping.self is Some(original) && physical_equal(mapping, original) else {
    return None
  }
  if pages.max_rows < 1 ||
    pages.max_rows > 2 ||
    body_bytes < 1 ||
    body_bytes > pages.max_bytes ||
    !record_target_before_limits_valid(limits) {
    return None
  }
  let fields = mapping.original.names
  guard record_target_before_construction_inventory(
      mapping.original,
      fields,
      body_bytes,
      pages,
      values,
      limits,
    )
    is Some(base) &&
    @shape.collection_construction_extent({
      // Lookup/Before hosts two original-page array copies and the three
      // validation identity strings. Their cells are all borrowed.
      records: 18L,
      record_references: 28L,
      record_words: 22L,
      reference_arrays: 4L,
      reference_items: fields.length().to_int64() + 6L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(ctrl) &&
    @execution.compose_preparation_representation([
      base.retained,
      {
        ..update_construction_empty(),
        record_headers: 4L,
        reference_slots: 9L,
        scalar_words: 5L,
      },
    ])
    is Some(retained) &&
    @execution.compose_preparation_representation([
      base.workspace,
      {
        ..record_read_collection_units(ctrl),
        owned_wire_bytes: 3L * limits.max_identity_bytes.to_int64(),
      },
    ])
    is Some(workspace) else {
    return None
  }
  update_construction_capacity({ retained, workspace, })
}
