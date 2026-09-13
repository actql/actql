///|
struct AnalyticLimit {
  source : AnalyticAggregateSource
  selected : @context.GroupArrayLimit
  claim : @wire.LimitClaim
  proofs : Array[AnalyticInputProof]
}

///|
pub fn analytic_limit_source(v : AnalyticLimit) -> AnalyticAggregateSource {
  v.source
}

///|
pub fn analytic_limit_selection(v : AnalyticLimit) -> @context.GroupArrayLimit {
  v.selected
}

///|
pub fn analytic_limit_claim(v : AnalyticLimit) -> @wire.LimitClaim {
  v.claim
}

///|
pub fn analytic_limit_proof_count(v : AnalyticLimit) -> Int {
  v.proofs.length()
}

///|
pub fn analytic_limit_proof_at(
  v : AnalyticLimit,
  index : Int,
) -> AnalyticInputProof? {
  v.proofs.get(index)
}

///|
/// Reconstruct one owned limit; this is neither runtime enforcement nor a Plan.
pub fn unit_analytic_array_limit(
  program : CheckedProgram,
  stage : Int,
  step : Int,
  aggregate : Int,
  max_work~ : Int,
  max_bytes~ : Int,
  max_nodes~ : Int,
  max_depth~ : Int,
) -> AnalyticLimit raise UnitBuildFailure {
  if max_work < 0 || max_bytes < 0 || max_nodes < 0 || max_depth < 0 {
    raise BudgetExceeded
  }
  let budget = IdentityBudget::{
    work: max_work,
    bytes: max_bytes,
    nodes: max_nodes,
    depth: max_depth,
  }
  let (source, selected) = owned_analytic_array_limit(
    program, stage, step, aggregate, budget,
  )
  assemble_analytic_array_limit(program.units, source, selected, budget)
}

///|
fn assemble_analytic_array_limit(
  units : Array[BuiltUnit],
  source : AnalyticAggregateSource,
  selected : @context.GroupArrayLimit,
  budget : IdentityBudget,
) -> AnalyticLimit raise UnitBuildFailure {
  let max_depth = budget.depth
  let host = publication_host(@context.group_array_limit_host(selected), budget)
  let host_bytes = publication_metadata(
    w => @host.emit(host, w) catch { e => raise Encoding(e) },
    budget,
  )
  identity_charge(budget, host_bytes.length())
  let host_witness = match
    @wire.admit(host_bytes, @host.cid(host), {
      max_bytes: host_bytes.length(),
      max_nodes: host_bytes.length(),
      max_depth,
    }) {
    Ok(v) => v
    Err(e) => raise PublicationWire(e)
  }
  let candidates : Array[(String, @wire.WireWitness)] = [
    (@wire.cid(host_witness), host_witness),
  ]
  let proofs : Array[AnalyticInputProof] = []
  let inputs : Array[ReidentifiedStep] = []
  let count = @context.group_array_limit_candidate_count(selected)
  identity_charge(budget, count)
  let mut non_author = @wire.value(host_witness)
  for candidate in 0..<count {
    let proof = analytic_input_proof(units, source, selected, candidate, budget)
    let witness = @wire.program_proof_witness(proof.proof)
    non_author = Int64::min(non_author, @wire.value(witness))
    candidates.push((@wire.cid(witness), witness))
    inputs.push(proof.input)
    proofs.push(proof)
  }
  let guard_value = @context.group_array_limit_guard(selected)
  if guard_value is Some(value) {
    let witness = emit_aggregate_guard_witness(
      source.operation,
      source.call.name,
      source.scope,
      "analytic.functions",
      value,
      budget,
    )
    candidates.push((@wire.cid(witness), witness))
  }
  let claim = assemble_aggregate_limit_claim(
    analytic_aggregate_subject_with_budget(source, budget),
    candidates,
    inputs,
    guard_value,
    Some(non_author),
    @context.group_array_limit_maximum(selected),
    "array_items",
    budget,
  )
  { source, selected, claim, proofs, }
}
