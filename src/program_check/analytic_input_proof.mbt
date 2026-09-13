///|
struct AnalyticInputProof {
  source : AnalyticAggregateSource
  membership : @capacity.TargetMembership
  input : ReidentifiedStep
  proof : @wire.ProgramProofClaim
}

///|
pub fn analytic_input_proof_source(
  v : AnalyticInputProof,
) -> AnalyticAggregateSource {
  v.source
}

///|
pub fn analytic_input_proof_membership(
  v : AnalyticInputProof,
) -> @capacity.TargetMembership {
  v.membership
}

///|
pub fn analytic_input_proof_input(v : AnalyticInputProof) -> ReidentifiedStep {
  v.input
}

///|
pub fn analytic_input_proof_claim(
  v : AnalyticInputProof,
) -> @wire.ProgramProofClaim {
  v.proof
}

///|
pub fn unit_analytic_input_proof(
  program : CheckedProgram,
  stage : Int,
  step : Int,
  aggregate : Int,
  candidate : Int,
  max_work~ : Int,
  max_bytes~ : Int,
  max_nodes~ : Int,
  max_depth~ : Int,
) -> AnalyticInputProof raise UnitBuildFailure {
  if max_work < 0 || max_bytes < 0 || max_nodes < 0 || max_depth < 0 {
    raise BudgetExceeded
  }
  let budget = IdentityBudget::{
    work: max_work,
    bytes: max_bytes,
    nodes: max_nodes,
    depth: max_depth,
  }
  let (source, limit) = owned_analytic_array_limit(
    program, stage, step, aggregate, budget,
  )
  analytic_input_proof(program.units, source, limit, candidate, budget)
}

///|
fn owned_analytic_array_limit(
  program : CheckedProgram,
  stage : Int,
  step : Int,
  aggregate : Int,
  budget : IdentityBudget,
) -> (AnalyticAggregateSource, @context.GroupArrayLimit) raise UnitBuildFailure {
  guard unit_analytic_aggregate_source_at(program, stage, step, aggregate)
    is Some(source) else {
    raise ForeignOwner
  }
  guard source.call.function is @relation.Aggregate(aggregate) &&
    source.scope == "items" else {
    raise ForeignOwner
  }
  let closure = @context.stage_requirement_operations(requirements(program))
  for index in 0..<@context.operation_closure_count(closure) {
    identity_charge(budget, 1)
    guard @context.operation_closure_at(closure, index)
      is Some(ExecutionCheck(AnalyticExecution(check))) &&
      check.rule is EnforceArrayItems(call, limit) &&
      physical_equal(call, source.call) &&
      check.site.stage == stage &&
      physical_equal(check.site.pipeline, source.operation.pipeline) &&
      check.site.step == step &&
      physical_equal(@context.group_array_limit_call(limit), aggregate) else {
      continue
    }
    return (source, limit)
  }
  raise ForeignOwner
}

///|
// The input remains a rows witness. This separate law application bounds each
// array and retains the exact input membership and its prerequisite graph.
fn analytic_input_proof(
  units : Array[BuiltUnit],
  source : AnalyticAggregateSource,
  limit : @context.GroupArrayLimit,
  candidate : Int,
  budget : IdentityBudget,
) -> AnalyticInputProof raise UnitBuildFailure {
  guard source.call.function is @relation.Aggregate(aggregate) &&
    @context.group_array_limit_input_law(limit) ==
    "actql.bound.analytic-array-input" else {
    raise ForeignOwner
  }
  let remaining = IdentityBudget::{ ..budget, }
  identity_charge(remaining, 1)
  let requirements = @context.operation_resolution_requirements(
    @context.group_array_limit_owner(limit),
  )
  guard @context.operation_requirements_at(
      requirements,
      @context.group_array_limit_requirement(limit),
    )
    is Some(site) &&
    physical_equal(site.pipeline, source.operation.pipeline) &&
    site.step == source.operation.source_ordinal &&
    physical_equal(@context.group_array_limit_call(limit), aggregate) &&
    source.scope == "items" &&
    @context.group_array_limit_candidate_at(limit, candidate)
    is Some(membership) else {
    raise ForeignOwner
  }
  let identity = @context.expression_closure_identity(
    @context.operation_requirements_expressions(requirements),
  )
  guard @context.program_identity_stage_at(identity, site.stage) is Some(stage) &&
    physical_equal(stage, source.operation.stage) else {
    raise ForeignOwner
  }
  let mut found = false
  for unit in units {
    identity_charge(remaining, 1)
    if physical_equal(unit.pipeline, site.pipeline) {
      if found || unit.definition_cid != source.operation.unit_definition_cid {
        raise ForeignOwner
      }
      found = true
    }
  }
  guard found else { raise ForeignOwner }
  let input = reidentify_step_graph(
    units,
    @step_bounds.target_rows_bound(@capacity.target_membership_rows(membership)),
    remaining,
  )
  let subject = analytic_aggregate_subject_with_budget(source, remaining)
  let proof = array_input_claim(
    input, subject, "actql.bound.analytic-array-input", remaining,
  )
  budget.work = remaining.work
  budget.bytes = remaining.bytes
  budget.nodes = remaining.nodes
  { source, membership, input, proof, }
}
