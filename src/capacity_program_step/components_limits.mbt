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
  if max_output_rows is Some(_) {
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
