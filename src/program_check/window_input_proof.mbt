///|
struct WindowInputProof {
  source : UnitOperationSource
  membership : @capacity.TargetMembership
  input : ReidentifiedStep
  proof : @wire.ProgramProofClaim
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
