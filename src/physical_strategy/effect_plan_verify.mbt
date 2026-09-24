///|
/// The checked Plan and approved Preview remain paired with the same live
/// captured input. A physical adapter must still supply rows from that input's
/// verified Result cursor; this owner is not an Effect apply permit.
struct CapturedEffectPlanVerifier {
  preview : CapturedEffectPreviewInputs
  preview_index : Int
  terminal : @results.EffectPlanTerminal
  literals : @results.EffectMappingLiterals
  mut next_row : Int
  mut live : Bool
}

///|
pub(all) enum CapturedEffectPlanVerifyIssue {
  InvalidMember
  MissingPlan
  NotReady
  PreviewMismatch
  SelectorEncoding
  Plan(CapturedEffectPlanIssue)
  Row(@results.EffectPlanRowIssue)
  Changes(@results.EffectPlanChangeIssue)
}

///|
pub fn prepare_captured_effect_plan_verifier(
  preview : CapturedEffectPreviewInputs,
  preview_index : Int,
  max_fields : Int,
  max_work : Int,
) -> Result[CapturedEffectPlanVerifier, CapturedEffectPlanVerifyIssue] {
  if captured_effect_preview_input_at(preview, preview_index) is None {
    return Err(InvalidMember)
  }
  let terminal = match
    captured_effect_preview_plan_terminal(
      preview, preview_index, max_fields, max_work,
    ) {
    Ok(Some(value)) => value
    Ok(None) => return Err(MissingPlan)
    Err(issue) => return Err(Plan(issue))
  }
  let run = @checked.effect_program_run_preview_owner(
    captured_effect_preview_owner(preview),
  )
  let static_candidate = @checked.effect_program_run_static_candidate(run)
  let effects = @checked.effect_program_static_effects(static_candidate)
  let literals = @results.effect_static_candidate_mapping_literals(effects)
  Ok({ preview, preview_index, terminal, literals, next_row: 0, live: true, })
}

///|
/// Check a single Result row in source order. Any mismatch revokes this
/// verifier, so a later row or empty tail cannot turn partial validation into
/// a completed proof. The caller must separately protect row provenance.
pub fn check_captured_effect_plan_row(
  value : CapturedEffectPlanVerifier,
  source_row : @identity.CanonicalValue,
  source_row_index : Int,
  max_fields : Int,
  max_work : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, CapturedEffectPlanVerifyIssue] {
  if !value.live ||
    captured_effect_preview_input_at(value.preview, value.preview_index) is None {
    value.live = false
    return Err(NotReady)
  }
  if source_row_index != value.next_row {
    value.live = false
    return Err(PreviewMismatch)
  }
  let projected = match
    @results.project_effect_plan_row(
      value.terminal,
      source_row,
      source_row_index,
      max_fields,
      max_work,
    ) {
    Ok(value) => value
    Err(issue) => {
      value.live = false
      return Err(Row(issue))
    }
  }
  let changes = match
    @results.effect_plan_row_intended_changes_wire(
      projected,
      value.literals,
      max_fields,
      max_work,
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => {
      value.live = false
      return Err(Changes(issue))
    }
  }
  let selector = @identity.stringify_value(
    @results.effect_plan_row_selector(projected),
    max_bytes,
    max_nodes,
    max_depth,
  ) catch {
    _ => {
      value.live = false
      return Err(SelectorEncoding)
    }
  }
  let identity = @checked.effect_program_run_preview_identity(
    captured_effect_preview_owner(value.preview),
  )
  if @publication.effect_preview_row_correlation_wire(
      identity,
      value.preview_index,
      source_row_index,
    ) !=
    Some(selector) ||
    @publication.effect_preview_row_intended_changes_wire(
      identity,
      value.preview_index,
      source_row_index,
    ) !=
    Some(changes) {
    value.live = false
    return Err(PreviewMismatch)
  }
  value.next_row += 1
  Ok(())
}

///|
pub fn finish_captured_effect_plan_verifier(
  value : CapturedEffectPlanVerifier,
) -> Result[Unit, CapturedEffectPlanVerifyIssue] {
  if !value.live ||
    captured_effect_preview_input_at(value.preview, value.preview_index) is None {
    value.live = false
    return Err(NotReady)
  }
  value.live = false
  let identity = @checked.effect_program_run_preview_identity(
    captured_effect_preview_owner(value.preview),
  )
  if @publication.effect_preview_row_count(identity, value.preview_index) !=
    Some(value.next_row) {
    return Err(PreviewMismatch)
  }
  Ok(())
}

///|
pub fn cancel_captured_effect_plan_verifier(
  value : CapturedEffectPlanVerifier,
) -> Unit {
  value.live = false
}
