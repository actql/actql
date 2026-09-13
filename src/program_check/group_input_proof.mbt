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
pub fn unit_group_input_proof(
  program : CheckedProgram,
  stage : Int,
  step : Int,
  aggregate : Int,
  candidate : Int,
  max_work~ : Int,
  max_bytes~ : Int,
  max_nodes~ : Int,
  max_depth~ : Int,
) -> GroupInputProof raise UnitBuildFailure {
  if max_work < 0 || max_bytes < 0 || max_nodes < 0 || max_depth < 0 {
    raise BudgetExceeded
  }
  let budget = IdentityBudget::{
    work: max_work,
    bytes: max_bytes,
    nodes: max_nodes,
    depth: max_depth,
  }
  let (source, limit) = owned_group_array_limit(
    program, stage, step, aggregate, budget,
  )
  group_input_proof(program.units, source, limit, candidate, budget)
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
  )
  let input_witness = @wire.program_proof_witness(input.proof)
  guard @wire.unit(input_witness) is Rows else { raise ForeignOwner }
  let input_cid = @wire.cid(input_witness)
  let value = @wire.value(input_witness)
  let subject = group_aggregate_subject_with_budget(source, remaining)
  let law = @context.group_array_limit_input_law(limit)
  let emit_proof = fn(w : @encode.Writer) -> Unit raise UnitBuildFailure {
    try {
      @encode.begin_object(w)
      @encode.key(w, "inputs")
      @encode.begin_array(w)
      @encode.string_value(w, input_cid)
      @encode.end_array(w)
      @encode.key(w, "law_id")
      @encode.string_value(w, law)
      @encode.key(w, "semantic_ref")
      @encode.string_value(w, subject)
      @encode.key(w, "unit")
      @encode.string_value(w, "array_items")
      @encode.key(w, "value")
      @encode.number_value(w, value.to_double())
      @encode.key(w, "version")
      @encode.string_value(w, "actql-bound-proof/0.1")
      @encode.end_object(w)
    } catch {
      e => raise Encoding(e)
    }
  }
  let hash = identity_writer(remaining)
  emit_proof(hash)
  let proof_cid = identity_finish(remaining, hash)
  let proof_bytes = publication_metadata(emit_proof, remaining)
  let dependencies = [(input_cid, ()), (proof_cid, ())]
  identity_sort(dependencies, remaining)
  let emit = fn(
    w : @encode.Writer,
    cid : String?,
  ) -> Unit raise UnitBuildFailure {
    try {
      @encode.begin_object(w)
      @encode.key(w, "dependencies")
      @encode.begin_array(w)
      for (dependency, _) in dependencies {
        @encode.string_value(w, dependency)
      }
      @encode.end_array(w)
      @encode.key(w, "derivation")
      @encode.begin_object(w)
      @encode.key(w, "op")
      @encode.string_value(w, "source")
      @encode.end_object(w)
      @encode.key(w, "law_id")
      @encode.string_value(w, law)
      @encode.key(w, "role")
      @encode.string_value(w, "proven_upper_bound")
      @encode.key(w, "source")
      @encode.begin_object(w)
      @encode.key(w, "kind")
      @encode.string_value(w, "program")
      @encode.key(w, "proof_cid")
      @encode.string_value(w, proof_cid)
      @encode.key(w, "semantic_ref")
      @encode.string_value(w, subject)
      @encode.end_object(w)
      @encode.key(w, "unit")
      @encode.string_value(w, "array_items")
      @encode.key(w, "value")
      @encode.number_value(w, value.to_double())
      @encode.key(w, "version")
      @encode.string_value(w, "actql-bound-witness/0.1")
      if cid is Some(cid) {
        @encode.key(w, "witness_cid")
        @encode.string_value(w, cid)
      }
      @encode.end_object(w)
    } catch {
      e => raise Encoding(e)
    }
  }
  let hash = identity_writer(remaining)
  emit(hash, None)
  let cid = identity_finish(remaining, hash)
  let bytes = publication_metadata(w => emit(w, Some(cid)), remaining)
  identity_charge(remaining, bytes.length())
  identity_charge(remaining, proof_bytes.length())
  let witness = match
    @wire.admit(bytes, cid, {
      max_bytes: bytes.length(),
      max_nodes: bytes.length(),
      max_depth: remaining.depth,
    }) {
    Ok(v) => v
    Err(e) => raise PublicationWire(e)
  }
  let proof = match
    @wire.bind_program_proof(proof_bytes, witness, {
      max_bytes: proof_bytes.length(),
      max_nodes: proof_bytes.length(),
      max_depth: remaining.depth,
    }) {
    Ok(v) => v
    Err(e) => raise PublicationWire(e)
  }
  budget.work = remaining.work
  budget.bytes = remaining.bytes
  budget.nodes = remaining.nodes
  { source, membership, input, proof, }
}
