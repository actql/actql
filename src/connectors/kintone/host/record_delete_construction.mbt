///|
/// Comparison queries own a temporary concatenation and a returned JSON body.
/// The selected Mapping, API ID and Form fields remain borrowed.
pub fn record_delete_target_read_construction_capacity(
  mapping : RecordDeleteMapping,
  max_fields : Int,
  limits : @catalog.RecordMutationLimits,
) -> @execution.ExecutionCapacity? {
  if !record_delete_mapping_is_original(mapping) ||
    !record_target_before_limits_valid(limits) ||
    max_fields <= 0 ||
    mapping.before_fields.length() > Int::min(max_fields, 998) {
    return None
  }
  guard record_read_writer_units(
      limits.max_output_bytes,
      limits.max_output_nodes,
      limits.max_output_depth,
    )
    is Some(writer) else {
    return None
  }
  let query_units = Int64::min(
    limits.max_output_bytes.to_int64(),
    limits.max_identity_bytes.to_int64() +
    "$id in () order by $id asc limit 1".length().to_int64(),
  )
  guard @execution.compose_preparation_representation([
      writer,
      {
        ..update_construction_empty(),
        record_headers: 6L,
        reference_slots: 8L,
        scalar_words: 4L,
        owned_utf16_units: 2L * query_units,
      },
    ])
    is Some(workspace) else {
    return None
  }
  update_construction_capacity({
    retained: {
      ..update_construction_empty(),
      record_headers: 2L,
      reference_slots: 2L,
      owned_utf16_units: limits.max_output_bytes.to_int64(),
    },
    workspace,
  })
}

///|
/// Form metadata is borrowed. The original comparison leaves only Unit.
pub fn record_delete_form_construction_capacity(
  mapping : RecordDeleteMapping,
  body_bytes : Int,
  limits : @catalog.FormFieldLimits,
) -> @execution.ExecutionCapacity? {
  if !record_delete_mapping_is_original(mapping) {
    return None
  }
  guard managed_record_form_inventory(mapping.original, body_bytes, limits)
    is Some(workspace) else {
    return None
  }
  update_construction_capacity({
    retained: update_construction_empty(),
    workspace,
  })
}

///|
/// The same before capture supplies the page, checked row, before wire and
/// revision. The DELETE request adds its own writer, document and copied
/// one-target vector, while sharing the original target and its Strings.
pub fn record_delete_target_construction_capacity(
  mapping : RecordDeleteMapping,
  body_bytes : Int,
  pages : @catalog.RecordPageLimits,
  values : @catalog.RecordValueLimits,
  limits : @catalog.RecordMutationLimits,
) -> @execution.ExecutionCapacity? {
  if !record_delete_mapping_is_original(mapping) || limits.max_records != 1 {
    return None
  }
  guard record_target_before_construction_inventory(
      mapping.original,
      mapping.before_fields,
      body_bytes,
      pages,
      values,
      limits,
    )
    is Some(before) else {
    return None
  }
  // The immutable App, ID and revision are digit Strings. Their combined
  // length is admitted by the original request constructor before encoding.
  let envelope = "{\"app\":\"\",\"ids\":[\"\"],\"revisions\":[\"\"]}"
  let request_bytes = Int64::min(
    limits.max_output_bytes.to_int64(),
    limits.max_identity_bytes.to_int64() + envelope.length().to_int64(),
  ).to_int()
  guard record_read_writer_units(
      request_bytes,
      limits.max_output_nodes,
      limits.max_output_depth,
    )
    is Some(writer) &&
    @execution.compose_preparation_representation([
      before.retained,
      {
        record_headers: 9L,
        reference_slots: 18L,
        scalar_words: 10L,
        owned_utf16_units: request_bytes.to_int64(),
        owned_wire_bytes: 0L,
      },
    ])
    is Some(retained) &&
    @execution.compose_preparation_representation([
      before.workspace,
      writer,
      {
        ..update_construction_empty(),
        record_headers: 8L,
        reference_slots: 12L,
        scalar_words: 4L,
      },
    ])
    is Some(workspace) else {
    return None
  }
  update_construction_capacity({ retained, workspace, })
}

///|
/// The original request and before observation are already backed. Account
/// for the raw acknowledgement parser, correlation writers and returned DATA.
/// The caller adds the canonical EffectOutcome check's parser and Host copy.
pub fn record_delete_response_construction_capacity(
  mapping : RecordDeleteMapping,
  body_bytes : Int,
  limits : @catalog.RecordMutationLimits,
) -> @execution.ExecutionCapacity? {
  if !record_delete_mapping_is_original(mapping) ||
    limits.max_records != 1 ||
    !record_target_before_limits_valid(limits) ||
    body_bytes < 0 ||
    body_bytes > limits.max_output_bytes {
    return None
  }
  let bytes = Int::max(1, body_bytes)
  let nodes = Int::min(bytes, limits.max_output_nodes)
  let depth = Int::min(nodes, limits.max_output_depth)
  let target_bytes = Int64::min(
    limits.max_output_bytes.to_int64(),
    limits.max_identity_bytes.to_int64() + 2L,
  ).to_int()
  let outcome_bytes = Int::min(
    limits.max_output_bytes,
    "{\"result\":{},\"state\":\"applied\"}".length(),
  )
  guard record_read_decoded_construction(bytes, nodes, depth, false)
    is Some(parser) &&
    record_read_writer_units(target_bytes, 1, 0) is Some(target_writer) &&
    record_read_writer_units(
      outcome_bytes,
      3,
      Int::min(2, limits.max_output_depth),
    )
    is Some(outcome_writer) &&
    @encode.hash_writer_live_key_inventory(0, 0) is Some(hash) &&
    @decode.issue_construction_extent(depth) is Some(issue) &&
    @shape.collection_construction_extent({
      // Root view, copied selected-column/target arrays and the fixed
      // response, ordered-row, identity and encoding Result/Option controls.
      records: 48L,
      record_references: 80L,
      record_words: 48L,
      reference_arrays: 12L,
      reference_items: 16L + 4L * mapping.before_fields.length().to_int64(),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(controls) &&
    @execution.compose_preparation_representation([
      parser,
      target_writer,
      outcome_writer,
      record_read_collection_units(issue),
      record_read_collection_units(controls),
      {
        record_headers: hash.record_headers,
        reference_slots: hash.reference_slots,
        scalar_words: hash.scalar_words,
        owned_utf16_units: hash.owned_utf16_units,
        owned_wire_bytes: hash.owned_wire_bytes,
      },
    ])
    is Some(workspace) else {
    return None
  }
  update_construction_capacity({
    retained: {
      record_headers: 8L,
      reference_slots: 16L,
      scalar_words: 8L,
      owned_utf16_units: 64L + outcome_bytes.to_int64(),
      owned_wire_bytes: 0L,
    },
    workspace,
  })
}
