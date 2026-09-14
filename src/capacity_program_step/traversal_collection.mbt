///|
pub(all) enum TraversalCollectionIssue {
  InvalidLimits
  WorkLimit
  ForeignClaims
  MissingMixedClosure
  ForeignPipeline(Int)
  ForeignSources(Int)
  ForeignProgram(Int)
  ForeignPolicy(Int)
  ForeignGuardBindings(Int)
  DuplicateApplication(Int)
  DuplicateConsumption(Int)
  MissingApplication(Int)
  UnconsumedLimits(Int)
} derive(Eq, Debug)

///|
struct TraversalApplications {
  pipeline : @pipeline.CheckedPipeline
  sources : @host.HostSources
  program : Applications
  policy : @policy.Policy
  entries : Array[TraversalLimits?]
  consumed : Array[Bool]
  remaining : Int
  work : Int
  guards : @pipeline.BoundAuthorGuards?
}

///|
/// Cover every local traversal step using one consistent proof/source owner.
/// Other consumers, upstream closure and source authority remain separate.
pub fn check_traversal_applications(
  pipeline : @pipeline.CheckedPipeline,
  sources : @host.HostSources,
  program : Applications,
  policy : @policy.Policy,
  applications : Array[TraversalLimits],
  max_work~ : Int,
) -> Result[TraversalApplications, TraversalCollectionIssue] {
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
    a > (max_work - n * 2 - limits) / 3 {
    return Err(WorkLimit)
  }
  let work = n * 2 + limits + a * 3
  let entries : Array[TraversalLimits?] = Array::make(n, None)
  let consumed = Array::make(limits, false)
  let mut guards = None
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
    if app.guards is Some(bound) {
      if guards is Some(previous) &&
        !same_capacity_guard_bindings(previous, bound) {
        return Err(ForeignGuardBindings(i))
      }
      guards = Some(bound)
    }
    for index in [app.paths_index, app.rows_index] {
      if consumed[index] {
        return Err(DuplicateConsumption(index))
      }
      consumed[index] = true
    }
    entries[app.step] = Some(app)
  }
  for i in 0..<n {
    let required = match @pipeline.step_at(pipeline, i).unwrap().operation {
      @pipeline.Traverse(..) | @pipeline.Reach(_) | @pipeline.Shortest(..) =>
        true
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
    remaining: limits - a * 2,
    work,
    guards,
  })
}

///|
pub fn check_traversal_complete(
  pipeline : @pipeline.CheckedPipeline,
  sources : @host.HostSources,
  program : Applications,
  policy : @policy.Policy,
  applications : Array[TraversalLimits],
  max_work~ : Int,
) -> Result[TraversalApplications, TraversalCollectionIssue] {
  match
    check_traversal_applications(
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
pub fn traversal_application_at(
  v : TraversalApplications,
  step : Int,
) -> TraversalLimits? {
  v.entries.get(step).bind(x => x)
}

///|
pub fn traversal_application_pipeline(
  v : TraversalApplications,
) -> @pipeline.CheckedPipeline {
  v.pipeline
}

///|
pub fn traversal_application_sources(
  v : TraversalApplications,
) -> @host.HostSources {
  v.sources
}

///|
pub fn traversal_application_program(v : TraversalApplications) -> Applications {
  v.program
}

///|
pub fn traversal_application_policy(
  v : TraversalApplications,
) -> @policy.Policy {
  v.policy
}

///|
pub fn traversal_consumes_limit(v : TraversalApplications, index : Int) -> Bool {
  v.consumed.get(index).unwrap_or(false)
}

///|
pub fn traversal_unconsumed_limit_count(v : TraversalApplications) -> Int {
  v.remaining
}

///|
pub fn traversal_application_work(v : TraversalApplications) -> Int {
  v.work
}

///|
fn same_capacity_guard_bindings(
  a : @pipeline.BoundAuthorGuards,
  b : @pipeline.BoundAuthorGuards,
) -> Bool {
  if !physical_equal(
      @pipeline.author_guards_pipeline(@pipeline.bound_guard_occurrences(a)),
      @pipeline.author_guards_pipeline(@pipeline.bound_guard_occurrences(b)),
    ) {
    return false
  }
  match (@pipeline.bound_guard_bindings(a), @pipeline.bound_guard_bindings(b)) {
    (None, None) => true
    (Some(a), Some(b)) => physical_equal(a, b)
    _ => false
  }
}

///|
pub fn traversal_application_guard_bindings_match(
  v : TraversalApplications,
  expected : @pipeline.BoundAuthorGuards,
) -> Bool {
  if !physical_equal(
      v.pipeline,
      @pipeline.author_guards_pipeline(
        @pipeline.bound_guard_occurrences(expected),
      ),
    ) {
    return false
  }
  match v.guards {
    None => true
    Some(bound) => same_capacity_guard_bindings(bound, expected)
  }
}
