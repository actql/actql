///|
pub(all) enum ComponentsCollectionIssue {
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
struct ComponentsApplications {
  pipeline : @pipeline.CheckedPipeline
  sources : @host.HostSources
  program : Applications
  policy : @policy.Policy
  entries : Array[ComponentsLimits?]
  consumed : Array[Bool]
  remaining : Int
  work : Int
  guards : @pipeline.BoundAuthorGuards?
}

///|
/// Cover every local components step using one consistent proof/source owner.
/// Other consumers, upstream closure and source authority remain separate.
pub fn check_components_applications(
  pipeline : @pipeline.CheckedPipeline,
  sources : @host.HostSources,
  program : Applications,
  policy : @policy.Policy,
  applications : Array[ComponentsLimits],
  max_work~ : Int,
) -> Result[ComponentsApplications, ComponentsCollectionIssue] {
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
  let entries : Array[ComponentsLimits?] = Array::make(n, None)
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
    for index in [app.nodes_index, app.rows_index] {
      if consumed[index] {
        return Err(DuplicateConsumption(index))
      }
      consumed[index] = true
    }
    entries[app.step] = Some(app)
  }
  for i in 0..<n {
    let required = match @pipeline.step_at(pipeline, i).unwrap().operation {
      @pipeline.Graph(op) => @graph.operation(op) == @graph.Components
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
pub fn components_application_guard_bindings_match(
  v : ComponentsApplications,
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

///|
pub fn check_components_complete(
  pipeline : @pipeline.CheckedPipeline,
  sources : @host.HostSources,
  program : Applications,
  policy : @policy.Policy,
  applications : Array[ComponentsLimits],
  max_work~ : Int,
) -> Result[ComponentsApplications, ComponentsCollectionIssue] {
  match
    check_components_applications(
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
pub fn components_application_at(
  v : ComponentsApplications,
  step : Int,
) -> ComponentsLimits? {
  v.entries.get(step).bind(x => x)
}

///|
pub fn components_application_pipeline(
  v : ComponentsApplications,
) -> @pipeline.CheckedPipeline {
  v.pipeline
}

///|
pub fn components_application_sources(
  v : ComponentsApplications,
) -> @host.HostSources {
  v.sources
}

///|
pub fn components_application_program(
  v : ComponentsApplications,
) -> Applications {
  v.program
}

///|
pub fn components_application_policy(
  v : ComponentsApplications,
) -> @policy.Policy {
  v.policy
}

///|
pub fn components_consumes_limit(
  v : ComponentsApplications,
  index : Int,
) -> Bool {
  v.consumed.get(index).unwrap_or(false)
}

///|
pub fn components_unconsumed_limit_count(v : ComponentsApplications) -> Int {
  v.remaining
}

///|
pub fn components_application_work(v : ComponentsApplications) -> Int {
  v.work
}
