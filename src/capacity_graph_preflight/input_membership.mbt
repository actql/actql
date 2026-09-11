///|
priv struct InputMembership {
  owners : Map[(Int, Int, Int), Int]
  work : Int
}

///|
fn checked_input_owner(
  applications : Array[ApplicationCoverage],
  visit : Int,
  claim : Int,
  dependency : Int,
) -> GraphInputs? {
  applications
  .get(visit)
  .bind(entry => @program.application_at(entry.sources.program, claim))
  .bind(proof => @program.source_at(proof, dependency))
  .bind(source => {
    match source {
      @program.GraphInput(input) => Some(@input.bound_owner(input))
      _ => None
    }
  })
}

///|
// Proof coordinates have already been bound to actual contextual visits.
// Root coordinates must additionally retain the exact admitted preflight,
// rather than a second local check over equal-looking names or claims.
fn check_input_membership(
  applications : Array[ApplicationCoverage],
  proofs : Map[(Int, Int), Int],
  registrations : Array[(Int, Int, Int, Int)],
  max_work : Int,
) -> Result[InputMembership, ApplicationClosureIssue] {
  if registrations.length() > max_work {
    return Err(ProofWorkLimit)
  }
  let mut work = registrations.length()
  let owners : Map[(Int, Int, Int), Int] = Map([])
  for (visit, claim, dependency, producer) in registrations {
    let key = (visit, claim, dependency)
    guard checked_input_owner(applications, visit, claim, dependency)
      is Some(input) &&
      applications.get(producer) is Some(expected) &&
      proofs.get((visit, claim)) is Some(proof_owner) else {
      return Err(InvalidInputOwner(visit, claim, dependency))
    }
    if owners.contains(key) {
      return Err(DuplicateInputOwner(visit, claim, dependency))
    }
    if physical_equal(input, applications[proof_owner].sources.graph) {
      return Err(UnnecessaryInputOwner(visit, claim, dependency))
    }
    if !physical_equal(input, expected.sources.graph) {
      return Err(ForeignInputOwner(visit, claim, dependency))
    }
    owners[key] = producer
  }
  for visit, entry in applications {
    let count = @wire.claim_count(
      @wire.program_claim_arithmetic(
        @program.application_claims(entry.sources.program),
      ),
    )
    if count > max_work - work {
      return Err(ProofWorkLimit)
    }
    work += count
    for claim in 0..<count {
      guard @program.application_at(entry.sources.program, claim) is Some(proof) else {
        continue
      }
      let n = @program.input_count(proof)
      if n > max_work - work {
        return Err(ProofWorkLimit)
      }
      work += n
      for dependency in 0..<n {
        guard @program.source_at(proof, dependency)
          is Some(@program.GraphInput(input)) else {
          continue
        }
        let owner = @input.bound_owner(input)
        let proof_owner = proofs.get((visit, claim)).unwrap()
        let key = (visit, claim, dependency)
        if physical_equal(owner, applications[proof_owner].sources.graph) {
          owners[key] = proof_owner
        } else if !owners.contains(key) {
          return Err(MissingInputOwner(visit, claim, dependency))
        }
      }
    }
  }
  Ok({ owners, work, })
}
