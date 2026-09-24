///|
/// A computation check with retained Effect declarations, not an Effect
/// admission or an executable CheckedProgram. The ordinary checker continues
/// to reject nonempty Effects until their complete closure is connected.
struct EffectComputationCandidate {
  checked : CheckedProgram
  headers : @syntax.EffectHeaders
}

///|
/// One exact checked computation and its complete static Effect inventory.
/// Runtime authority, conversion implementations, captured values, Preview,
/// and apply admission remain outstanding obligations.
struct EffectProgramStaticCandidate {
  computation : EffectComputationCandidate
  effects : @results.EffectStaticCandidate
}

///|
/// One private Preview statically bound to its checked Program and exact
/// resolved member contracts. Captured Run, current authority and apply
/// admission are separate obligations; this is not an execution permit.
pub struct EffectProgramStaticPreview {
  candidate : EffectProgramStaticCandidate
  stage_index : Int
  preview : @run_publication.EffectPreviewIdentity
}

///|
/// The same statically closed checked Program retained with its admitted
/// Run. Effect capture, current authority, and apply remain separate proofs.
pub struct EffectProgramRunCandidate {
  candidate : EffectProgramStaticCandidate
  admission : @run_publication.RunPublicationAdmission
  run_definition : @run_publication.PublicationContract
}

///|
/// A private Preview bound both to a statically closed checked Effect Stage
/// and to exact Run and Invocation identities. ObservationSet proof and apply
/// authority are separate; this still cannot dispatch.
pub struct EffectProgramRunPreview {
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
  Inventory(@results.EffectPreviewStaticInventoryIssue)
} derive(Eq, Debug)

///|
pub(all) enum EffectComputationIssue {
  InvalidLimits
  InvalidProgram(@syntax.SyntaxError)
  Headers(@syntax.EffectHeaderIssue)
  MissingEffects
  Computation(LocalConstructionFailure)
}

///|
/// Reuse the ordinary computation check, but retain a separately validated
/// Effect inventory instead of treating it as checked execution authority.
/// Header work is charged before the computation budget is passed onward.
pub fn prepare_effect_computation_candidate(
  program : @syntax.Program,
  environment : CheckEnvironment,
  supplied : @decode.Cursor?,
  evidence : Array[@context.StageCapacityInput],
  limits : CheckLimits,
  max_members : Int,
  max_header_work : Int,
) -> Result[EffectComputationCandidate, EffectComputationIssue] {
  if !compile_limits_valid(limits.compilation) ||
    max_members < 0 ||
    max_header_work < 0 {
    return Err(InvalidLimits)
  }
  match @syntax.validate_reuse(program, limits.input) {
    Ok(_) => ()
    Err(issue) => return Err(InvalidProgram(issue))
  }
  let headers = match
    @syntax.collect_effect_headers(
      program,
      max_members,
      Int::min(max_header_work, limits.compilation.work),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Headers(issue))
  }
  if @syntax.effect_header_count(headers) == 0 {
    return Err(MissingEffects)
  }
  let remaining = limits.compilation.work - @syntax.effect_headers_work(headers)
  let computation_limits = {
    ..limits,
    compilation: { ..limits.compilation, work: remaining, },
  }
  let checked = construct_parsed(
    program,
    environment,
    supplied,
    evidence,
    computation_limits,
    effect_headers=Some(headers),
  ) catch {
    issue => return Err(Computation(issue))
  }
  Ok({ checked, headers, })
}

///|
pub fn effect_computation_headers(
  candidate : EffectComputationCandidate,
) -> @syntax.EffectHeaders {
  candidate.headers
}

///|
pub fn effect_computation_stage_results(
  candidate : EffectComputationCandidate,
) -> @results.Checked {
  checked_stage_results(candidate.checked)
}

///|
pub fn effect_computation_environment(
  candidate : EffectComputationCandidate,
) -> @environment.WireEnvironment {
  checked_environment(candidate.checked)
}

///|
pub fn effect_computation_catalog_references(
  candidate : EffectComputationCandidate,
) -> @environment.CatalogReferences {
  checked_catalog_references(candidate.checked)
}

///|
/// The static Mapping/Command closure consumes and retains the exact checked
/// computation owner. It still cannot authorize an Effect, Preview, apply,
/// or Run.
pub fn close_effect_computation_static(
  candidate : EffectComputationCandidate,
  mappings : @environment.MappingContractShapes,
  limits : @results.EffectStaticCandidateLimits,
) -> Result[EffectProgramStaticCandidate, @results.EffectStaticCandidateIssue] {
  let effects = match
    @results.prepare_effect_static_candidate(
      candidate.headers,
      checked_stage_results(candidate.checked),
      checked_environment(candidate.checked),
      mappings,
      checked_catalog_references(candidate.checked),
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ computation: candidate, effects, })
}

///|
pub fn effect_program_static_effects(
  candidate : EffectProgramStaticCandidate,
) -> @results.EffectStaticCandidate {
  candidate.effects
}

///|
pub fn effect_program_static_headers(
  candidate : EffectProgramStaticCandidate,
) -> @syntax.EffectHeaders {
  candidate.computation.headers
}

///|
pub fn effect_program_static_stage_results(
  candidate : EffectProgramStaticCandidate,
) -> @results.Checked {
  checked_stage_results(candidate.computation.checked)
}

///|
pub fn effect_program_static_environment(
  candidate : EffectProgramStaticCandidate,
) -> @environment.WireEnvironment {
  checked_environment(candidate.computation.checked)
}

///|
pub fn effect_program_static_definition_cid(
  candidate : EffectProgramStaticCandidate,
) -> String {
  @context.program_identity_definition_cid(
    source_identity(candidate.computation.checked),
  )
}

///|
pub fn effect_program_static_semantics_cid(
  candidate : EffectProgramStaticCandidate,
) -> String {
  @references.program_definition_semantics_cid(
    @context.program_identity_definition(
      source_identity(candidate.computation.checked),
    ),
  )
}

///|
pub fn bind_effect_program_static_run(
  candidate : EffectProgramStaticCandidate,
  admission : @run_publication.RunPublicationAdmission,
  run_definition : @run_publication.PublicationContract,
) -> Result[EffectProgramRunCandidate, EffectProgramRunIssue] {
  match
    @run_publication.check_run_publication_program_binding(
      admission,
      run_definition,
      effect_program_static_definition_cid(candidate),
      effect_program_static_semantics_cid(candidate),
      @environment.cid(effect_program_static_environment(candidate)),
    ) {
    Ok(_) => Ok({ candidate, admission, run_definition, })
    Err(issue) => Err(Binding(issue))
  }
}

///|
pub fn effect_program_run_static_candidate(
  value : EffectProgramRunCandidate,
) -> EffectProgramStaticCandidate {
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
) -> Result[EffectProgramRunPreview, EffectProgramRunPreviewIssue] {
  let static_preview = match
    bind_effect_program_static_preview(
      run.candidate,
      stage_index,
      preview,
      max_work,
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
pub fn bind_effect_program_static_preview(
  candidate : EffectProgramStaticCandidate,
  stage_index : Int,
  preview : @run_publication.EffectPreviewIdentity,
  max_work : Int,
) -> Result[EffectProgramStaticPreview, EffectProgramStaticPreviewIssue] {
  if @run_publication.effect_preview_program_definition_cid(preview) !=
    effect_program_static_definition_cid(candidate) {
    return Err(ForeignProgramDefinition)
  }
  if @run_publication.effect_preview_program_semantics_cid(preview) !=
    effect_program_static_semantics_cid(candidate) {
    return Err(ForeignProgramSemantics)
  }
  if @run_publication.effect_preview_check_environment_cid(preview) !=
    @environment.cid(effect_program_static_environment(candidate)) {
    return Err(ForeignCheckEnvironment)
  }
  match
    @results.check_effect_preview_static_inventory(
      candidate.effects,
      stage_index,
      preview,
      max_work,
    ) {
    Ok(_) => Ok({ candidate, stage_index, preview, })
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
) -> EffectProgramStaticCandidate {
  value.candidate
}
