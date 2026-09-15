///|
struct GroupInputProof {
  source : GroupAggregateSource
  membership : @capacity.TargetMembership
  input : ReidentifiedStep
  proof : @wire.ProgramProofClaim
}

///|
pub fn group_input_proof_source(v : GroupInputProof) -> GroupAggregateSource {
  v.source
}

///|
pub fn group_input_proof_membership(
  v : GroupInputProof,
) -> @capacity.TargetMembership {
  v.membership
}

///|
pub fn group_input_proof_input(v : GroupInputProof) -> ReidentifiedStep {
  v.input
}

///|
pub fn group_input_proof_claim(v : GroupInputProof) -> @wire.ProgramProofClaim {
  v.proof
}

///|
fn owned_group_array_limit(
  program : CheckedProgram,
  stage : Int,
  step : Int,
  aggregate : Int,
  budget : IdentityBudget,
) -> (GroupAggregateSource, @context.GroupArrayLimit) raise UnitBuildFailure {
  guard unit_group_aggregate_source_at(program, stage, step, aggregate)
    is Some(source) else {
    raise ForeignOwner
  }
  let closure = @context.stage_requirement_operations(requirements(program))
  for index in 0..<@context.operation_closure_count(closure) {
    identity_charge(budget, 1)
    guard @context.operation_closure_at(closure, index)
      is Some(ExecutionCheck(GroupExecution(check))) &&
      check.rule is EnforceArrayItems(limit) &&
      check.site.stage == stage &&
      physical_equal(check.site.pipeline, source.operation.pipeline) &&
      check.site.step == step &&
      physical_equal(@context.group_array_limit_call(limit), source.call) else {
      continue
    }
    return (source, limit)
  }
  raise ForeignOwner
}

///|
// The input remains a rows witness. This separate law application bounds each
// array and retains the exact input membership and its prerequisite graph.
fn group_input_proof(
  units : Array[BuiltUnit],
  source : GroupAggregateSource,
  limit : @context.GroupArrayLimit,
  candidate : Int,
  budget : IdentityBudget,
  conversion? : ProofConversion? = None,
) -> GroupInputProof raise UnitBuildFailure {
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
    physical_equal(@context.group_array_limit_call(limit), source.call) &&
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
    conversion~,
  )
  let subject = group_aggregate_subject_with_budget(source, remaining)
  let proof = array_input_claim(
    input,
    subject,
    @context.group_array_limit_input_law(limit),
    remaining,
  )
  budget.work = remaining.work
  budget.bytes = remaining.bytes
  budget.nodes = remaining.nodes
  { source, membership, input, proof, }
}
