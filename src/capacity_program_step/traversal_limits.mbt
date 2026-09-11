///|
pub(all) enum TraversalScope {
  SearchPaths
  OutputRows
} derive(Eq, Debug)

///|
pub(all) enum TraversalLimitIssue {
  InvalidLimits
  InvalidStep
  WrongOperation
  UnresolvedAuthorSource
  ForeignClaims
  MissingMixedClosure
  MissingLimit(TraversalScope)
  SubjectMismatch(TraversalScope)
  WrongEnforcement(TraversalScope)
  Candidates(TraversalScope, CandidateIssue)
} derive(Eq, Debug)

///|
/// Both local limits retain their source and application owners. This does not
/// discharge runtime enforcement or the enclosing pipeline's remaining limits.
struct TraversalLimits {
  pipeline : @pipeline.CheckedPipeline
  step : Int
  sources : @host.HostSources
  program : Applications
  policy : @policy.Policy
  paths : @wire.LimitClaim
  rows : @wire.LimitClaim
  paths_index : Int
  rows_index : Int
  work : Int
}

///|
pub fn check_traversal_limits(
  pipeline : @pipeline.CheckedPipeline,
  step : Int,
  sources : @host.HostSources,
  program : Applications,
  policy : @policy.Policy,
  paths_index : Int,
  rows_index : Int,
  max_work~ : Int,
) -> Result[TraversalLimits, TraversalLimitIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  guard @pipeline.step_at(pipeline, step) is Some(checked) else {
    return Err(InvalidStep)
  }
  guard checked.operation is @pipeline.Traverse(checked=op, ..) else {
    return Err(WrongOperation)
  }
  if @graph.traverse_output_guard(op) is Some(_) {
    return Err(UnresolvedAuthorSource)
  }
  if !physical_equal(@host.source_claims(sources), program.claims) {
    return Err(ForeignClaims)
  }
  guard @wire.program_claim_mixed(program.claims) is Some(mixed) else {
    return Err(MissingMixedClosure)
  }
  guard @wire.mixed_limit_at(mixed, paths_index) is Some(paths) else {
    return Err(MissingLimit(SearchPaths))
  }
  guard @wire.mixed_limit_at(mixed, rows_index) is Some(rows) else {
    return Err(MissingLimit(OutputRows))
  }
  let subject = "traverse:checked-step:" + step.to_string()
  let mut work = 0
  for
    (scope, limit, suffix, unit, host_field, required, law) in [
      (
        SearchPaths,
        paths,
        ":paths",
        @arithmetic.Paths,
        Some("max_graph_paths"),
        false,
        None,
      ),
      (
        OutputRows,
        rows,
        "",
        @arithmetic.Rows,
        Some("max_graph_output_rows"),
        false,
        Some("actql.bound.traverse-nodes"),
      ),
    ] {
    if @wire.limit_subject(limit) != subject + suffix {
      return Err(SubjectMismatch(scope))
    }
    if @wire.limit_enforcement(limit) != @wire.EngineAtomic {
      return Err(WrongEnforcement(scope))
    }
    match
      check_limit_candidates(
        pipeline,
        step,
        sources,
        program,
        policy,
        limit,
        unit,
        host_field,
        required,
        app => {
          law is Some(name) &&
          @law.name(@wire.law(@wire.program_proof_witness(app.proof))) == name
        },
        max_work - work,
      ) {
      Ok(n) => work += n
      Err(issue) => return Err(Candidates(scope, issue))
    }
  }
  Ok({
    pipeline,
    step,
    sources,
    program,
    policy,
    paths,
    rows,
    paths_index,
    rows_index,
    work,
  })
}

///|
pub fn traversal_limit_pipeline(
  v : TraversalLimits,
) -> @pipeline.CheckedPipeline {
  v.pipeline
}

///|
pub fn traversal_limit_step(v : TraversalLimits) -> Int {
  v.step
}

///|
pub fn traversal_limit_sources(v : TraversalLimits) -> @host.HostSources {
  v.sources
}

///|
pub fn traversal_limit_program(v : TraversalLimits) -> Applications {
  v.program
}

///|
pub fn traversal_limit_policy(v : TraversalLimits) -> @policy.Policy {
  v.policy
}

///|
pub fn traversal_limit_claim(
  v : TraversalLimits,
  scope : TraversalScope,
) -> @wire.LimitClaim {
  match scope {
    SearchPaths => v.paths
    OutputRows => v.rows
  }
}

///|
pub fn traversal_limit_index(
  v : TraversalLimits,
  scope : TraversalScope,
) -> Int {
  match scope {
    SearchPaths => v.paths_index
    OutputRows => v.rows_index
  }
}

///|
pub fn traversal_limit_work(v : TraversalLimits) -> Int {
  v.work
}
