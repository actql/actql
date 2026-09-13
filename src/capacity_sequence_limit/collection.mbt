///|
pub(all) enum CollectionIssue {
  InvalidLimits
  WorkLimit
  MissingMixedClosure
  ForeignPipeline(Int)
  ForeignSources(Int)
  ForeignPolicy(Int)
  DuplicateApplication(Int)
  DuplicateConsumption(Int)
  MissingApplication(Int)
  UnconsumedLimits(Int)
  ForeignGuardBindings(Int)
} derive(Eq, Debug)

///|
/// Complete local sequence coverage; other consumers and sources remain separate.
struct Applications {
  pipeline : @pipeline.CheckedPipeline
  sources : @host.HostSources
  policy : @policy.Policy
  entries : Array[SequenceLimits?]
  consumed : Array[Bool]
  remaining : Int
  work : Int
  guards : @pipeline.BoundAuthorGuards?
}

///|
/// Require one checked application for every sequence, including unused steps.
/// All entries must retain this exact pipeline and source-collection owner.
pub fn check_applications(
  pipeline : @pipeline.CheckedPipeline,
  sources : @host.HostSources,
  policy : @policy.Policy,
  applications : Array[SequenceLimits],
  max_work~ : Int,
) -> Result[Applications, CollectionIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  guard @wire.program_claim_mixed(@host.source_claims(sources)) is Some(mixed) else {
    return Err(MissingMixedClosure)
  }
  let n = @pipeline.step_count(pipeline)
  let limits = @wire.mixed_limit_count(mixed)
  let a = applications.length()
  // Two step visits (owned slots and coverage), one per limit slot, and one
  // registration plus two scope consumptions per supplied application.
  if n > max_work / 2 ||
    limits > max_work - n * 2 ||
    a > (max_work - n * 2 - limits) / 3 {
    return Err(WorkLimit)
  }
  let work = n * 2 + limits + a * 3
  let entries : Array[SequenceLimits?] = Array::make(n, None)
  let consumed = Array::make(limits, false)
  let mut guards = None
  for i, app in applications {
    if !physical_equal(app.pipeline, pipeline) {
      return Err(ForeignPipeline(i))
    }
    if !physical_equal(app.sources, sources) {
      return Err(ForeignSources(i))
    }
    if @policy.cid(app.policy) != @policy.cid(policy) {
      return Err(ForeignPolicy(i))
    }
    if app.guards is Some(bound) {
      if guards is Some(previous) && !same_guard_bindings(previous, bound) {
        return Err(ForeignGuardBindings(i))
      }
      guards = Some(bound)
    }
    if entries[app.step] is Some(_) {
      return Err(DuplicateApplication(i))
    }
    entries[app.step] = Some(app)
    for index in [app.match_index, app.output_index] {
      if consumed[index] {
        return Err(DuplicateConsumption(index))
      }
      consumed[index] = true
    }
  }
  for i in 0..<n {
    if @pipeline.step_at(pipeline, i).unwrap().operation
      is @pipeline.Sequence(_) &&
      entries[i] is None {
      return Err(MissingApplication(i))
    }
  }
  Ok({
    pipeline,
    sources,
    policy,
    entries,
    consumed,
    remaining: limits - a * 2,
    work,
    guards,
  })
}

///|
/// Also require this dedicated collection to contain no other limit consumers.
/// Does not claim completeness for non-sequence operations or upstream owners.
pub fn check_complete(
  pipeline : @pipeline.CheckedPipeline,
  sources : @host.HostSources,
  policy : @policy.Policy,
  applications : Array[SequenceLimits],
  max_work~ : Int,
) -> Result[Applications, CollectionIssue] {
  match check_applications(pipeline, sources, policy, applications, max_work~) {
    Err(e) => Err(e)
    Ok(v) =>
      if v.remaining == 0 {
        Ok(v)
      } else {
        Err(UnconsumedLimits(v.remaining))
      }
  }
}

///|
pub fn application_at(v : Applications, step : Int) -> SequenceLimits? {
  v.entries.get(step).bind(x => x)
}

///|
pub fn application_pipeline(v : Applications) -> @pipeline.CheckedPipeline {
  v.pipeline
}

///|
pub fn application_sources(v : Applications) -> @host.HostSources {
  v.sources
}

///|
pub fn application_policy(v : Applications) -> @policy.Policy {
  v.policy
}

///|
pub fn consumes_limit(v : Applications, index : Int) -> Bool {
  v.consumed.get(index).unwrap_or(false)
}

///|
pub fn unconsumed_limit_count(v : Applications) -> Int {
  v.remaining
}

///|
pub fn application_work(v : Applications) -> Int {
  v.work
}
