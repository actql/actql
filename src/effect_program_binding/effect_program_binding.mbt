///|
/// One private Preview statically bound to its checked Program and exact
/// resolved member contracts. Captured Run, current authority and apply
/// admission are separate obligations; this is not an execution permit.
struct EffectProgramStaticPreview {
  candidate : @checked.EffectProgramStaticCandidate
  stage_index : Int
  preview : @run_publication.EffectPreviewIdentity
}

///|
/// The same statically closed checked Program retained with its admitted
/// Run. Effect capture, current authority, and apply remain separate proofs.
struct EffectProgramRunCandidate {
  candidate : @checked.EffectProgramStaticCandidate
  admission : @run_publication.RunPublicationAdmission
  run_definition : @run_publication.PublicationContract
}

///|
/// A private Preview bound both to a statically closed checked Effect Stage
/// and to exact Run and Invocation identities. ObservationSet proof and apply
/// authority are separate; this still cannot dispatch.
struct EffectProgramRunPreview {
  run : EffectProgramRunCandidate
  invocation : @run_publication.PublicationContract
  preview : EffectProgramStaticPreview
}

///|
pub(all) enum EffectProgramRunPreviewIssue {
  Static(EffectProgramStaticPreviewIssue)
  Run(@run_publication.EffectPreviewRunBindingIssue)
} derive(Eq, Debug)

///|
pub(all) enum EffectProgramRunIssue {
  Binding(@run_publication.RunProgramBindingIssue)
} derive(Eq, Debug)

///|
pub(all) enum EffectProgramStaticPreviewIssue {
  ForeignProgramDefinition
  ForeignProgramSemantics
  ForeignCheckEnvironment
  ForeignResolvedLimit(String)
  LimitWorkExceeded
  Inventory(@results.EffectPreviewStaticInventoryIssue)
  PlanInventory(@results.EffectPlanInventoryIssue)
} derive(Eq, Debug)

///|
/// Resolve only the author's Effect scope guard from the admitted Program
/// parameter owner. Policy and Contract ceilings remain Plan obligations.
fn effect_authored_max_items(
  candidate : @checked.EffectProgramStaticCandidate,
  header : @syntax.EffectHeader,
  remaining : Ref[Int],
) -> Result[Int64?, EffectProgramStaticPreviewIssue] {
  let body = @decode.open_object(@syntax.effect_header_body(header)).unwrap()
  guard @decode.lookup(body, "max_items") is Some(guard_value) else {
    return Ok(None)
  }
  match @decode.safe_integer(guard_value) {
    Ok(value) => return Ok(Some(value))
    Err(_) => ()
  }
  let parameter = @decode.open_object(guard_value).unwrap()
  let name = @decode.text(@decode.lookup(parameter, "$param").unwrap()).unwrap()
  let stage = @syntax.effect_header_stage(header)
  let identity = @checked.source_identity(
    @checked.effect_program_static_checked_computation(candidate),
  )
  let stage_owner = @context.program_identity_stage_at(identity, stage).unwrap()
  let values = @parameter_refs.bound_values(
    @context.stage_identity_parameter_values(stage_owner),
  )
  for index in 0..<@parameters.bound_value_count(values) {
    if remaining.val <= 0 {
      return Err(LimitWorkExceeded)
    }
    remaining.val -= 1
    let bound = @parameters.bound_value_at(values, index).unwrap()
    if bound.name == name {
      return match bound.value.value {
        @value.Number(number) if number > 0.0 &&
          number <= 9007199254740991.0 &&
          number == number.to_int64().to_double() => Ok(Some(number.to_int64()))
        _ => Err(ForeignResolvedLimit(@syntax.effect_header_id(header)))
      }
    }
  }
  Err(ForeignResolvedLimit(@syntax.effect_header_id(header)))
}

///|
pub fn bind_effect_program_static_run(
  candidate : @checked.EffectProgramStaticCandidate,
  admission : @run_publication.RunPublicationAdmission,
  run_definition : @run_publication.PublicationContract,
) -> Result[EffectProgramRunCandidate, EffectProgramRunIssue] {
  match
    @run_publication.check_run_publication_program_binding(
      admission,
      run_definition,
      @checked.effect_program_static_definition_cid(candidate),
      @checked.effect_program_static_semantics_cid(candidate),
      @environment.cid(@checked.effect_program_static_environment(candidate)),
    ) {
    Ok(_) => Ok({ candidate, admission, run_definition, })
    Err(issue) => Err(Binding(issue))
  }
}

///|
pub fn effect_program_run_static_candidate(
  value : EffectProgramRunCandidate,
) -> @checked.EffectProgramStaticCandidate {
  value.candidate
}

///|
pub fn effect_program_run_admission(
  value : EffectProgramRunCandidate,
) -> @run_publication.RunPublicationAdmission {
  value.admission
}

///|
pub fn effect_program_run_definition(
  value : EffectProgramRunCandidate,
) -> @run_publication.PublicationContract {
  value.run_definition
}

///|
pub fn bind_effect_program_run_preview(
  run : EffectProgramRunCandidate,
  invocation : @run_publication.PublicationContract,
  stage_index : Int,
  preview : @run_publication.EffectPreviewIdentity,
  max_work : Int,
  plan_limits : @results.EffectPlanIdentityLimits,
) -> Result[EffectProgramRunPreview, EffectProgramRunPreviewIssue] {
  let static_preview = match
    bind_effect_program_static_preview(
      run.candidate,
      stage_index,
      preview,
      max_work,
      plan_limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Static(issue))
  }
  match
    @run_publication.check_effect_preview_run_binding(
      run.admission,
      run.run_definition,
      invocation,
      preview,
    ) {
    Ok(_) => Ok({ run, invocation, preview: static_preview, })
    Err(issue) => Err(Run(issue))
  }
}

///|
pub fn effect_program_run_preview_identity(
  value : EffectProgramRunPreview,
) -> @run_publication.EffectPreviewIdentity {
  value.preview.preview
}

///|
pub fn effect_program_run_preview_invocation(
  value : EffectProgramRunPreview,
) -> @run_publication.PublicationContract {
  value.invocation
}

///|
pub fn effect_program_run_preview_owner(
  value : EffectProgramRunPreview,
) -> EffectProgramRunCandidate {
  value.run
}

///|
pub fn effect_program_run_preview_stage(value : EffectProgramRunPreview) -> Int {
  value.preview.stage_index
}

///|
/// Check the entire admitted Effect Set footprint on the exact checked Run
/// Preview owner. A caller-supplied member list cannot replace the retained
/// inventory. Current authorization, target guards, captured values and
/// payload equivalence are separate apply-admission obligations.
pub fn check_effect_program_run_preview_footprints(
  value : EffectProgramRunPreview,
  max_members : Int,
  max_targets : Int,
  max_work : Int,
) -> Result[Unit, @effect.EffectFootprintIssue] {
  @effect.check_admitted_effect_preview_footprint_conflicts(
    value.preview.preview,
    max_members,
    max_targets,
    max_work,
  )
}

///|
pub fn bind_effect_program_static_preview(
  candidate : @checked.EffectProgramStaticCandidate,
  stage_index : Int,
  preview : @run_publication.EffectPreviewIdentity,
  max_work : Int,
  plan_limits : @results.EffectPlanIdentityLimits,
) -> Result[EffectProgramStaticPreview, EffectProgramStaticPreviewIssue] {
  if @run_publication.effect_preview_program_definition_cid(preview) !=
    @checked.effect_program_static_definition_cid(candidate) {
    return Err(ForeignProgramDefinition)
  }
  if @run_publication.effect_preview_program_semantics_cid(preview) !=
    @checked.effect_program_static_semantics_cid(candidate) {
    return Err(ForeignProgramSemantics)
  }
  if @run_publication.effect_preview_check_environment_cid(preview) !=
    @environment.cid(@checked.effect_program_static_environment(candidate)) {
    return Err(ForeignCheckEnvironment)
  }
  if max_work < 0 {
    return Err(LimitWorkExceeded)
  }
  let remaining = Ref(max_work)
  let headers = @checked.effect_program_static_headers(candidate)
  for header_index in 0..<@syntax.effect_header_count(headers) {
    if remaining.val <= 0 {
      return Err(LimitWorkExceeded)
    }
    remaining.val -= 1
    let header = @syntax.effect_header_at(headers, header_index).unwrap()
    if @syntax.effect_header_stage(header) != stage_index {
      continue
    }
    let authored = match
      effect_authored_max_items(candidate, header, remaining) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if authored is Some(limit) {
      let id = @syntax.effect_header_id(header)
      let mut found = false
      for
        member_index in 0..<@run_publication.effect_preview_member_count(
          preview,
        ) {
        if remaining.val <= 0 {
          return Err(LimitWorkExceeded)
        }
        remaining.val -= 1
        if @run_publication.effect_preview_member_effect_id(
            preview, member_index,
          ) ==
          Some(id) {
          found = true
          if @run_publication.effect_preview_member_max_items(
              preview, member_index,
            )
            is Some(resolved) &&
            resolved <= limit {
            break
          }
          return Err(ForeignResolvedLimit(id))
        }
      }
      if !found {
        return Err(ForeignResolvedLimit(id))
      }
    }
  }
  match
    @results.check_effect_preview_static_inventory(
      @checked.effect_program_static_effects(candidate),
      stage_index,
      preview,
      remaining.val,
    ) {
    Ok(_) =>
      match
        @results.check_effect_preview_plan_inventory(
          @results.effect_static_candidate_mapping_rules(
            @checked.effect_program_static_effects(candidate),
          ),
          stage_index,
          preview,
          plan_limits,
        ) {
        Ok(_) => Ok({ candidate, stage_index, preview, })
        Err(issue) => Err(PlanInventory(issue))
      }
    Err(issue) => Err(Inventory(issue))
  }
}

///|
pub fn effect_program_static_preview_identity(
  value : EffectProgramStaticPreview,
) -> @run_publication.EffectPreviewIdentity {
  value.preview
}

///|
pub fn effect_program_static_preview_stage(
  value : EffectProgramStaticPreview,
) -> Int {
  value.stage_index
}

///|
pub fn effect_program_static_preview_candidate(
  value : EffectProgramStaticPreview,
) -> @checked.EffectProgramStaticCandidate {
  value.candidate
}
