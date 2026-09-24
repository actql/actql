///|
/// A computation check with retained Effect declarations, not an Effect
/// admission or an executable CheckedProgram. The ordinary checker continues
/// to reject nonempty Effects until their complete closure is connected.
struct EffectComputationCandidate {
  checked : CheckedProgram
  headers : @syntax.EffectHeaders
}

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
/// The static Mapping/Command candidate consumes the exact owners retained
/// above. It still cannot authorize an Effect, Preview, apply, or Run.
pub fn prepare_effect_computation_static(
  candidate : EffectComputationCandidate,
  mappings : @environment.MappingContractShapes,
  limits : @results.EffectStaticCandidateLimits,
) -> Result[@results.EffectStaticCandidate, @results.EffectStaticCandidateIssue] {
  @results.prepare_effect_static_candidate(
    candidate.headers,
    checked_stage_results(candidate.checked),
    checked_environment(candidate.checked),
    mappings,
    checked_catalog_references(candidate.checked),
    limits,
  )
}
