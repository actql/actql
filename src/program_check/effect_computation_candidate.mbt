///|
/// A computation check with retained Effect declarations, not an Effect
/// admission or an executable CheckedProgram. The ordinary checker continues
/// to reject nonempty Effects until their complete closure is connected.
struct EffectComputationCandidate {
  checked : CheckedProgram
  headers : @syntax.EffectHeaders
  supplied : @decode.Cursor?
}

///|
/// One exact checked computation and its complete static Effect inventory.
/// Runtime authority, conversion implementations, captured values, Preview,
/// and apply admission remain outstanding obligations.
struct EffectProgramStaticCandidate {
  computation : EffectComputationCandidate
  effects : @results.EffectStaticCandidate
  local_update_completion_free_audit : CompletionFreeAudit
}

///|
pub(all) enum EffectComputationIssue {
  InvalidLimits
  InvalidProgram(@syntax.SyntaxError)
  Headers(@syntax.EffectHeaderIssue)
  MissingEffects
  Computation(LocalConstructionFailure)
  Phase(ParsedCheckPreludeIssue)
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
  source_catalog? : PreparedSourceCatalog? = None,
) -> Result[EffectComputationCandidate, EffectComputationIssue] {
  let original = match
    prepare_effect_computation_input(
      program,
      environment,
      supplied,
      evidence,
      limits,
      max_members,
      max_header_work,
      source_catalog~,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let checked = finish_parsed_check_input_owned(original) catch {
    issue => return Err(Computation(issue))
  }
  Ok({
    checked,
    headers: original.effect_headers.unwrap(),
    supplied: original.supplied,
  })
}

///|
/// Retain the original validated Effect inventory and its header-adjusted
/// budget in the existing parsed input. This is DATA, not Effect authority.
/// Later prelude/Catalog/check phases consume this SAME input, never recheck
/// the computation to recover an Effect candidate.
pub fn prepare_effect_computation_input(
  program : @syntax.Program,
  environment : CheckEnvironment,
  supplied : @decode.Cursor?,
  evidence : Array[@context.StageCapacityInput],
  limits : CheckLimits,
  max_members : Int,
  max_header_work : Int,
  source_catalog? : PreparedSourceCatalog? = None,
  source_preparation? : @stages.Source? = None,
) -> Result[ParsedCheckInput, EffectComputationIssue] {
  prepare_effect_computation_input_owned(
    program,
    environment,
    supplied,
    evidence,
    limits,
    max_members,
    max_header_work,
    source_catalog~,
    source_preparation~,
  )
}

///|
pub fn observe_prepare_effect_computation_input(
  program : @syntax.Program,
  environment : CheckEnvironment,
  supplied : @decode.Cursor?,
  evidence : Array[@context.StageCapacityInput],
  limits : CheckLimits,
  max_members : Int,
  max_header_work : Int,
  source_catalog? : PreparedSourceCatalog? = None,
  source_preparation? : @stages.Source? = None,
) -> (Result[ParsedCheckInput, EffectComputationIssue], Int) {
  let work = Ref(0)
  let result = prepare_effect_computation_input_owned(
    program,
    environment,
    supplied,
    evidence,
    limits,
    max_members,
    max_header_work,
    source_catalog~,
    source_preparation~,
    work_out=Some(work),
  )
  (result, work.val)
}

///|
fn prepare_effect_computation_input_owned(
  program : @syntax.Program,
  environment : CheckEnvironment,
  supplied : @decode.Cursor?,
  evidence : Array[@context.StageCapacityInput],
  limits : CheckLimits,
  max_members : Int,
  max_header_work : Int,
  source_catalog? : PreparedSourceCatalog? = None,
  source_preparation? : @stages.Source? = None,
  work_out? : Ref[Int]? = None,
) -> Result[ParsedCheckInput, EffectComputationIssue] {
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
  if work_out is Some(output) {
    output.val = @syntax.effect_headers_work(headers)
  }
  let binding_work = work_out.map(_ => Ref(0))
  let result = Ok(
    prepare_parsed_check_input_owned(
      program,
      environment,
      supplied,
      evidence,
      computation_limits,
      effect_headers=Some(headers),
      source_catalog~,
      source_preparation~,
      binding_work_out=binding_work,
    ),
  ) catch {
    issue => Err(Computation(issue))
  }
  if work_out is Some(output) && binding_work is Some(binding) {
    output.val += binding.val
  }
  result
}

///|
/// Consume the original phased registry once into its actual Effect candidate.
/// Missing inputs or a typed construction refusal remain the original cause;
/// no ordinary CheckedProgram is upgraded into an Effect closure by identity.
pub fn finish_parsed_effect_check_registry(
  prepared : ParsedCheckRegistry,
) -> Result[EffectComputationCandidate, EffectComputationIssue] {
  if !prepared.available {
    return Err(Phase(AlreadyConsumed))
  }
  guard prepared.prelude.original.effect_headers is Some(headers) else {
    return Err(MissingEffects)
  }
  prepared.available = false
  let checked = construct_after_parsed_check_registry(prepared) catch {
    issue => return Err(Computation(issue))
  }
  Ok({ checked, headers, supplied: prepared.prelude.original.supplied, })
}

///|
/// Original immutable computation and supplied Cursor, not an execution permit.
pub fn effect_computation_checked_program(
  candidate : EffectComputationCandidate,
) -> CheckedProgram {
  candidate.checked
}

///|
pub fn effect_computation_supplied(
  candidate : EffectComputationCandidate,
) -> @decode.Cursor? {
  candidate.supplied
}

///|
/// Observe only the original remaining Budget; rejected prefixes remain partial.
pub fn observe_finish_parsed_effect_check_registry(
  prepared : ParsedCheckRegistry,
) -> (Result[EffectComputationCandidate, EffectComputationIssue], Int, Bool) {
  let before = environment_start_budget(prepared.start).work
  let result = finish_parsed_effect_check_registry(prepared)
  let known = Int::max(
    0,
    before - environment_start_budget(prepared.start).work,
  )
  let complete = result is Ok(_)
  (result, known, complete)
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
  let count = @context.program_identity_stage_count(candidate.checked.identity)
  if count > limits.max_work {
    return Err(@results.WorkLimit)
  }
  let parameter_values = Array::makei(count, stage => {
    @context.stage_identity_parameter_values(
      @context.program_identity_stage_at(candidate.checked.identity, stage).unwrap(),
    )
  })
  let effects = match
    @results.prepare_effect_static_candidate(
      candidate.headers,
      checked_stage_results(candidate.checked),
      checked_environment(candidate.checked),
      mappings,
      checked_catalog_references(candidate.checked),
      limits,
      parameter_values~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let local_update_completion_free_audit = audit_local_update_completion_free(
    candidate, effects,
  )
  Ok({ computation: candidate, effects, local_update_completion_free_audit, })
}

///|
pub fn effect_program_static_effects(
  candidate : EffectProgramStaticCandidate,
) -> @results.EffectStaticCandidate {
  candidate.effects
}

///|
/// The exact computation owner retained by the static Effect closure. This
/// permits physical preparation of the computation only; the returned checked
/// Program is not an Effect apply permit or an Effect-free Run proof.
pub fn effect_program_static_checked_computation(
  candidate : EffectProgramStaticCandidate,
) -> CheckedProgram {
  candidate.computation.checked
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
