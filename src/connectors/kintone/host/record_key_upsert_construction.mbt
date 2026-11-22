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
/// Both Form path copies and the observed Form retire with the recheck.
pub fn record_key_upsert_form_construction_capacity(
  mapping : RecordKeyUpsertMapping,
  body_bytes : Int,
  limits : @catalog.FormFieldLimits,
) -> @execution.ExecutionCapacity? {
  guard record_key_upsert_mapping_matches_declaration(mapping, mapping.original) &&
    managed_record_form_inventory(mapping.original, body_bytes, limits)
    is Some(workspace) else {
    return None
  }
  update_construction_capacity({
    retained: update_construction_empty(),
    workspace,
  })
}

///|
/// Outcome capacity covers the one original CREATE or revision-checked UPDATE.
pub fn record_key_upsert_response_construction_capacity(
  mapping : RecordKeyUpsertMapping,
  body_bytes : Int,
  limits : @catalog.RecordMutationLimits,
) -> @execution.ExecutionCapacity? {
  guard record_key_upsert_mapping_matches_declaration(mapping, mapping.original) &&
    record_mutation_response_construction_inventory(
      mapping.original.names.length(),
      body_bytes,
      limits,
      true,
    )
    is Some(inventory) else {
    return None
  }
  update_construction_capacity(inventory)
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

///|
fn record_key_upsert_request_checks(
  count : Int,
) -> @shape.CollectionConstructionExtent? {
  let fields = count.to_int64()
  let utf8 = @scalar.utf8_length_admission_construction_units()
  @shape.collection_construction_extent({
    // The Form/key validation and the comparisons borrow all original text.
    // The UTF8 passes are synchronous and use the same scalar admission owner.
    records: 16L + utf8.0 + 4L * fields,
    record_references: 20L + utf8.1 + 6L * fields,
    record_words: 20L + utf8.2 + 6L * fields,
    reference_arrays: 3L + 2L * fields,
    reference_items: 3L + 4L * fields,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  })
}

///|
/// Quote the revision-checked PUT selected by this proposal's original Before.
/// The retained proposal cells, lookup and observed target stay with their
/// existing owners. Absent Before requires the separate create inventory.
pub fn record_key_upsert_update_construction_capacity(
  proposal : RecordKeyUpsertProposal,
  before : RecordKeyUpsertBefore,
  limits : @catalog.RecordMutationLimits,
) -> @execution.ExecutionCapacity? {
  guard record_key_upsert_has_original_before(proposal, before) &&
    before.target is Some(_) else {
    return None
  }
  record_key_upsert_update_request_capacity(proposal.mapping, limits)
}

///|
fn record_key_upsert_update_request_capacity(
  mapping : RecordKeyUpsertMapping,
  limits : @catalog.RecordMutationLimits,
) -> @execution.ExecutionCapacity? {
  guard record_target_before_limits_valid(limits) && limits.max_records == 1 else {
    return None
  }
  let count = mapping.fields.length()
  guard record_update_request_construction_inventory(count, limits)
    is Some(update) &&
    record_key_upsert_request_checks(count) is Some(checks) &&
    @execution.compose_preparation_representation([
      update.retained,
      {
        ..update_construction_empty(),
        record_headers: 3L,
        reference_slots: 6L,
        scalar_words: 2L,
      },
    ])
    is Some(retained) &&
    @execution.compose_preparation_representation([
      update.workspace,
      record_read_collection_units(checks),
    ])
    is Some(workspace) else {
    return None
  }
  update_construction_capacity({ retained, workspace, })
}

///|
/// Quote CREATE from the original complete absence. The source cells are
/// already checked and retained. Only the appended key carrier, the new
/// checked-cell vector and the two native documents outlive construction.
pub fn record_key_upsert_create_construction_capacity(
  proposal : RecordKeyUpsertProposal,
  before : RecordKeyUpsertBefore,
  write : @catalog.RecordWriteLimits,
  limits : @catalog.RecordMutationLimits,
) -> @execution.ExecutionCapacity? {
  guard record_key_upsert_has_original_before(proposal, before) &&
    before.target is None else {
    return None
  }
  record_key_upsert_create_request_capacity(proposal.mapping, write, limits)
}

///|
fn record_key_upsert_create_request_capacity(
  mapping : RecordKeyUpsertMapping,
  write : @catalog.RecordWriteLimits,
  limits : @catalog.RecordMutationLimits,
) -> @execution.ExecutionCapacity? {
  guard record_target_before_limits_valid(limits) &&
    limits.max_records == 1 &&
    write.max_fields > 0 &&
    write.max_name_bytes > 0 &&
    write.max_nodes > 0 &&
    write.max_depth > 0 &&
    write.max_text_bytes > 0 &&
    write.max_output_bytes > 0 else {
    return None
  }
  let selected = mapping.fields.length()
  let catalog = mapping.original.catalog
  let form_fields = @catalog.form_field_count(catalog)
  // The copied input always has room for one additional key. The admitted
  // prefix of the new native value vector is bounded separately.
  let cells = selected.to_int64() + 1L
  let count = Int64::min(
    cells,
    Int::min(write.max_fields, write.max_nodes).to_int64(),
  ).to_int()
  let fields = count.to_int64()
  let required = Int::min(form_fields, write.max_fields).to_int64()
  let copied = @catalog.record_create_copied_target_bound(
    catalog,
    write.max_fields,
    limits.max_comparison_work,
  ).to_int64()
  guard @shape.reference_array_push_construction_extent(count - 1, count - 1)
    is Some(growth) &&
    @shape.reference_array_retained_extent(2L, growth.reference_slots + 1L)
    is Some(arrays) &&
    record_key_upsert_request_checks(selected) is Some(checks) &&
    @shape.collection_construction_extent({
      // Cell copy and growth, required-code projection, checked tuples and
      // per-field Contract/recheck controls. Original cell bodies are borrowed.
      records: 22L + 10L * fields + 6L * required,
      record_references: 26L + 18L * fields + 10L * required,
      record_words: 23L + 14L * fields + 5L * required,
      reference_arrays: 5L + 2L * fields,
      reference_items: cells + 4L * fields + required + 2L,
      scalar_arrays: 3L,
      scalar_items: 28L,
      maps: 2L,
      map_entries: copied + fields,
    })
    is Some(controls) &&
    record_write_value_construction_extents(mapping.original, write)
    is Some((_, traversal)) &&
    record_read_writer_units(
      write.max_output_bytes,
      write.max_nodes,
      write.max_depth,
    )
    is Some(value_writer) &&
    record_read_writer_units(
      limits.max_output_bytes,
      limits.max_output_nodes,
      limits.max_output_depth,
    )
    is Some(request_writer) &&
    @execution.compose_preparation_representation([
      record_read_collection_units(checks),
      record_read_collection_units(controls),
      record_read_collection_units(traversal),
      value_writer,
      request_writer,
      {
        ..update_construction_empty(),
        // Native Timestamp emission temporarily holds its substring and UTC spelling.
        owned_utf16_units: 39L,
      },
    ])
    is Some(workspace) else {
    return None
  }
  let retained : @execution.PreparationRepresentationUnits = {
    record_headers: arrays.record_headers + fields + 14L,
    reference_slots: arrays.reference_slots + 2L * fields + 21L,
    scalar_words: arrays.scalar_words + 10L,
    owned_utf16_units: write.max_output_bytes.to_int64() +
    limits.max_output_bytes.to_int64(),
    owned_wire_bytes: 0L,
  }
  update_construction_capacity({ retained, workspace, })
}

///|
/// Budget finalization before any target has been read. Exactly one original
/// branch can be constructed, so use the larger branch per dimension.
pub fn record_key_upsert_finalization_construction_capacity(
  mapping : RecordKeyUpsertMapping,
  write : @catalog.RecordWriteLimits,
  limits : @catalog.RecordMutationLimits,
) -> @execution.ExecutionCapacity? {
  guard mapping.self is Some(original) &&
    physical_equal(mapping, original) &&
    record_key_upsert_create_request_capacity(mapping, write, limits)
    is Some(insert) &&
    record_key_upsert_update_request_capacity(mapping, limits) is Some(update) else {
    return None
  }
  @execution.execution_capacity(
    Int64::max(
      @execution.execution_capacity_retained_bytes(insert),
      @execution.execution_capacity_retained_bytes(update),
    ),
    Int64::max(
      @execution.execution_capacity_execution_bytes(insert),
      @execution.execution_capacity_execution_bytes(update),
    ),
  )
}

///|
/// Cold native recovery borrows the saved bytes and returns the rebuilt
/// proposal, Before and request together. Only their retained allocations
/// overlap the following phase; each constructor's synchronous parser or
/// writer has returned before the next phase begins. Host saved envelopes,
/// digests and transport have their own caller-side allowances.
pub fn record_key_upsert_recovery_construction_capacity(
  mapping : RecordKeyUpsertMapping,
  target_bytes : Int,
  max_input_bytes : Int,
  lookup : @catalog.RecordLookupLimits,
  pages : @catalog.RecordPageLimits,
  values : @catalog.RecordValueLimits,
  write : @catalog.RecordWriteLimits,
  request_limits : @catalog.RecordMutationLimits,
  before_limits : @catalog.RecordMutationLimits,
) -> @execution.ExecutionCapacity? {
  let utf8 = @scalar.utf8_length_admission_construction_units()
  // Tuple and Result retain the three native outputs. The original outer
  // guard and branch/body comparison borrow text and keep no new byte array.
  guard update_construction_capacity({
      retained: {
        ..update_construction_empty(),
        record_headers: 2L,
        reference_slots: 4L,
        scalar_words: 1L,
      },
      workspace: {
        ..update_construction_empty(),
        record_headers: 14L + utf8.0,
        reference_slots: 14L + utf8.1,
        scalar_words: 10L + utf8.2,
      },
    })
    is Some(controls) &&
    record_key_upsert_proposal_construction_capacity(
      mapping, max_input_bytes, write, request_limits, lookup,
    )
    is Some(proposal) &&
    record_key_upsert_before_construction_capacity(
      mapping, target_bytes, pages, values, before_limits,
    )
    is Some(before) &&
    record_key_upsert_finalization_construction_capacity(
      mapping, write, request_limits,
    )
    is Some(request) else {
    return None
  }
  let proposal_bytes = @execution.execution_capacity_retained_bytes(proposal)
  let before_bytes = @execution.execution_capacity_retained_bytes(before)
  guard @execution.execution_capacity(proposal_bytes, proposal_bytes)
    is Some(held_proposal) &&
    @execution.execution_capacity(before_bytes, before_bytes)
    is Some(held_before) &&
    @execution.add_execution_capacity(held_proposal, before)
    is Some(before_peak) &&
    @execution.add_execution_capacity(held_proposal, held_before)
    is Some(held_inputs) &&
    @execution.add_execution_capacity(held_inputs, request)
    is Some(request_peak) &&
    @execution.execution_capacity(
      @execution.execution_capacity_retained_bytes(request_peak),
      Int64::max(
        @execution.execution_capacity_execution_bytes(proposal),
        Int64::max(
          @execution.execution_capacity_execution_bytes(before_peak),
          @execution.execution_capacity_execution_bytes(request_peak),
        ),
      ),
    )
    is Some(native) else {
    return None
  }
  @execution.add_execution_capacity(native, controls)
}
