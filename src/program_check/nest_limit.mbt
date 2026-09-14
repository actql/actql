///|
pub struct NestInputProof {
  membership : @capacity.TargetMembership
  input : ReidentifiedStep
  proof : @wire.ProgramProofClaim
}

///|
/// An applicable parent-row prerequisite, not an observed expansion count.
pub struct NestParentInput {
  membership : @capacity.TargetMembership
  input : ReidentifiedStep
}

///|
struct NestLimits {
  source : NestResourceSource
  envelope : @context.NestValueEnvelope
  claims : Array[@wire.LimitClaim]
  proofs : Array[NestInputProof]
  parents : Array[NestParentInput]
  empty : @wire.ProgramProofClaim
}

///|
pub fn nest_limits_source(v : NestLimits) -> NestResourceSource {
  v.source
}

///|
pub fn nest_limits_envelope(v : NestLimits) -> @context.NestValueEnvelope {
  v.envelope
}

///|
pub fn nest_limits_claim(
  v : NestLimits,
  scope : NestResourceScope,
) -> @wire.LimitClaim {
  v.claims[match scope {
    ChildItems => 0
    EmptyItems => 1
    GroupedBytes => 2
    AttachedBytes => 3
  }]
}

///|
pub fn nest_limits_input_count(v : NestLimits) -> Int {
  v.proofs.length()
}

///|
pub fn nest_limits_input_at(v : NestLimits, index : Int) -> NestInputProof? {
  v.proofs.get(index)
}

///|
pub fn nest_limits_empty_proof(v : NestLimits) -> @wire.ProgramProofClaim {
  v.empty
}

///|
pub fn nest_limits_parent_count(v : NestLimits) -> Int {
  v.parents.length()
}

///|
pub fn nest_limits_parent_at(v : NestLimits, index : Int) -> NestParentInput? {
  v.parents.get(index)
}

///|
fn nest_host_witness(
  ceiling : @policy.Ceiling,
  budget : IdentityBudget,
) -> @wire.WireWitness raise UnitBuildFailure {
  let host = publication_host(ceiling, budget)
  let bytes = publication_metadata(
    w => @host.emit(host, w) catch { e => raise Encoding(e) },
    budget,
  )
  identity_charge(budget, bytes.length())
  match
    @wire.admit(bytes, @host.cid(host), {
      max_bytes: bytes.length(),
      max_nodes: bytes.length(),
      max_depth: budget.depth,
    }) {
    Ok(v) => v
    Err(e) => raise PublicationWire(e)
  }
}

///|
fn assemble_nest_limits(
  units : Array[BuiltUnit],
  source : NestResourceSource,
  envelope : @context.NestValueEnvelope,
  budget : IdentityBudget,
) -> NestLimits raise UnitBuildFailure {
  let selected = envelope.items
  // Validates the exact owner even when no authored restriction exists.
  let guard_witness = emit_nest_guard_witness(source, selected, budget)
  let subject = nest_resource_subject_with_budget(source, ChildItems, budget)
  let host = nest_host_witness(selected.host, budget)
  let candidates = [(@wire.cid(host), host)]
  let inputs : Array[ReidentifiedStep] = []
  let proofs : Array[NestInputProof] = []
  let count = @context.nest_item_candidate_count(selected)
  identity_charge(budget, count)
  let mut non_author = @wire.value(host)
  for index in 0..<count {
    let membership = @context.nest_item_candidate_at(selected, index).unwrap()
    let input = reidentify_step_graph(
      units,
      @step_bounds.target_rows_bound(
        @capacity.target_membership_rows(membership),
      ),
      budget,
    )
    let proof = array_input_claim(
      input, subject, "actql.bound.array-aggregate-input", budget,
    )
    let witness = @wire.program_proof_witness(proof)
    non_author = Int64::min(non_author, @wire.value(witness))
    candidates.push((@wire.cid(witness), witness))
    inputs.push(input)
    proofs.push({ membership, input, proof, })
  }
  if guard_witness is Some(witness) {
    candidates.push((@wire.cid(witness), witness))
  }
  let items = assemble_aggregate_limit_claim(
    subject,
    candidates,
    inputs,
    selected.guard_value,
    Some(non_author),
    selected.maximum,
    "array_items",
    budget,
  )
  let empty_subject = nest_resource_subject_with_budget(
    source,
    EmptyItems,
    budget,
  )
  let empty = emit_source_bound_claim(
    None,
    empty_subject,
    "actql.bound.nest-empty-array",
    "array_items",
    1L,
    None,
    budget,
  )
  let witness = @wire.program_proof_witness(empty)
  let empty_limit = assemble_aggregate_limit_claim(
    empty_subject,
    [(@wire.cid(witness), witness)],
    [],
    None,
    Some(1L),
    1L,
    "array_items",
    budget,
  )
  // One immutable Host witness may occur in two distinct enforcement claims.
  // It is not an observation, and equal ceilings do not collapse the sites.
  let bytes = nest_host_witness(envelope.byte_ceiling, budget)
  let claims = [items, empty_limit]
  for scope in [GroupedBytes, AttachedBytes] {
    claims.push(
      assemble_aggregate_limit_claim(
        nest_resource_subject_with_budget(source, scope, budget),
        [(@wire.cid(bytes), bytes)],
        [],
        None,
        Some(@wire.value(bytes)),
        @wire.value(bytes),
        "bytes",
        budget,
      ),
    )
  }
  let count = @context.nest_parent_candidate_count(envelope)
  identity_charge(budget, count)
  let parents : Array[NestParentInput] = []
  for index in 0..<count {
    let membership = @context.nest_parent_candidate_at(envelope, index).unwrap()
    let input = reidentify_step_graph(
      units,
      @step_bounds.target_rows_bound(
        @capacity.target_membership_rows(membership),
      ),
      budget,
    )
    parents.push({ membership, input, })
  }
  { source, envelope, claims, proofs, parents, empty, }
}

///|
fn prepare_program_nest_limits(
  units : Array[BuiltUnit],
  requirements : @context.StageRequirementClosure,
  budget : IdentityBudget,
) -> Array[Array[NestLimits]] raise UnitBuildFailure {
  let remaining = IdentityBudget::{ ..budget, }
  identity_charge(remaining, units.length())
  let result = Array::makei(units.length(), _ => [])
  let closure = @context.stage_requirement_operations(requirements)
  let seen : Map[(Int, Int), Bool] = Map([])
  for index in 0..<@context.operation_closure_count(closure) {
    identity_charge(remaining, 1)
    guard @context.operation_closure_at(closure, index)
      is Some(ExecutionCheck(NestValues(check))) else {
      continue
    }
    guard units.get(check.site.stage) is Some(unit) else { raise ForeignOwner }
    if !physical_equal(unit.pipeline, check.site.pipeline) {
      continue
    }
    let key = (check.site.stage, check.site.step)
    if seen.contains(key) {
      raise ForeignOwner
    }
    seen[key] = true
    guard unit_nest_resource_source(unit, check.site.pipeline, check.site.step)
      is Some(source) else {
      raise ForeignOwner
    }
    let value = assemble_nest_limits(units, source, check.envelope, remaining)
    identity_charge(remaining, 1)
    result[check.site.stage].push(value)
  }
  budget.work = remaining.work
  budget.bytes = remaining.bytes
  budget.nodes = remaining.nodes
  result
}

///|
pub fn unit_nest_limit_count(program : CheckedProgram, stage : Int) -> Int? {
  program.nest_limits.get(stage).map(v => v.length())
}

///|
pub fn unit_nest_limit_at(
  program : CheckedProgram,
  stage : Int,
  index : Int,
) -> NestLimits? {
  program.nest_limits.get(stage).bind(v => v.get(index))
}
