///|
/// Checked before DATA under the same original Mapping/Form and target. This
/// is neither an authenticated observation, current permission nor an Effect
/// outcome or sealed Effect Preview; the original Site/capture must establish
/// and retain those facts.
pub struct RecordDeletePreview {
  priv mut self : RecordDeletePreview?
  priv mapping : RecordDeleteMapping
  priv target : @catalog.OriginalRecordTarget
  priv checked : @catalog.CheckedRecordPage
  priv before_wire : String
  priv version_cid : String
}

///|
fn validate_record_delete_selector(
  mapping : RecordDeleteMapping,
  identity : String,
  limits : @catalog.RecordMutationLimits,
) -> Result[Unit, @catalog.RecordMutationIssue] {
  if !record_delete_mapping_is_original(mapping) {
    return Err(ForeignCatalog)
  }
  if !record_target_before_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  if identity.length() > limits.max_identity_bytes {
    return Err(BudgetExceeded)
  }
  if !record_request_id(identity) {
    return Err(InvalidRequest)
  }
  Ok(())
}

///|
/// Prepare the comparison read for an admitted DELETE Mapping. The selector
/// is the provider's API ID, and the Mapping supplies every before field.
pub fn record_delete_target_read_body(
  mapping : RecordDeleteMapping,
  identity : String,
  max_fields : Int,
  limits : @catalog.RecordMutationLimits,
) -> Result[String, @catalog.RecordMutationIssue] {
  match validate_record_delete_selector(mapping, identity, limits) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  record_exact_target_read_body(
    mapping.original.catalog.app_id,
    identity,
    mapping.before_fields,
    max_fields,
    limits.max_output_bytes,
    limits.max_output_nodes,
    limits.max_output_depth,
  )
}

///|
pub(all) enum RecordDeleteTargetReadIssue {
  TargetMismatch
  Page(@catalog.RecordPageIssue)
  Before(RecordReadIssue)
  Request(@catalog.RecordMutationIssue)
}

///|
/// Project one selected API ID from the complete comparison read. Preview
/// DATA and the conditional request retain the same original target/revision.
pub fn prepare_record_delete_target_read(
  mapping : RecordDeleteMapping,
  identity : String,
  bytes : Bytes,
  pages : @catalog.RecordPageLimits,
  values : @catalog.RecordValueLimits,
  limits : @catalog.RecordMutationLimits,
) -> Result[
  (RecordDeletePreview, @catalog.RecordDeleteRequest),
  RecordDeleteTargetReadIssue,
] {
  match validate_record_delete_selector(mapping, identity, limits) {
    Ok(_) => ()
    Err(issue) => return Err(Request(issue))
  }
  let page = match
    @catalog.project_record_page(
      bytes,
      mapping.original.catalog,
      mapping.before_fields,
      pages,
    ) {
    Ok(page) => page
    Err(issue) => return Err(Page(issue))
  }
  let records = @catalog.record_page_records(page)
  if records.length() != 1 || records[0].record_id != identity {
    return Err(TargetMismatch)
  }
  let target = match
    @catalog.prepare_original_record_target(page, 0, limits.max_identity_bytes) {
    Ok(target) => target
    Err(issue) => return Err(Request(issue))
  }
  let preview = match
    prepare_record_delete_preview(mapping, target, values, limits) {
    Ok(preview) => preview
    Err(issue) => return Err(Before(issue))
  }
  let request = match @catalog.prepare_record_delete_request([target], limits) {
    Ok(request) => request
    Err(issue) => return Err(Request(issue))
  }
  Ok((preview, request))
}

///|
pub fn prepare_record_delete_preview(
  mapping : RecordDeleteMapping,
  target : @catalog.OriginalRecordTarget,
  values : @catalog.RecordValueLimits,
  limits : @catalog.RecordMutationLimits,
) -> Result[RecordDeletePreview, RecordReadIssue] {
  if !record_target_before_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  let page = @catalog.original_record_target_page(target)
  if !record_delete_mapping_page_matches(mapping, page) {
    return Err(ForeignDeclaration)
  }
  let (checked, before, version) = match
    prepare_record_target_before(mapping.original, target, values, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let result : RecordDeletePreview = {
    self: None,
    mapping,
    target,
    checked,
    before_wire: before,
    version_cid: version,
  }
  result.self = Some(result)
  Ok(result)
}

///|
pub fn record_delete_preview_identity(view : RecordDeletePreview) -> String {
  @catalog.original_record_target_id(view.target)
}

///|
pub fn record_delete_preview_version_cid(view : RecordDeletePreview) -> String {
  view.version_cid
}

///|
pub fn record_delete_preview_before_wire(view : RecordDeletePreview) -> String {
  view.before_wire
}

///|
/// Correspondence only: the same original Mapping and target must remain held.
pub fn record_delete_preview_matches(
  view : RecordDeletePreview,
  mapping : RecordDeleteMapping,
  target : @catalog.OriginalRecordTarget,
) -> Bool {
  view.self is Some(original) &&
  physical_equal(original, view) &&
  physical_equal(view.mapping, mapping) &&
  physical_equal(view.target, target) &&
  physical_equal(
    @catalog.checked_record_original(view.checked),
    @catalog.original_record_target_page(target),
  )
}
