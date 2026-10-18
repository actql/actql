///|
pub enum RecordDeleteOutcomeIssue {
  MappingMismatch
  ForeignPreview
  Response(@catalog.RecordMutationIssue)
  Before(RecordReadIssue)
  Encoding
  Preview(@publication.EffectRowOutcomeIssue)
} derive(Debug)

///|
/// A typed response for one original DELETE and its admitted Preview row.
/// Physical response custody, current authority, the approved durable claim
/// and terminal settlement remain with the existing Site and Effect owners.
pub struct RecordDeletePreviewOutcome {
  priv mapping : RecordDeleteMapping
  priv request : @catalog.RecordDeleteRequest
  priv response : @catalog.RecordDeleteAcknowledgement
  priv preview : @publication.EffectPreviewIdentity
  priv member_index : Int
  priv row_index : Int
  priv row_cid : String
  priv document : @encode.EncodedDocument
}

///|
pub fn project_record_delete_preview_outcome(
  mapping : RecordDeleteMapping,
  request : @catalog.RecordDeleteRequest,
  response : @catalog.RecordDeleteAcknowledgement,
  preview : @publication.EffectPreviewIdentity,
  member_index : Int,
  row_index : Int,
  values : @catalog.RecordValueLimits,
  limits : @catalog.RecordMutationLimits,
) -> Result[RecordDeletePreviewOutcome, RecordDeleteOutcomeIssue] {
  if !record_delete_mapping_matches_request(mapping, request) {
    return Err(MappingMismatch)
  }
  let targets = @catalog.record_delete_request_targets(request)
  if targets.length() != 1 ||
    !@catalog.record_delete_acknowledgement_is_original(response) ||
    !physical_equal(
      @catalog.record_delete_acknowledgement_request(response),
      request,
    ) {
    return Err(Response(@catalog.UncorrelatedResult))
  }
  let before = match
    prepare_record_delete_preview(mapping, targets[0], values, limits) {
    Ok(value) => value
    Err(issue) => return Err(Before(issue))
  }
  guard @publication.effect_preview_member_kind(preview, member_index) ==
    Some("delete") &&
    @publication.effect_preview_member_resolved_contract(preview, member_index) ==
    Some(
      @publication.Mapping(
        mapping.mapping.mapping_ref,
        mapping.mapping.mapping_cid,
      ),
    ) &&
    @publication.effect_preview_ordered_row_identity(
      preview, member_index, row_index,
    )
    is Some(row_cid) &&
    @publication.effect_preview_row_index(preview, member_index, row_cid)
    is Some(change_index) &&
    @publication.effect_preview_ordered_row_correlation_wire(
      preview, member_index, row_index,
    )
    is Some(target_wire) &&
    @publication.effect_preview_row_guard_version_cid(
      preview, member_index, change_index,
    ) ==
    Some(record_delete_preview_version_cid(before)) &&
    @publication.effect_preview_ordered_row_intended_changes_wire(
      preview, member_index, row_index,
    ) ==
    Some("{\"state\":\"not_applicable\"}") else {
    return Err(ForeignPreview)
  }
  // Original API IDs have already passed the vendor decimal-digit reader.
  // Encode the exact original string; never use a Number or Record Number.
  let target_writer = @encode.writer(
    limits.max_output_bytes,
    limits.max_output_nodes,
    limits.max_output_depth,
  ) catch {
    _ => return Err(Encoding)
  }
  let expected_target = try {
    @encode.string_value(target_writer, record_delete_preview_identity(before))
    @encode.finish(target_writer)
  } catch {
    _ => {
      @encode.cancel_writer(target_writer)
      return Err(Encoding)
    }
  }
  if target_wire != expected_target {
    return Err(ForeignPreview)
  }
  let writer = @encode.writer(
    limits.max_output_bytes,
    limits.max_output_nodes,
    limits.max_output_depth,
  ) catch {
    _ => return Err(Encoding)
  }
  let document = try {
    @encode.begin_object(writer)
    @encode.key(writer, "result")
    @encode.begin_object(writer)
    @encode.end_object(writer)
    @encode.key(writer, "state")
    @encode.string_value(writer, "applied")
    @encode.end_object(writer)
    @encode.finish_document(writer)
  } catch {
    _ => {
      @encode.cancel_writer(writer)
      return Err(Encoding)
    }
  }
  match
    @publication.check_effect_preview_row_outcome(
      preview,
      member_index,
      change_index,
      row_cid,
      @encode.document_text(document),
      limits.max_output_bytes,
      limits.max_output_nodes,
      limits.max_output_depth,
    ) {
    Ok(_) =>
      Ok({
        mapping,
        request,
        response,
        preview,
        member_index,
        row_index,
        row_cid,
        document,
      })
    Err(issue) => Err(Preview(issue))
  }
}

///|
pub fn record_delete_preview_outcome_wire(
  value : RecordDeletePreviewOutcome,
) -> String {
  @encode.document_text(value.document)
}

///|
pub fn record_delete_preview_outcome_row_cid(
  value : RecordDeletePreviewOutcome,
) -> String {
  value.row_cid
}

///|
pub fn record_delete_preview_outcome_response_sha256(
  value : RecordDeletePreviewOutcome,
) -> String {
  value.response.response_sha256
}

///|
pub fn record_delete_preview_outcome_matches(
  value : RecordDeletePreviewOutcome,
  mapping : RecordDeleteMapping,
  request : @catalog.RecordDeleteRequest,
  preview : @publication.EffectPreviewIdentity,
  member_index : Int,
  row_index : Int,
) -> Bool {
  record_delete_mapping_is_original(mapping) &&
  @catalog.record_delete_request_is_original(request) &&
  @catalog.record_delete_acknowledgement_is_original(value.response) &&
  physical_equal(value.mapping, mapping) &&
  physical_equal(value.request, request) &&
  physical_equal(
    @catalog.record_delete_acknowledgement_request(value.response),
    request,
  ) &&
  physical_equal(value.preview, preview) &&
  value.member_index == member_index &&
  value.row_index == row_index
}
