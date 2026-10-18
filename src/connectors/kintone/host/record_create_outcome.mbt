///|
pub enum RecordCreateOutcomeIssue {
  MappingMismatch
  ForeignPreview
  Values(@catalog.RecordCreateJsonIssue)
  Response(@catalog.RecordMutationIssue)
  Preview(@publication.EffectRowOutcomeIssue)
} derive(Debug)

///|
/// One typed projection retaining the same admitted Preview, original Mapping,
/// physical request and decoded response. It is not a saved-response receipt,
/// current authorization, approved claim or terminal Ledger transition.
pub struct RecordCreatePreviewOutcome {
  priv mapping : RecordCreateMapping
  priv request : @catalog.RecordCreateRequest
  priv preview : @publication.EffectPreviewIdentity
  priv member_index : Int
  priv row_index : Int
  priv row_cid : String
  priv projected : @catalog.RecordCreateEffectOutcome
}

///|
pub fn project_record_create_preview_outcome(
  mapping : RecordCreateMapping,
  request : @catalog.RecordCreateRequest,
  response : @catalog.RecordCreateAcknowledgement,
  preview : @publication.EffectPreviewIdentity,
  member_index : Int,
  row_index : Int,
  max_value_bytes : Int,
  write_limits : @catalog.RecordWriteLimits,
  limits : @catalog.RecordMutationLimits,
) -> Result[RecordCreatePreviewOutcome, RecordCreateOutcomeIssue] {
  if !record_create_mapping_matches_request(mapping, request) {
    return Err(MappingMismatch)
  }
  guard @publication.effect_preview_member_kind(preview, member_index) ==
    Some("create") &&
    @publication.effect_preview_ordered_row_identity(
      preview, member_index, row_index,
    )
    is Some(row_cid) &&
    @publication.effect_preview_ordered_row_intended_value_wire(
      preview, member_index, row_index,
    )
    is Some(wire) else {
    return Err(ForeignPreview)
  }
  match
    @catalog.record_create_request_matches_value_wire(
      request, wire, max_value_bytes, write_limits, limits,
    ) {
    Ok(true) => ()
    Ok(false) => return Err(ForeignPreview)
    Err(issue) => return Err(Values(issue))
  }
  let projected = match
    @catalog.project_record_create_effect_outcome(request, response, limits) {
    Ok(value) => value
    Err(issue) => return Err(Response(issue))
  }
  guard @publication.effect_preview_row_index(preview, member_index, row_cid)
    is Some(change_index) else {
    return Err(ForeignPreview)
  }
  match
    @publication.check_effect_preview_row_outcome(
      preview,
      member_index,
      row_index,
      row_cid,
      @catalog.record_create_effect_outcome_wire(projected),
      limits.max_output_bytes,
      limits.max_output_nodes,
      limits.max_output_depth,
    ) {
    Ok(_) =>
      Ok({
        mapping,
        request,
        preview,
        member_index,
        row_index,
        row_cid,
        projected,
      })
    Err(issue) => Err(Preview(issue))
  }
}

///|
pub fn record_create_preview_outcome_wire(
  value : RecordCreatePreviewOutcome,
) -> String {
  @catalog.record_create_effect_outcome_wire(value.projected)
}

///|
pub fn record_create_preview_outcome_row_cid(
  value : RecordCreatePreviewOutcome,
) -> String {
  value.row_cid
}

///|
pub fn record_create_preview_outcome_response_sha256(
  value : RecordCreatePreviewOutcome,
) -> String {
  @catalog.record_create_effect_outcome_response_sha256(value.projected)
}

///|
pub fn record_create_preview_outcome_matches(
  value : RecordCreatePreviewOutcome,
  mapping : RecordCreateMapping,
  request : @catalog.RecordCreateRequest,
  preview : @publication.EffectPreviewIdentity,
  member_index : Int,
  row_index : Int,
) -> Bool {
  physical_equal(value.mapping, mapping) &&
  record_create_mapping_is_original(mapping) &&
  physical_equal(value.request, request) &&
  physical_equal(value.preview, preview) &&
  value.member_index == member_index &&
  value.row_index == row_index &&
  @catalog.record_create_effect_outcome_matches_request(
    value.projected,
    request,
  )
}
