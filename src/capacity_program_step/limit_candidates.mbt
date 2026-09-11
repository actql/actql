///|
pub(all) enum CandidateIssue {
  WorkLimit
  WrongUnit
  UnsupportedCandidate(Int)
  CandidateScopeMismatch(Int)
  MissingHostCandidate
  MissingProgramCandidate(Int)
  MissingProgramEvidence
} derive(Eq, Debug)

///|
// Shared applicability scan, not a caller-supplied proof policy. Public
// operation consumers select these arguments from their checked operation.
fn check_limit_candidates(
  pipeline : @pipeline.CheckedPipeline,
  step : Int,
  sources : @host.HostSources,
  program : Applications,
  policy : @policy.Policy,
  limit : @wire.LimitClaim,
  unit : @arithmetic.BoundUnit,
  host_field : String?,
  require_program : Bool,
  accepts : (StepBound) -> Bool,
  max_work : Int,
) -> Result[Int, CandidateIssue] {
  let minimum = @wire.limit_minimum(limit)
  if @arithmetic.minimum_unit(minimum) != unit {
    return Err(WrongUnit)
  }
  let n = @arithmetic.minimum_candidate_count(minimum)
  let entries = program.entries.length()
  if entries > max_work || n > max_work - entries {
    return Err(WorkLimit)
  }
  let seen : Map[Int, Bool] = Map([])
  let mut host_present = false
  let mut program_present = false
  for i in 0..<n {
    let candidate = @arithmetic.minimum_candidate_at(minimum, i).unwrap()
    if @host.source_at(sources, candidate.node) is Some(host) {
      let ceiling = @host.ceiling(host)
      if @policy.cid(@policy.ceiling_policy(ceiling)) != @policy.cid(policy) ||
        host_field != Some(@policy.ceiling_field(ceiling)) ||
        @host.unit(host) != unit {
        return Err(CandidateScopeMismatch(i))
      }
      host_present = true
    } else {
      guard program.entries[candidate.node] is Some(app) else {
        return Err(UnsupportedCandidate(i))
      }
      if !physical_equal(app.pipeline, pipeline) ||
        app.index != step ||
        @wire.unit(@wire.program_proof_witness(app.proof)) != unit ||
        !accepts(app) {
        return Err(CandidateScopeMismatch(i))
      }
      program_present = true
      seen[candidate.node] = true
    }
  }
  if host_field is Some(_) && !host_present {
    return Err(MissingHostCandidate)
  }
  if require_program && !program_present {
    return Err(MissingProgramEvidence)
  }
  for i, app in program.entries {
    if app is Some(app) &&
      physical_equal(app.pipeline, pipeline) &&
      app.index == step &&
      @wire.unit(@wire.program_proof_witness(app.proof)) == unit &&
      accepts(app) &&
      !seen.contains(i) {
      return Err(MissingProgramCandidate(i))
    }
  }
  Ok(entries + n)
}
