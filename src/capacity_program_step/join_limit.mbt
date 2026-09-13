///|
pub(all) enum JoinLimitIssue {
  InvalidLimits
  WorkLimit
  InvalidStep
  WrongOperation
  UnresolvedAuthorSource
  ForeignClaims
  MissingMixedClosure
  MissingLimit
  SubjectMismatch
  WrongEnforcement
  UnsupportedCandidate(Int)
  CandidateScopeMismatch(Int)
  MissingHostCandidate
  MissingProgramCandidate(Int)
} derive(Eq, Debug)

///|
/// Local output-limit application, not complete source authority or execution.
struct JoinLimit {
  pipeline : @pipeline.CheckedPipeline
  step : Int
  sources : @host.HostSources
  program : Applications
  policy : @policy.Policy
  limit : @wire.LimitClaim
  index : Int
  work : Int
}

///|
/// Bind a join-family limit to all applicable registered local Program proofs
/// and the selected Host field. Authored guards require a later source boundary.
pub fn check_join_limit(
  pipeline : @pipeline.CheckedPipeline,
  step : Int,
  sources : @host.HostSources,
  program : Applications,
  policy : @policy.Policy,
  index : Int,
  max_work~ : Int,
) -> Result[JoinLimit, JoinLimitIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  guard @pipeline.step_at(pipeline, step) is Some(checked) else {
    return Err(InvalidStep)
  }
  let authored = match checked.operation {
    @pipeline.Join(checked~, ..) => @join.output_guard(checked) is Some(_)
    @pipeline.CrossJoin(checked~, ..) =>
      @join.cross_output_guard(checked) is Some(_)
    @pipeline.IntervalJoin(checked~, ..) =>
      @join.interval_output_guard(checked) is Some(_)
    @pipeline.AsOfJoin(..) => false
    _ => return Err(WrongOperation)
  }
  if authored {
    return Err(UnresolvedAuthorSource)
  }
  if !physical_equal(@host.source_claims(sources), program.claims) {
    return Err(ForeignClaims)
  }
  guard @wire.program_claim_mixed(program.claims) is Some(mixed) else {
    return Err(MissingMixedClosure)
  }
  guard @wire.mixed_limit_at(mixed, index) is Some(limit) else {
    return Err(MissingLimit)
  }
  if @wire.limit_subject(limit) !=
    "join:checked-step:" + step.to_string() + ":output" {
    return Err(SubjectMismatch)
  }
  if @wire.limit_enforcement(limit) != @wire.EngineAtomic {
    return Err(WrongEnforcement)
  }
  let work = match
    check_limit_candidates(
      pipeline,
      step,
      sources,
      program,
      policy,
      limit,
      @arithmetic.Rows,
      Some("max_relation_output_rows"),
      false,
      // A resolved output depends on this minimum; it is not an independent
      // candidate for the minimum that produced it.
      app => app.enforcement is None,
      max_work,
    ) {
    Ok(n) => n
    Err(WorkLimit) => return Err(WorkLimit)
    Err(WrongUnit) => return Err(SubjectMismatch)
    Err(UnsupportedCandidate(i)) => return Err(UnsupportedCandidate(i))
    Err(CandidateScopeMismatch(i)) => return Err(CandidateScopeMismatch(i))
    Err(MissingHostCandidate) => return Err(MissingHostCandidate)
    Err(MissingProgramCandidate(i)) => return Err(MissingProgramCandidate(i))
    Err(MissingProgramEvidence) => return Err(MissingHostCandidate)
  }
  Ok({ pipeline, step, sources, program, policy, limit, index, work, })
}

///|
pub fn join_limit_pipeline(v : JoinLimit) -> @pipeline.CheckedPipeline {
  v.pipeline
}

///|
pub fn join_limit_step(v : JoinLimit) -> Int {
  v.step
}

///|
pub fn join_limit_sources(v : JoinLimit) -> @host.HostSources {
  v.sources
}

///|
pub fn join_limit_program(v : JoinLimit) -> Applications {
  v.program
}

///|
pub fn join_limit_policy(v : JoinLimit) -> @policy.Policy {
  v.policy
}

///|
pub fn join_limit_claim(v : JoinLimit) -> @wire.LimitClaim {
  v.limit
}

///|
pub fn join_limit_index(v : JoinLimit) -> Int {
  v.index
}

///|
pub fn join_limit_work(v : JoinLimit) -> Int {
  v.work
}
