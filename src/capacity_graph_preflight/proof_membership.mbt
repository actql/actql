///|
priv struct ProofMembership {
  owners : Map[(Int, Int), Int]
  work : Int
}

///|
// Coordinates select a candidate owner, never establish ownership by themselves.
// Explicit coordinates are needed only for nonlocal proof applications.
fn check_proof_membership(
  orders : @pipeline.ContextualClosure,
  applications : Array[ApplicationCoverage],
  guards : @pipeline.BoundGuardClosure,
  registrations : Array[(Int, Int, Int)],
  max_work : Int,
) -> Result[ProofMembership, ApplicationClosureIssue] {
  if registrations.length() > max_work {
    return Err(ProofWorkLimit)
  }
  let mut work = registrations.length()
  let owners : Map[(Int, Int), Int] = Map([])
  for (visit, claim, producer) in registrations {
    guard applications.get(visit) is Some(entry) &&
      @program.application_at(entry.sources.program, claim) is Some(proof) &&
      @pipeline.contextual_closure_at(orders, producer) is Some(context) else {
      return Err(InvalidProofOwner(visit, claim))
    }
    if owners.contains((visit, claim)) {
      return Err(DuplicateProofOwner(visit, claim))
    }
    if physical_equal(
        @program.checked_pipeline(proof),
        entry.sources.graph.pipeline,
      ) {
      return Err(UnnecessaryProofOwner(visit, claim))
    }
    if !physical_equal(
        @program.checked_pipeline(proof),
        @pipeline.contextual_orders_pipeline(context),
      ) {
      return Err(ForeignProofOwner(visit, claim))
    }
    owners[(visit, claim)] = producer
  }
  for visit, entry in applications {
    let claims = @program.application_claims(entry.sources.program)
    let count = @wire.claim_count(@wire.program_claim_arithmetic(claims))
    if count > max_work - work {
      return Err(ProofWorkLimit)
    }
    work += count
    for claim in 0..<count {
      if @program.application_at(entry.sources.program, claim) is Some(proof) {
        let producer = if physical_equal(
            @program.checked_pipeline(proof),
            entry.sources.graph.pipeline,
          ) {
          visit
        } else {
          match owners.get((visit, claim)) {
            Some(i) => i
            None => return Err(MissingProofOwner(visit, claim))
          }
        }
        if @program.checked_bindings(proof) is Some(binding) {
          let context = @pipeline.bound_guard_closure_at(guards, producer).unwrap()
          guard @pipeline.bound_guard_bindings(context) is Some(values) &&
            physical_equal(values, @program.parameter_values(binding)) else {
            return Err(ProofBindingMismatch(visit, claim))
          }
        }
        owners[(visit, claim)] = producer
      }
    }
  }
  Ok({ owners, work, })
}
