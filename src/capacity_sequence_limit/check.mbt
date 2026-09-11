///|
pub(all) enum Scope {
  MatchesPerKey
  OutputRows
} derive(Eq, Debug)

///|
pub(all) enum Issue {
  InvalidLimits
  WorkLimit
  InvalidStep
  WrongOperation
  UnresolvedAuthorSource(Scope)
  MissingMixedClosure
  MissingLimit(Scope)
  SubjectMismatch(Scope)
  WrongEnforcement(Scope)
  UnsupportedCandidate(Scope, Int)
  CandidateScopeMismatch(Scope, Int)
} derive(Eq, Debug)

///|
/// Local consumer association, not Host authority or runtime enforcement.
struct SequenceLimits {
  pipeline : @pipeline.CheckedPipeline
  step : Int
  sources : @host.HostSources
  policy : @policy.Policy
  matches : @wire.LimitClaim
  output : @wire.LimitClaim
  match_index : Int
  output_index : Int
  work : Int
}

///|
/// Requires both Host-only sequence limits from the retained mixed collection.
/// Authored guards fail explicitly until their source identity can be bound.
pub fn check_host_limits(
  pipeline : @pipeline.CheckedPipeline,
  step : Int,
  sources : @host.HostSources,
  policy : @policy.Policy,
  match_index : Int,
  output_index : Int,
  max_work~ : Int,
) -> Result[SequenceLimits, Issue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  guard @pipeline.step_at(pipeline, step) is Some(checked) else {
    return Err(InvalidStep)
  }
  guard checked.operation is @pipeline.Sequence(operation) else {
    return Err(WrongOperation)
  }
  if @relation.sequence_per_key_guard(operation) is Some(_) {
    return Err(UnresolvedAuthorSource(MatchesPerKey))
  }
  if @relation.sequence_output_guard(operation) is Some(_) {
    return Err(UnresolvedAuthorSource(OutputRows))
  }
  guard @wire.program_claim_mixed(@host.source_claims(sources)) is Some(mixed) else {
    return Err(MissingMixedClosure)
  }
  guard @wire.mixed_limit_at(mixed, match_index) is Some(matches) else {
    return Err(MissingLimit(MatchesPerKey))
  }
  guard @wire.mixed_limit_at(mixed, output_index) is Some(output) else {
    return Err(MissingLimit(OutputRows))
  }
  let mut work = 0
  for (scope, limit) in [(MatchesPerKey, matches), (OutputRows, output)] {
    let minimum = @wire.limit_minimum(limit)
    let n = @arithmetic.minimum_candidate_count(minimum)
    if work >= max_work || n > max_work - work - 1 {
      return Err(WorkLimit)
    }
    work += n + 1
    let (suffix, field, unit) = match scope {
      MatchesPerKey =>
        (
          "matches-per-key",
          "max_temporal_matches_per_key",
          @arithmetic.MatchesPerKey,
        )
      OutputRows => ("output", "max_temporal_output_rows", @arithmetic.Rows)
    }
    if @wire.limit_subject(limit) !=
      "sequence:checked-step:" + step.to_string() + ":" + suffix {
      return Err(SubjectMismatch(scope))
    }
    if @wire.limit_enforcement(limit) != @wire.EngineAtomic {
      return Err(WrongEnforcement(scope))
    }
    // Limit admission requires a nonempty, same-unit candidate list and checks
    // the exact minimum. Every occurrence must be the applicable selected Host
    // field; no unrelated same-valued policy ceiling can stand in for it.
    for j in 0..<n {
      let candidate = @arithmetic.minimum_candidate_at(minimum, j).unwrap()
      guard @host.source_at(sources, candidate.node) is Some(source) else {
        return Err(UnsupportedCandidate(scope, j))
      }
      let ceiling = @host.ceiling(source)
      if @policy.cid(@policy.ceiling_policy(ceiling)) != @policy.cid(policy) ||
        @policy.ceiling_field(ceiling) != field ||
        @host.unit(source) != unit {
        return Err(CandidateScopeMismatch(scope, j))
      }
    }
  }
  Ok({
    pipeline,
    step,
    sources,
    policy,
    matches,
    output,
    match_index,
    output_index,
    work,
  })
}

///|
pub fn checked_pipeline(v : SequenceLimits) -> @pipeline.CheckedPipeline {
  v.pipeline
}

///|
pub fn checked_step(v : SequenceLimits) -> Int {
  v.step
}

///|
pub fn checked_sources(v : SequenceLimits) -> @host.HostSources {
  v.sources
}

///|
pub fn selected_policy(v : SequenceLimits) -> @policy.Policy {
  v.policy
}

///|
pub fn limit(v : SequenceLimits, scope : Scope) -> @wire.LimitClaim {
  if scope == MatchesPerKey {
    v.matches
  } else {
    v.output
  }
}

///|
pub fn limit_index(v : SequenceLimits, scope : Scope) -> Int {
  if scope == MatchesPerKey {
    v.match_index
  } else {
    v.output_index
  }
}

///|
pub fn usage(v : SequenceLimits) -> Int {
  v.work
}
