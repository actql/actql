///|
fn publication_proofs(
  units : Array[BuiltUnit],
  selected : @context.PublicationRowLimit,
  budget : IdentityBudget,
) -> Array[ReidentifiedStep] raise UnitBuildFailure {
  let count = @context.publication_row_limit_program_count(selected)
  identity_charge(budget, count)
  let proofs : Array[ReidentifiedStep] = []
  for i in 0..<count {
    let candidate = @context.publication_row_limit_program_at(selected, i).unwrap()
    let bound = @step_bounds.target_rows_bound(
      @capacity.target_membership_rows(candidate.membership),
    )
    proofs.push(reidentify_step_graph(units, bound, budget))
  }
  proofs
}

///|
fn publication_proof_claims(
  proofs : Array[ReidentifiedStep],
  budget : IdentityBudget,
  limits? : Array[(Bytes, String)] = [],
) -> Array[@wire.WireWitness] raise UnitBuildFailure {
  identity_charge(budget, proofs.length())
  let pending = proofs.copy()
  let seen : Map[String, Bool] = Map([])
  let claims : Array[@wire.WireWitness] = []
  let seen_limits : Map[String, Bool] = Map([])
  while pending.pop() is Some(proof) {
    let witness = @wire.program_proof_witness(proof.proof)
    let cid = @wire.cid(witness)
    identity_charge(budget, cid.length())
    if seen.contains(cid) {
      continue
    }
    seen[cid] = true
    identity_charge(budget, 1)
    claims.push(witness)
    identity_charge(budget, proof.external_inputs.length())
    for dependency in proof.external_inputs {
      let key = @wire.cid(dependency)
      identity_charge(budget, key.length())
      if !seen.contains(key) {
        seen[key] = true
        claims.push(dependency)
      }
    }
    identity_charge(budget, proof.graph_inputs.length())
    for input in proof.graph_inputs {
      let limit_cid = @wire.limit_cid(input.limit)
      identity_charge(budget, limit_cid.length())
      if !seen_limits.contains(limit_cid) {
        seen_limits[limit_cid] = true
        limits.push((input.limit_bytes, limit_cid))
      }
      let context = @wire.mixed_arithmetic(input.claims)
      identity_charge(budget, @wire.claim_count(context))
      for i in 0..<@wire.claim_count(context) {
        let dependency = @wire.claim_at(context, i).unwrap()
        let key = @wire.cid(dependency)
        identity_charge(budget, key.length())
        if !seen.contains(key) {
          seen[key] = true
          claims.push(dependency)
        }
      }
    }
    identity_charge(budget, proof.inputs.length())
    for input in proof.inputs {
      pending.push(input)
    }
  }
  claims
}
