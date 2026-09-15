///|
struct WindowInputProof {
  source : UnitOperationSource
  membership : @capacity.TargetMembership
  input : ReidentifiedStep
  proof : @wire.ProgramProofClaim
}

///|
/// Read a closed Program's exact window requirement; never accept caller CIDs.
pub fn unit_window_input_proof(
  program : CheckedProgram,
  stage : Int,
  step : Int,
  candidate : Int,
  max_work~ : Int,
  max_bytes~ : Int,
  max_nodes~ : Int,
  max_depth~ : Int,
) -> WindowInputProof raise UnitBuildFailure {
  if max_work < 0 || max_bytes < 0 || max_nodes < 0 || max_depth < 0 {
    raise BudgetExceeded
  }
  let budget = IdentityBudget::{
    work: max_work,
    bytes: max_bytes,
    nodes: max_nodes,
    depth: max_depth,
  }
  guard program.units.get(stage) is Some(unit) &&
    unit_operation_source(unit, unit.pipeline, step) is Some(source) else {
    raise ForeignOwner
  }
  let closure = @context.stage_requirement_operations(requirements(program))
  for i in 0..<@context.operation_closure_count(closure) {
    identity_charge(budget, 1)
    guard @context.operation_closure_at(closure, i)
      is Some(ExecutionCheck(WindowMembershipLimit(limit))) &&
      limit.site.stage == stage &&
      limit.site.step == step &&
      physical_equal(limit.site.pipeline, source.pipeline) else {
      continue
    }
    return window_input_proof(program.units, source, limit, candidate, budget)
  }
  raise ForeignOwner
}

///|
fn window_input_proof(
  units : Array[BuiltUnit],
  source : UnitOperationSource,
  limit : @context.WindowMembershipLimit,
  candidate : Int,
  budget : IdentityBudget,
  conversion? : ProofConversion? = None,
) -> WindowInputProof raise UnitBuildFailure {
  let remaining = IdentityBudget::{ ..budget, }
  identity_charge(remaining, 1)
  let bounds = limit.bounds
  let execution = @context.window_membership_bound_execution(bounds)
  let requirements = @context.operation_resolution_requirements(
    @context.window_membership_bound_owner(bounds),
  )
  guard @context.operation_requirements_at(
      requirements,
      @context.window_membership_bound_requirement(bounds),
    )
    is Some(site) &&
    physical_equal(site, limit.site) &&
    physical_equal(site.pipeline, source.pipeline) &&
    site.step == source.source_ordinal &&
    @pipeline.step_at(source.pipeline, source.source_ordinal) is Some(step) &&
    physical_equal(step, execution.step) &&
    @context.window_membership_bound_candidate_at(bounds, candidate)
    is Some(selected) else {
    raise ForeignOwner
  }
  let identity = @context.expression_closure_identity(
    @context.operation_requirements_expressions(requirements),
  )
  guard @context.program_identity_stage_at(identity, site.stage) is Some(stage) &&
    physical_equal(stage, source.stage) else {
    raise ForeignOwner
  }
  let mut found = false
  for unit in units {
    identity_charge(remaining, 1)
    if physical_equal(unit.pipeline, source.pipeline) {
      if found || unit.definition_cid != source.unit_definition_cid {
        raise ForeignOwner
      }
      found = true
    }
  }
  guard found else { raise ForeignOwner }
  let input = reidentify_step_graph(
    units,
    @step_bounds.target_rows_bound(
      @capacity.target_membership_rows(selected.input),
    ),
    remaining,
    conversion~,
  )
  let proof = window_input_claim(
    input,
    unit_operation_subject(source, remaining),
    @context.window_membership_bound_law(bounds),
    @context.window_membership_bound_options(bounds).maximum_per_input,
    remaining,
  )
  if @wire.value(@wire.program_proof_witness(proof)) != selected.maximum {
    raise ForeignOwner
  }
  budget.work = remaining.work
  budget.bytes = remaining.bytes
  budget.nodes = remaining.nodes
  { source, membership: selected.input, input, proof, }
}

///|
pub fn window_input_proof_source(v : WindowInputProof) -> UnitOperationSource {
  v.source
}

///|
pub fn window_input_proof_membership(
  v : WindowInputProof,
) -> @capacity.TargetMembership {
  v.membership
}

///|
pub fn window_input_proof_input(v : WindowInputProof) -> ReidentifiedStep {
  v.input
}

///|
pub fn window_input_proof_claim(
  v : WindowInputProof,
) -> @wire.ProgramProofClaim {
  v.proof
}
