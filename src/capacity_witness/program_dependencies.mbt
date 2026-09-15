///|
pub(all) enum ProgramDependencyIssue {
  InvalidLimits
  BudgetExceeded
  Arithmetic(ClosureIssue)
  Program(ProgramClosureIssue)
  ConflictingIdentity(String)
  InvalidMinimum(String)
  Extension(ProgramExtensionIssue)
} derive(Eq, Debug)

///|
/// A closed union of admitted bodies, with its exact source collections retained.
/// Sharing a body by CID does not identify its operation applications or owners.
/// This object supplies arithmetic dependencies, not source application coverage.
struct ProgramDependencies {
  claims : ProgramClaims
  sources : Array[ProgramClaims]
  work : Int
}

///|
pub fn collect_program_dependencies(
  sources : Array[ProgramClaims],
  limits : ClosureLimits,
  max_work~ : Int,
) -> Result[ProgramDependencies, ProgramDependencyIssue] {
  if max_work < 0 || limits.max_witnesses < 0 || limits.max_references < 0 {
    return Err(InvalidLimits)
  }
  if sources.length() > max_work / 2 {
    return Err(BudgetExceeded)
  }
  let mut remaining = max_work - sources.length() * 2
  let witnesses : Array[WireWitness] = []
  let proofs : Array[ProgramProofClaim] = []
  let prior_limits : Array[LimitClaim] = []
  let indices : Map[String, Int] = Map([])
  let proof_ids : Map[String, Bool] = Map([])
  let limit_indices : Map[String, Int] = Map([])
  let mut entities = 0
  let mut arithmetic_references = 0
  let mut proof_references = 0
  let mut has_mixed = false
  for source in sources {
    for i, witness in source.claims.witnesses {
      if remaining == 0 {
        return Err(BudgetExceeded)
      }
      remaining -= 1
      if limit_indices.contains(witness.cid) {
        return Err(ConflictingIdentity(witness.cid))
      }
      if !indices.contains(witness.cid) {
        if entities == limits.max_witnesses {
          return Err(BudgetExceeded)
        }
        entities += 1
        let declared = witness.dependencies.length()
        let operands = operand_count(witness.derivation)
        if declared > limits.max_references - arithmetic_references ||
          operands > limits.max_references - arithmetic_references - declared {
          return Err(BudgetExceeded)
        }
        arithmetic_references += declared + operands
        indices[witness.cid] = witnesses.length()
        witnesses.push(witness)
      }
      if source.proofs[i] is Some(proof) && !proof_ids.contains(witness.cid) {
        if entities == limits.max_witnesses {
          return Err(BudgetExceeded)
        }
        entities += 1
        if proof.inputs.length() > limits.max_references - proof_references {
          return Err(BudgetExceeded)
        }
        proof_references += proof.inputs.length()
        proof_ids[witness.cid] = true
        proofs.push(proof)
      }
    }
    if source.mixed is Some(mixed) {
      has_mixed = true
      for limit in mixed.limits {
        if remaining == 0 {
          return Err(BudgetExceeded)
        }
        remaining -= 1
        if indices.contains(limit.identity) {
          return Err(ConflictingIdentity(limit.identity))
        }
        if !limit_indices.contains(limit.identity) {
          if entities == limits.max_witnesses {
            return Err(BudgetExceeded)
          }
          entities += 1
          limit_indices[limit.identity] = prior_limits.length()
          prior_limits.push(limit)
        }
      }
    }
  }
  if witnesses.length() > remaining ||
    arithmetic_references > remaining - witnesses.length() {
    return Err(BudgetExceeded)
  }
  remaining -= witnesses.length() + arithmetic_references
  let arithmetic = match arithmetic_claims(witnesses, limits, true) {
    Ok(value) => value
    Err(issue) => return Err(Arithmetic(issue))
  }
  // Charge the graph traversal even when every body was already admitted. No
  // hashing/admission is repeated: immutable wire cursors are reused below.
  let rebound : Array[LimitClaim] = []
  let mut references = arithmetic.references
  let mut bytes = 0
  let mut nodes = 0
  for prior in prior_limits {
    let count = @arithmetic.minimum_candidate_count(prior.minimum)
    if count > limits.max_references - references || count > remaining / 2 {
      return Err(BudgetExceeded)
    }
    remaining -= count * 2
    references += count
    let candidates : Array[@arithmetic.Candidate] = []
    for i in 0..<count {
      let candidate = @arithmetic.minimum_candidate_at(prior.minimum, i).unwrap()
      let witness = prior.claims.witnesses[candidate.node]
      candidates.push({ node: indices[witness.cid], role: candidate.role, })
    }
    let minimum = match
      @arithmetic.select_candidate_minimum(
        claim_arithmetic(arithmetic),
        candidates,
        @arithmetic.minimum_unit(prior.minimum),
        max_candidates=count,
      ) {
      Ok(value) => value
      Err(_) => return Err(InvalidMinimum(prior.identity))
    }
    if @arithmetic.minimum_value(minimum) !=
      @arithmetic.minimum_value(prior.minimum) ||
      @arithmetic.minimum_guard_binding(minimum) !=
      @arithmetic.minimum_guard_binding(prior.minimum) {
      return Err(InvalidMinimum(prior.identity))
    }
    let span = @decode.cursor_span(prior.cursor)
    let size = span.end_byte - span.start_byte
    if size > 2147483647 - bytes || prior.nodes > 2147483647 - nodes {
      return Err(BudgetExceeded)
    }
    bytes += size
    nodes += prior.nodes
    rebound.push({ ..prior, claims: arithmetic, minimum, })
  }
  let bound : Array[Int?] = []
  for witness in witnesses {
    if remaining == 0 {
      return Err(BudgetExceeded)
    }
    remaining -= 1
    bound.push(
      match witness.derivation {
        EnforcedCeiling(id) => Some(limit_indices[id])
        _ => None
      },
    )
  }
  let mixed = if !has_mixed {
    None
  } else {
    Some(MixedClaims::{
      arithmetic,
      limits: rebound,
      bound,
      references,
      bytes,
      nodes,
    })
  }
  if proof_references > limits.max_references - references ||
    entities > remaining ||
    references > remaining - entities ||
    proof_references > remaining - entities - references {
    return Err(BudgetExceeded)
  }
  remaining -= entities + references + proof_references
  let claims = match program_claims(arithmetic, proofs, limits, mixed) {
    Ok(value) => value
    Err(issue) => return Err(Program(issue))
  }
  Ok({ claims, sources: sources.copy(), work: max_work - remaining, })
}

///|
pub fn program_dependency_claims(v : ProgramDependencies) -> ProgramClaims {
  v.claims
}

///|
pub fn program_dependency_source_count(v : ProgramDependencies) -> Int {
  v.sources.length()
}

///|
pub fn program_dependency_source_at(
  v : ProgramDependencies,
  index : Int,
) -> ProgramClaims? {
  v.sources.get(index)
}

///|
pub fn program_dependency_work(v : ProgramDependencies) -> Int {
  v.work
}
