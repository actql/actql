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
  ForeignGuardOwner
  MissingGuard
  WorkLimit
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
/// Covers only checked traversal operations; unsupported authored consumers
/// cannot acquire an application or runtime permission.
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
  guards : @pipeline.BoundAuthorGuards?
  output_guard : Int?
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
  guards? : @pipeline.BoundAuthorGuards? = None,
  max_work~ : Int,
) -> Result[TraversalLimits, TraversalLimitIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  guard @pipeline.step_at(pipeline, step) is Some(checked) else {
    return Err(InvalidStep)
  }
  let (operation_name, authored_guard, output_law, guard_scope) = match
    checked.operation {
    @pipeline.Traverse(checked=op, ..) =>
      (
        "traverse",
        @graph.traverse_output_guard(op),
        Some("actql.bound.traverse-nodes"),
        Some(@pipeline.TraverseOutputRows),
      )
    _ => return Err(WrongOperation)
  }
  if guards is None && authored_guard is Some(_) {
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
  let subject = operation_name + ":checked-step:" + step.to_string()
  let mut work = 0
  let mut output_guard = None
  if guards is Some(bound) {
    let occurrences = @pipeline.bound_guard_occurrences(bound)
    if !physical_equal(@pipeline.author_guards_pipeline(occurrences), pipeline) {
      return Err(ForeignGuardOwner)
    }
    let (first, end) = @pipeline.author_guard_step_range(occurrences, step).unwrap()
    if end - first > max_work {
      return Err(WorkLimit)
    }
    work += end - first
    for index in first..<end {
      let occurrence = @pipeline.author_guard_at(occurrences, index).unwrap()
      if Some(@pipeline.author_guard_scope(occurrence)) == guard_scope {
        output_guard = Some(index)
      }
    }
    if (authored_guard is Some(_)) != (output_guard is Some(_)) {
      return Err(MissingGuard)
    }
  }
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
        output_law,
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
    guards,
    output_guard,
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
/// Original admitted candidates; authored guards are retained separately.
/// Use traversal_limit_effective_maximum for the combined restriction.
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

///|
/// Bound authored restriction, separate from the admitted candidate claims.
/// Minting its persistent witness requires the enclosing Unit identity.
pub fn traversal_limit_guards(
  v : TraversalLimits,
) -> @pipeline.BoundAuthorGuards? {
  v.guards
}

///|
pub fn traversal_limit_guard_index(v : TraversalLimits) -> Int? {
  v.output_guard
}

///|
pub fn traversal_limit_guard_value(v : TraversalLimits) -> Int64? {
  guard v.guards is Some(guards) && v.output_guard is Some(index) else {
    return None
  }
  @pipeline.bound_guard_value_at(guards, index)
}

///|
/// SearchPaths is independent of the authored output-row restriction.
pub fn traversal_limit_effective_maximum(
  v : TraversalLimits,
  scope : TraversalScope,
) -> Int64 {
  let maximum = @arithmetic.minimum_value(
    @wire.limit_minimum(traversal_limit_claim(v, scope)),
  )
  match (scope, traversal_limit_guard_value(v)) {
    (OutputRows, Some(value)) => if value < maximum { value } else { maximum }
    _ => maximum
  }
}
