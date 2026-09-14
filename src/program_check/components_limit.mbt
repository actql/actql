///|
struct ComponentsLimit {
  source : UnitOperationSource
  selected : @context.ComponentsLimitsCheck
  nodes : @wire.LimitClaim
  output : @wire.LimitClaim
  proofs : Array[ReidentifiedStep]
}

///|
pub fn components_limit_source(v : ComponentsLimit) -> UnitOperationSource {
  v.source
}

///|
pub fn components_limit_selection(
  v : ComponentsLimit,
) -> @context.ComponentsLimitsCheck {
  v.selected
}

///|
pub fn components_limit_claim(
  v : ComponentsLimit,
  scope : @step_bounds.ComponentsScope,
) -> @wire.LimitClaim {
  match scope {
    InputNodes => v.nodes
    OutputRows => v.output
  }
}

///|
pub fn components_limit_proof_count(v : ComponentsLimit) -> Int {
  v.proofs.length()
}

///|
pub fn components_limit_proof_at(
  v : ComponentsLimit,
  index : Int,
) -> ReidentifiedStep? {
  v.proofs.get(index)
}

///|
fn assemble_components_limit(
  units : Array[BuiltUnit],
  source : UnitOperationSource,
  selected : @context.ComponentsLimitsCheck,
  budget : IdentityBudget,
) -> ComponentsLimit raise UnitBuildFailure {
  guard physical_equal(source.pipeline, selected.site.pipeline) &&
    source.source_ordinal == selected.site.step &&
    physical_equal(
      @step_bounds.components_limit_pipeline(selected.limits),
      source.pipeline,
    ) &&
    @step_bounds.components_limit_step(selected.limits) == source.source_ordinal else {
    raise ForeignOwner
  }
  let applications = @step_bounds.components_limit_program(selected.limits)
  let (limits, proofs) = assemble_operation_capacity_limits(
    units,
    applications,
    unit_operation_subject(source, budget) + "/components/",
    [
      (
        @step_bounds.components_limit_claim(
          selected.limits,
          @step_bounds.InputNodes,
        ),
        "nodes",
        "nodes",
      ),
      (
        @step_bounds.components_limit_claim(
          selected.limits,
          @step_bounds.ComponentsScope::OutputRows,
        ),
        "output",
        "rows",
      ),
    ],
    budget,
  )
  { source, selected, nodes: limits[0], output: limits[1], proofs, }
}

///|
fn prepare_program_components_limits(
  units : Array[BuiltUnit],
  requirements : @context.StageRequirementClosure,
  budget : IdentityBudget,
) -> Array[Array[ComponentsLimit]] raise UnitBuildFailure {
  let remaining = IdentityBudget::{ ..budget, }
  identity_charge(remaining, units.length())
  let result = Array::makei(units.length(), _ => [])
  let closure = @context.stage_requirement_operations(requirements)
  let identity = @context.expression_closure_identity(
    @context.operation_requirements_expressions(
      @context.operation_resolution_requirements(
        @context.operation_closure_index(closure),
      ),
    ),
  )
  for stage, unit in units {
    identity_charge(remaining, 1)
    guard @context.program_identity_stage_at(identity, stage) is Some(expected) &&
      physical_equal(expected, unit.source) else {
      raise ForeignOwner
    }
  }
  let seen : Map[(Int, Int), Bool] = Map([])
  for index in 0..<@context.operation_closure_count(closure) {
    identity_charge(remaining, 1)
    guard @context.operation_closure_at(closure, index)
      is Some(ExecutionCheck(ComponentsLimits(selected))) else {
      continue
    }
    let site = selected.site
    guard units.get(site.stage) is Some(unit) else { raise ForeignOwner }
    // Imported visits use the producer Unit's retained limit, not a consumer copy.
    if !physical_equal(unit.pipeline, site.pipeline) {
      continue
    }
    if seen.contains((site.stage, site.step)) {
      raise ForeignOwner
    }
    seen[(site.stage, site.step)] = true
    guard unit_operation_source(unit, site.pipeline, site.step) is Some(source) else {
      raise ForeignOwner
    }
    let limit = assemble_components_limit(units, source, selected, remaining)
    identity_charge(remaining, 1)
    result[site.stage].push(limit)
  }
  budget.work = remaining.work
  budget.bytes = remaining.bytes
  budget.nodes = remaining.nodes
  result
}

///|
pub fn unit_components_limit_count(
  program : CheckedProgram,
  stage : Int,
) -> Int? {
  program.components_limits.get(stage).map(v => v.length())
}

///|
pub fn unit_components_limit_at(
  program : CheckedProgram,
  stage : Int,
  index : Int,
) -> ComponentsLimit? {
  program.components_limits.get(stage).bind(v => v.get(index))
}
