///|
/// Checked before DATA under the same original Mapping/Form and target. This
/// is neither an authenticated observation, current permission nor an Effect
/// outcome or sealed Effect Preview; the original Site/capture must establish
/// and retain those facts.
pub struct RecordDeletePreview {
  priv mapping : RecordDeleteMapping
  priv target : @catalog.OriginalRecordTarget
  priv checked : @catalog.CheckedRecordPage
  priv before_wire : String
  priv version_cid : String
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
  Ok({ mapping, target, checked, before_wire: before, version_cid: version, })
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
  physical_equal(view.mapping, mapping) &&
  physical_equal(view.target, target) &&
  physical_equal(
    @catalog.checked_record_original(view.checked),
    @catalog.original_record_target_page(target),
  )
}
