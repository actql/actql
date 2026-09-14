///|
// Shared conversion mechanics; callers validate the operation-specific owner and
// supply its normative scope mapping. No candidate is selected or discarded here.
fn assemble_operation_capacity_limits(
  units : Array[BuiltUnit],
  applications : @step_bounds.Applications,
  subject : String,
  scopes : Array[(@wire.LimitClaim, String, String)],
  budget : IdentityBudget,
) -> (Array[@wire.LimitClaim], Array[ReidentifiedStep]) raise UnitBuildFailure {
  let arithmetic = @wire.program_claim_arithmetic(
    @step_bounds.application_claims(applications),
  )
  let proofs : Array[ReidentifiedStep] = []
  let converted : Map[Int, ReidentifiedStep] = Map([])
  let limits : Array[@wire.LimitClaim] = []
  for (original, suffix, unit) in scopes {
    if !physical_equal(@wire.limit_claims(original), arithmetic) {
      raise ForeignOwner
    }
    let minimum = @wire.limit_minimum(original)
    let count = @derivation.minimum_candidate_count(minimum)
    identity_charge(budget, count)
    let candidates : Array[(String, @wire.WireWitness)] = []
    for index in 0..<count {
      let node = @derivation.minimum_candidate_at(minimum, index).unwrap().node
      let original_witness = @wire.claim_at(arithmetic, node).unwrap()
      let witness = match @wire.source(original_witness) {
        Program(_, _) => {
          guard @step_bounds.application_at(applications, node) is Some(bound) &&
            physical_equal(
              @wire.program_proof_witness(@step_bounds.checked_proof(bound)),
              original_witness,
            ) else {
            raise ForeignOwner
          }
          let proof = match converted.get(node) {
            Some(v) => v
            None => {
              let value = reidentify_step_graph(units, bound, budget)
              converted[node] = value
              proofs.push(value)
              value
            }
          }
          @wire.program_proof_witness(proof.proof)
        }
        HostPolicy(_, _) => original_witness
        _ => raise UnconvertedProofInput
      }
      candidates.push((@wire.cid(witness), witness))
    }
    let maximum = @derivation.minimum_value(minimum)
    limits.push(
      assemble_aggregate_limit_claim(
        subject + suffix,
        candidates,
        proofs,
        None,
        Some(maximum),
        maximum,
        unit,
        budget,
        preserve_candidate_occurrences=true,
      ),
    )
  }
  (limits, proofs)
}
