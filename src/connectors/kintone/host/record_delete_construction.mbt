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
