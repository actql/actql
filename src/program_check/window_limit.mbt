///|
struct WindowLimit {
  source : UnitOperationSource
  selected : @context.WindowMembershipLimit
  claim : @wire.LimitClaim
  proofs : Array[WindowInputProof]
}

///|
pub fn window_limit_source(v : WindowLimit) -> UnitOperationSource {
  v.source
}

///|
pub fn window_limit_selection(
  v : WindowLimit,
) -> @context.WindowMembershipLimit {
  v.selected
}

///|
pub fn window_limit_claim(v : WindowLimit) -> @wire.LimitClaim {
  v.claim
}

///|
pub fn window_limit_proof_count(v : WindowLimit) -> Int {
  v.proofs.length()
}

///|
pub fn window_limit_proof_at(v : WindowLimit, index : Int) -> WindowInputProof? {
  v.proofs.get(index)
}

///|
fn assemble_window_limit(
  units : Array[BuiltUnit],
  source : UnitOperationSource,
  selected : @context.WindowMembershipLimit,
  budget : IdentityBudget,
) -> WindowLimit raise UnitBuildFailure {
  let execution = @context.window_membership_bound_execution(selected.bounds)
  guard physical_equal(selected.site.pipeline, source.pipeline) &&
    selected.site.step == source.source_ordinal &&
    @pipeline.step_at(source.pipeline, source.source_ordinal) is Some(step) &&
    physical_equal(step, execution.step) else {
    raise ForeignOwner
  }
  let host = publication_host(selected.host, budget)
  let host_bytes = publication_metadata(
    w => @host.emit(host, w) catch { e => raise Encoding(e) },
    budget,
  )
  identity_charge(budget, host_bytes.length())
  let host_witness = match
    @wire.admit(host_bytes, @host.cid(host), {
      max_bytes: host_bytes.length(),
      max_nodes: host_bytes.length(),
      max_depth: budget.depth,
    }) {
    Ok(v) => v
    Err(e) => raise PublicationWire(e)
  }
  let candidates : Array[(String, @wire.WireWitness)] = [
    (@wire.cid(host_witness), host_witness),
  ]
  let proofs : Array[WindowInputProof] = []
  let inputs : Array[ReidentifiedStep] = []
  let count = @context.window_membership_bound_candidate_count(selected.bounds)
  identity_charge(budget, count)
  for candidate in 0..<count {
    let proof = window_input_proof(units, source, selected, candidate, budget)
    let witness = @wire.program_proof_witness(proof.proof)
    candidates.push((@wire.cid(witness), witness))
    inputs.push(proof.input)
    proofs.push(proof)
  }
  let claim = assemble_aggregate_limit_claim(
    unit_operation_subject(source, budget),
    candidates,
    inputs,
    None,
    Some(selected.maximum),
    selected.maximum,
    "rows",
    budget,
  )
  { source, selected, claim, proofs, }
}

///|
fn prepare_program_window_limits(
  units : Array[BuiltUnit],
  requirements : @context.StageRequirementClosure,
  budget : IdentityBudget,
) -> Array[Array[WindowLimit]] raise UnitBuildFailure {
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
      is Some(ExecutionCheck(WindowMembershipLimit(selected))) else {
      continue
    }
    let site = selected.site
    guard units.get(site.stage) is Some(unit) else { raise ForeignOwner }
    // Imported prerequisite visits keep their producer's Unit identity.
    if !physical_equal(unit.pipeline, site.pipeline) {
      continue
    }
    let key = (site.stage, site.step)
    if seen.contains(key) {
      raise ForeignOwner
    }
    seen[key] = true
    guard unit_operation_source(unit, site.pipeline, site.step) is Some(source) else {
      raise ForeignOwner
    }
    let value = assemble_window_limit(units, source, selected, remaining)
    identity_charge(remaining, 1)
    result[site.stage].push(value)
  }
  budget.work = remaining.work
  budget.bytes = remaining.bytes
  budget.nodes = remaining.nodes
  result
}

///|
pub fn unit_window_limit_count(program : CheckedProgram, stage : Int) -> Int? {
  program.window_limits.get(stage).map(v => v.length())
}

///|
pub fn unit_window_limit_at(
  program : CheckedProgram,
  stage : Int,
  index : Int,
) -> WindowLimit? {
  program.window_limits.get(stage).bind(v => v.get(index))
}
