///|
pub(all) enum JoinCollectionIssue {
  InvalidLimits
  WorkLimit
  ForeignClaims
  MissingMixedClosure
  ForeignPipeline(Int)
  ForeignSources(Int)
  ForeignProgram(Int)
  ForeignPolicy(Int)
  DuplicateApplication(Int)
  DuplicateConsumption(Int)
  MissingApplication(Int)
  UnconsumedLimits(Int)
} derive(Eq, Debug)

///|
struct JoinApplications {
  pipeline : @pipeline.CheckedPipeline
  sources : @host.HostSources
  program : Applications
  policy : @policy.Policy
  entries : Array[JoinLimit?]
  consumed : Array[Bool]
  remaining : Int
  work : Int
}

///|
/// Cover every local join-family step using one consistent proof/source owner.
/// Other consumers, upstream closure and source authority remain separate.
pub fn check_join_applications(
  pipeline : @pipeline.CheckedPipeline,
  sources : @host.HostSources,
  program : Applications,
  policy : @policy.Policy,
  applications : Array[JoinLimit],
  max_work~ : Int,
) -> Result[JoinApplications, JoinCollectionIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  if !physical_equal(@host.source_claims(sources), program.claims) {
    return Err(ForeignClaims)
  }
  guard @wire.program_claim_mixed(program.claims) is Some(mixed) else {
    return Err(MissingMixedClosure)
  }
  let n = @pipeline.step_count(pipeline)
  let limits = @wire.mixed_limit_count(mixed)
  let a = applications.length()
  if n > max_work / 2 ||
    limits > max_work - n * 2 ||
    a > (max_work - n * 2 - limits) / 2 {
    return Err(WorkLimit)
  }
  let work = n * 2 + limits + a * 2
  let entries : Array[JoinLimit?] = Array::make(n, None)
  let consumed = Array::make(limits, false)
  for i, app in applications {
    if !physical_equal(app.pipeline, pipeline) {
      return Err(ForeignPipeline(i))
    }
    if !physical_equal(app.sources, sources) {
      return Err(ForeignSources(i))
    }
    if !physical_equal(app.program, program) {
      return Err(ForeignProgram(i))
    }
    if @policy.cid(app.policy) != @policy.cid(policy) {
      return Err(ForeignPolicy(i))
    }
    if entries[app.step] is Some(_) {
      return Err(DuplicateApplication(i))
    }
    if consumed[app.index] {
      return Err(DuplicateConsumption(app.index))
    }
    entries[app.step] = Some(app)
    consumed[app.index] = true
  }
  for i in 0..<n {
    let required = match @pipeline.step_at(pipeline, i).unwrap().operation {
      @pipeline.Join(..)
      | @pipeline.CrossJoin(..)
      | @pipeline.IntervalJoin(..)
      | @pipeline.AsOfJoin(..) => true
      _ => false
    }
    if required && entries[i] is None {
      return Err(MissingApplication(i))
    }
  }
  Ok({
    pipeline,
    sources,
    program,
    policy,
    entries,
    consumed,
    remaining: limits - a,
    work,
  })
}

///|
pub fn check_join_complete(
  pipeline : @pipeline.CheckedPipeline,
  sources : @host.HostSources,
  program : Applications,
  policy : @policy.Policy,
  applications : Array[JoinLimit],
  max_work~ : Int,
) -> Result[JoinApplications, JoinCollectionIssue] {
  match
    check_join_applications(
      pipeline,
      sources,
      program,
      policy,
      applications,
      max_work~,
    ) {
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
pub fn join_application_at(v : JoinApplications, step : Int) -> JoinLimit? {
  v.entries.get(step).bind(x => x)
}

///|
pub fn join_application_pipeline(
  v : JoinApplications,
) -> @pipeline.CheckedPipeline {
  v.pipeline
}

///|
pub fn join_application_sources(v : JoinApplications) -> @host.HostSources {
  v.sources
}

///|
pub fn join_application_program(v : JoinApplications) -> Applications {
  v.program
}

///|
pub fn join_application_policy(v : JoinApplications) -> @policy.Policy {
  v.policy
}

///|
pub fn join_consumes_limit(v : JoinApplications, index : Int) -> Bool {
  v.consumed.get(index).unwrap_or(false)
}

///|
pub fn join_unconsumed_limit_count(v : JoinApplications) -> Int {
  v.remaining
}

///|
pub fn join_application_work(v : JoinApplications) -> Int {
  v.work
}
