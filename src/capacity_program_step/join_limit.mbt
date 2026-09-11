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
  let minimum = @wire.limit_minimum(limit)
  let n = @arithmetic.minimum_candidate_count(minimum)
  let entries = program.entries.length()
  if entries > max_work || n > max_work - entries {
    return Err(WorkLimit)
  }
  let seen : Map[Int, Bool] = Map([])
  let mut host_present = false
  for i in 0..<n {
    let candidate = @arithmetic.minimum_candidate_at(minimum, i).unwrap()
    if @host.source_at(sources, candidate.node) is Some(host) {
      let ceiling = @host.ceiling(host)
      if @policy.cid(@policy.ceiling_policy(ceiling)) != @policy.cid(policy) ||
        @policy.ceiling_field(ceiling) != "max_relation_output_rows" ||
        @host.unit(host) != @arithmetic.Rows {
        return Err(CandidateScopeMismatch(i))
      }
      host_present = true
    } else {
      guard program.entries[candidate.node] is Some(app) else {
        return Err(UnsupportedCandidate(i))
      }
      if !physical_equal(app.pipeline, pipeline) || app.index != step {
        return Err(CandidateScopeMismatch(i))
      }
      seen[candidate.node] = true
    }
  }
  if !host_present {
    return Err(MissingHostCandidate)
  }
  for i, app in program.entries {
    if app is Some(app) &&
      physical_equal(app.pipeline, pipeline) &&
      app.index == step &&
      !seen.contains(i) {
      return Err(MissingProgramCandidate(i))
    }
  }
  Ok({
    pipeline,
    step,
    sources,
    program,
    policy,
    limit,
    index,
    work: entries + n,
  })
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
