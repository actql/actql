///|
pub(all) enum ComponentsScope {
  InputNodes
  OutputRows
} derive(Eq, Debug)

///|
pub(all) enum ComponentsLimitIssue {
  InvalidLimits
  InvalidStep
  WrongOperation
  UnresolvedAuthorSource
  ForeignGuardOwner
  MissingGuard
  WorkLimit
  ForeignClaims
  MissingMixedClosure
  MissingLimit(ComponentsScope)
  SubjectMismatch(ComponentsScope)
  WrongEnforcement(ComponentsScope)
  Candidates(ComponentsScope, CandidateIssue)
} derive(Eq, Debug)

///|
/// Both local limits retain their source and application owners. This does not
/// discharge runtime enforcement or the enclosing pipeline's remaining limits.
struct ComponentsLimits {
  pipeline : @pipeline.CheckedPipeline
  step : Int
  sources : @host.HostSources
  program : Applications
  policy : @policy.Policy
  nodes : @wire.LimitClaim
  rows : @wire.LimitClaim
  nodes_index : Int
  rows_index : Int
  work : Int
  guards : @pipeline.BoundAuthorGuards?
  output_guard : Int?
}

///|
pub fn check_components_limits(
  pipeline : @pipeline.CheckedPipeline,
  step : Int,
  sources : @host.HostSources,
  program : Applications,
  policy : @policy.Policy,
  nodes_index : Int,
  rows_index : Int,
  guards? : @pipeline.BoundAuthorGuards? = None,
  max_work~ : Int,
) -> Result[ComponentsLimits, ComponentsLimitIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  guard @pipeline.step_at(pipeline, step) is Some(checked) else {
    return Err(InvalidStep)
  }
  guard checked.operation is @pipeline.Graph(op) else {
    return Err(WrongOperation)
  }
  guard @graph.options(op) is @graph.ComponentOptions(_, max_output_rows~) else {
    return Err(WrongOperation)
  }
  if guards is None && max_output_rows is Some(_) {
    return Err(UnresolvedAuthorSource)
  }
  if !physical_equal(@host.source_claims(sources), program.claims) {
    return Err(ForeignClaims)
  }
  guard @wire.program_claim_mixed(program.claims) is Some(mixed) else {
    return Err(MissingMixedClosure)
  }
  guard @wire.mixed_limit_at(mixed, nodes_index) is Some(nodes) else {
    return Err(MissingLimit(InputNodes))
  }
  guard @wire.mixed_limit_at(mixed, rows_index) is Some(rows) else {
    return Err(MissingLimit(OutputRows))
  }
  let subject = "components:checked-step:" + step.to_string()
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
      if @pipeline.author_guard_scope(
          @pipeline.author_guard_at(occurrences, index).unwrap(),
        ) ==
        @pipeline.ComponentOutputRows {
        output_guard = Some(index)
      }
    }
    if (max_output_rows is Some(_)) != (output_guard is Some(_)) {
      return Err(MissingGuard)
    }
  }
  for
    (scope, limit, suffix, unit, host_field, required, law) in [
      (
        InputNodes,
        nodes,
        ":nodes",
        @arithmetic.Nodes,
        None,
        true,
        "actql.bound.components-input-nodes",
      ),
      (
        OutputRows,
        rows,
        "",
        @arithmetic.Rows,
        Some("max_graph_output_rows"),
        false,
        "actql.bound.components-nodes",
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
          @law.name(@wire.law(@wire.program_proof_witness(app.proof))) == law
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
    nodes,
    rows,
    nodes_index,
    rows_index,
    work,
    guards,
    output_guard,
  })
}

///|
pub fn components_limit_pipeline(
  v : ComponentsLimits,
) -> @pipeline.CheckedPipeline {
  v.pipeline
}

///|
pub fn components_limit_step(v : ComponentsLimits) -> Int {
  v.step
}

///|
pub fn components_limit_sources(v : ComponentsLimits) -> @host.HostSources {
  v.sources
}

///|
pub fn components_limit_program(v : ComponentsLimits) -> Applications {
  v.program
}

///|
pub fn components_limit_policy(v : ComponentsLimits) -> @policy.Policy {
  v.policy
}

///|
/// Original admitted candidates; use components_limit_effective_maximum to
/// include the separately owned authored output restriction.
pub fn components_limit_claim(
  v : ComponentsLimits,
  scope : ComponentsScope,
) -> @wire.LimitClaim {
  match scope {
    InputNodes => v.nodes
    OutputRows => v.rows
  }
}

///|
pub fn components_limit_guards(
  v : ComponentsLimits,
) -> @pipeline.BoundAuthorGuards? {
  v.guards
}

///|
pub fn components_limit_guard_index(v : ComponentsLimits) -> Int? {
  v.output_guard
}

///|
pub fn components_limit_guard_value(v : ComponentsLimits) -> Int64? {
  guard v.guards is Some(guards) && v.output_guard is Some(index) else {
    return None
  }
  @pipeline.bound_guard_value_at(guards, index)
}

///|
/// Original claims remain unchanged; the bound author guard restricts output only.
pub fn components_limit_effective_maximum(
  v : ComponentsLimits,
  scope : ComponentsScope,
) -> Int64 {
  let maximum = @arithmetic.minimum_value(
    @wire.limit_minimum(components_limit_claim(v, scope)),
  )
  match (scope, components_limit_guard_value(v)) {
    (OutputRows, Some(value)) => maximum.min(value)
    _ => maximum
  }
}

///|
pub fn components_limit_index(
  v : ComponentsLimits,
  scope : ComponentsScope,
) -> Int {
  match scope {
    InputNodes => v.nodes_index
    OutputRows => v.rows_index
  }
}

///|
pub fn components_limit_work(v : ComponentsLimits) -> Int {
  v.work
}
