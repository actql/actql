///|
pub(all) enum EffectPreviewInventoryIssue {
  InvalidStage
  WorkLimit
  MemberCountMismatch
  MissingMember(String)
  KindMismatch(String)
  FailurePolicyMismatch(String)
  SourceMismatch(String)
} derive(Eq, Debug)

///|
/// Compare a private Preview to the Effect declarations retained by one
/// checked Stage. This is an inventory check, not a Preview, authority, or
/// apply permit. The caller must separately bind the Preview to this Program
/// and to the exact Captured Run before any mutation can be dispatched.
fn check_effect_preview_checked_inventory_usage(
  bindings : EffectResultBindings,
  stage_index : Int,
  preview : @publication.EffectPreviewIdentity,
  max_work : Int,
) -> Result[Int, EffectPreviewInventoryIssue] {
  if stage_index < 0 || stage_at(bindings.owner, stage_index) is None {
    return Err(InvalidStage)
  }
  if max_work < 0 {
    return Err(WorkLimit)
  }
  let mut remaining = max_work
  let declared_headers : Array[@syntax.EffectHeader] = []
  for binding in bindings.members {
    if remaining <= 0 {
      return Err(WorkLimit)
    }
    remaining -= 1
    let header = effect_result_binding_header(binding)
    if @syntax.effect_header_stage(header) == stage_index {
      declared_headers.push(header)
    }
  }
  let declared = declared_headers.length()
  if declared != @publication.effect_preview_member_count(preview) {
    return Err(MemberCountMismatch)
  }
  for header in declared_headers {
    if remaining <= 0 {
      return Err(WorkLimit)
    }
    remaining -= 1
    let id = @syntax.effect_header_id(header)
    let mut matched = -1
    for index in 0..<declared {
      if remaining <= 0 {
        return Err(WorkLimit)
      }
      remaining -= 1
      if @publication.effect_preview_member_effect_id(preview, index) ==
        Some(id) {
        matched = index
        break
      }
    }
    if matched < 0 {
      return Err(MissingMember(id))
    }
    if @publication.effect_preview_member_kind(preview, matched) !=
      Some(@syntax.effect_header_kind(header)) {
      return Err(KindMismatch(id))
    }
    if @publication.effect_preview_member_failure_policy(preview, matched) !=
      Some(@syntax.effect_header_failure_policy(header)) {
      return Err(FailurePolicyMismatch(id))
    }
    let source = @syntax.effect_header_source_result(header)
    if @publication.effect_preview_member_source_result(preview, matched) !=
      source {
      return Err(SourceMismatch(id))
    }
  }
  Ok(max_work - remaining)
}

///|
pub fn check_effect_preview_checked_inventory(
  bindings : EffectResultBindings,
  stage_index : Int,
  preview : @publication.EffectPreviewIdentity,
  max_work : Int,
) -> Result[Unit, EffectPreviewInventoryIssue] {
  match
    check_effect_preview_checked_inventory_usage(
      bindings, stage_index, preview, max_work,
    ) {
    Ok(_) => Ok(())
    Err(issue) => Err(issue)
  }
}
