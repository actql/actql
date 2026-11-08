///|
pub(all) enum RecordUpdateExecutionIssue {
  InvalidLimits
  MappingMismatch
  TargetMismatch
  Values(@catalog.RecordWriteJsonIssue)
  Page(@catalog.RecordPageIssue)
  Before(RecordReadIssue)
  Request(@catalog.RecordMutationIssue)
}

///|
/// The original mapped values and exact selector, before a target revision is
/// available. This is DATA, not an HTTP request, current permission or claim.
pub struct RecordUpdateProposal {
  priv mut self : RecordUpdateProposal?
  priv mapping : RecordUpdateMapping
  priv identity : String
  priv values : @catalog.RecordWriteValues
  priv value_wire : String
}

///|
pub fn record_update_proposal_matches_mapping(
  proposal : RecordUpdateProposal,
  mapping : RecordUpdateMapping,
) -> Bool {
  proposal.self is Some(original) &&
  physical_equal(original, proposal) &&
  record_update_mapping_is_original(mapping) &&
  physical_equal(proposal.mapping, mapping)
}

///|
fn update_mapping_values_match(
  mapping : RecordUpdateMapping,
  values : @catalog.RecordWriteValues,
) -> Bool {
  let written = @catalog.record_write_values_fields(values)
  @catalog.record_write_values_match_catalog(values, mapping.original.catalog) &&
  written.all(name => mapping.written_fields.contains(name)) &&
  mapping.written_fields.all(name => {
    written.contains(name) || mapping.omitted_fields.contains(name)
  })
}

///|
pub fn prepare_record_update_proposal(
  mapping : RecordUpdateMapping,
  identity : String,
  bytes : Bytes,
  max_input_bytes : Int,
  write_limits : @catalog.RecordWriteLimits,
  limits : @catalog.RecordMutationLimits,
) -> Result[RecordUpdateProposal, RecordUpdateExecutionIssue] {
  if !record_update_mapping_is_original(mapping) {
    return Err(MappingMismatch)
  }
  if !record_target_before_limits_valid(limits) || max_input_bytes <= 0 {
    return Err(InvalidLimits)
  }
  if identity.length() > limits.max_identity_bytes ||
    !record_request_id(identity) {
    return Err(TargetMismatch)
  }
  let values = match
    @catalog.prepare_record_write_values_json(
      mapping.original.catalog,
      bytes,
      max_input_bytes,
      write_limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Values(issue))
  }
  if !update_mapping_values_match(mapping, values) {
    return Err(MappingMismatch)
  }
  let wire = match
    @catalog.record_write_values_json(
      values,
      write_limits.max_output_bytes,
      write_limits.max_nodes,
      write_limits.max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Values(issue))
  }
  let result : RecordUpdateProposal = {
    self: None,
    mapping,
    identity,
    values,
    value_wire: wire,
  }
  result.self = Some(result)
  Ok(result)
}

///|
pub fn record_update_proposal_identity(
  proposal : RecordUpdateProposal,
) -> String {
  proposal.identity
}

///|
pub fn record_update_proposal_value_wire(
  proposal : RecordUpdateProposal,
) -> String {
  proposal.value_wire
}

///|
/// An exact native projection of one observed target body under the original
/// Catalog. The physical caller still owns its read authorization and bytes.
pub struct RecordUpdatePreview {
  priv mut self : RecordUpdatePreview?
  priv proposal : RecordUpdateProposal
  priv target : @catalog.OriginalRecordTarget
  priv checked : @catalog.CheckedRecordPage
  priv before_wire : String
  priv version_cid : String
}

///|
pub fn record_update_preview_matches(
  preview : RecordUpdatePreview,
  proposal : RecordUpdateProposal,
) -> Bool {
  preview.self is Some(original) &&
  physical_equal(original, preview) &&
  record_update_proposal_matches_mapping(proposal, proposal.mapping) &&
  physical_equal(preview.proposal, proposal) &&
  physical_equal(
    @catalog.checked_record_original(preview.checked),
    @catalog.original_record_target_page(preview.target),
  )
}

///|
pub fn prepare_record_update_preview(
  proposal : RecordUpdateProposal,
  bytes : Bytes,
  pages : @catalog.RecordPageLimits,
  values : @catalog.RecordValueLimits,
  limits : @catalog.RecordMutationLimits,
) -> Result[RecordUpdatePreview, RecordUpdateExecutionIssue] {
  if !record_update_proposal_matches_mapping(proposal, proposal.mapping) {
    return Err(MappingMismatch)
  }
  if !record_target_before_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  let mapping = proposal.mapping
  let page = match
    @catalog.project_record_page(
      bytes,
      mapping.original.catalog,
      mapping.before_fields,
      pages,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Page(issue))
  }
  let records = @catalog.record_page_records(page)
  // The existing targeted read asks for one exact API id. Extra/missing rows
  // are not a target or absence observation, even when one id happens to match.
  if records.length() != 1 || records[0].record_id != proposal.identity {
    return Err(TargetMismatch)
  }
  let target = match
    @catalog.prepare_original_record_target(page, 0, limits.max_identity_bytes) {
    Ok(value) => value
    Err(issue) => return Err(Request(issue))
  }
  let (checked, before, version) = match
    prepare_record_target_before(mapping.original, target, values, limits) {
    Ok(value) => value
    Err(issue) => return Err(Before(issue))
  }
  let result : RecordUpdatePreview = {
    self: None,
    proposal,
    target,
    checked,
    before_wire: before,
    version_cid: version,
  }
  result.self = Some(result)
  Ok(result)
}

///|
pub fn record_update_preview_identity(preview : RecordUpdatePreview) -> String {
  @catalog.original_record_target_id(preview.target)
}

///|
pub fn record_update_preview_revision(preview : RecordUpdatePreview) -> String {
  @catalog.original_record_target_revision(preview.target)
}

///|
pub fn record_update_preview_before_wire(
  preview : RecordUpdatePreview,
) -> String {
  preview.before_wire
}

///|
pub fn record_update_preview_version_cid(
  preview : RecordUpdatePreview,
) -> String {
  preview.version_cid
}

///|
/// Build the native PUT body only after its exact observed id/revision is
/// held. No invented revision, unconditional -1 or provider default is used.
pub fn finalize_record_update_request(
  proposal : RecordUpdateProposal,
  preview : RecordUpdatePreview,
  limits : @catalog.RecordMutationLimits,
) -> Result[@catalog.RecordUpdateRequest, RecordUpdateExecutionIssue] {
  if !record_update_preview_matches(preview, proposal) {
    return Err(TargetMismatch)
  }
  let request = match
    @catalog.prepare_record_update_request(
      [(preview.target, proposal.values)],
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Request(issue))
  }
  if !record_update_mapping_matches_request(proposal.mapping, request) {
    return Err(MappingMismatch)
  }
  Ok(request)
}

///|
pub fn record_update_execution_matches(
  proposal : RecordUpdateProposal,
  preview : RecordUpdatePreview,
  request : @catalog.RecordUpdateRequest,
) -> Bool {
  if !record_update_preview_matches(preview, proposal) ||
    !record_update_mapping_matches_request(proposal.mapping, request) {
    return false
  }
  let records = @catalog.record_update_request_values(request)
  records.length() == 1 &&
  physical_equal(records[0].0, preview.target) &&
  physical_equal(records[0].1, proposal.values)
}

///|
/// Re-admit saved DATA against the original publication Catalog and complete
/// saved target/value/body. This runs no I/O and issues no tag, CID or retry.
/// The existing native serializer must reproduce the entire saved PUT body.
pub fn restore_record_update_execution(
  mapping : RecordUpdateMapping,
  identity : String,
  value_bytes : Bytes,
  target_bytes : Bytes,
  original_body : String,
  max_input_bytes : Int,
  pages : @catalog.RecordPageLimits,
  values : @catalog.RecordValueLimits,
  write_limits : @catalog.RecordWriteLimits,
  limits : @catalog.RecordMutationLimits,
  preview_limits? : @catalog.RecordMutationLimits = limits,
) -> Result[
  (RecordUpdateProposal, RecordUpdatePreview, @catalog.RecordUpdateRequest),
  RecordUpdateExecutionIssue,
] {
  if !record_update_mapping_is_original(mapping) {
    return Err(MappingMismatch)
  }
  if !record_target_before_limits_valid(limits) ||
    !record_target_before_limits_valid(preview_limits) {
    return Err(InvalidLimits)
  }
  guard @scalar.admit_utf8_length(original_body, limits.max_output_bytes)
    is Ok(_) else {
    return Err(Request(@catalog.BudgetExceeded))
  }
  let proposal = match
    prepare_record_update_proposal(
      mapping, identity, value_bytes, max_input_bytes, write_limits, limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let preview = match
    prepare_record_update_preview(
      proposal, target_bytes, pages, values, preview_limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let request = match
    finalize_record_update_request(proposal, preview, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if @catalog.record_update_request_body(request) != original_body {
    return Err(TargetMismatch)
  }
  Ok((proposal, preview, request))
}
