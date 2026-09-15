///|
pub(all) enum ProgramExtensionIssue {
  InvalidLimits
  BudgetExceeded
  EnforcedProof(Int)
  Arithmetic(ClosureIssue)
  Program(ProgramClosureIssue)
} derive(Eq, Debug)

///|
/// Append ordinary admitted proof bodies to a closed claim collection. Existing
/// witness indices, proof handles, limit handles and enforced-limit bindings
/// remain unchanged. No source or operation application is established here.
/// Limits count the complete resulting graph, not only the appended records.
pub fn extend_program_claims(
  original : ProgramClaims,
  additional : Array[ProgramProofClaim],
  limits : ClosureLimits,
) -> Result[ProgramClaims, ProgramExtensionIssue] {
  if limits.max_witnesses < 0 || limits.max_references < 0 {
    return Err(InvalidLimits)
  }
  let old = original.claims
  let count = old.witnesses.length()
  let limit_count = match original.mixed {
    Some(mixed) => mixed.limits.length()
    None => 0
  }
  if count > limits.max_witnesses ||
    limit_count > limits.max_witnesses - count ||
    additional.length() > (limits.max_witnesses - count - limit_count) / 2 ||
    original.references > limits.max_references {
    return Err(BudgetExceeded)
  }
  let witnesses = old.witnesses.copy()
  let proofs : Array[ProgramProofClaim] = []
  for entry in original.proofs {
    if entry is Some(proof) {
      proofs.push(proof)
    }
  }
  if proofs.length() >
    limits.max_witnesses - count - limit_count - additional.length() * 2 {
    return Err(BudgetExceeded)
  }
  for i, proof in additional {
    if proof.witness.derivation is EnforcedCeiling(_) {
      return Err(EnforcedProof(i))
    }
    witnesses.push(proof.witness)
    proofs.push(proof)
  }
  let arithmetic = match
    arithmetic_claims(witnesses, limits, original.mixed is Some(_)) {
    Ok(value) => value
    Err(issue) => return Err(Arithmetic(issue))
  }
  let mixed = match original.mixed {
    None => None
    Some(prior) => {
      // Old limit candidate coordinates still refer to the unchanged prefix.
      // No new enforced leaves or limit bodies are introduced by this API.
      let limit_references = prior.references - old.references
      if limit_references > limits.max_references - arithmetic.references {
        return Err(BudgetExceeded)
      }
      let bound = prior.bound.copy()
      for _ in additional {
        bound.push(None)
      }
      Some(MixedClaims::{
        arithmetic,
        limits: prior.limits,
        bound,
        references: arithmetic.references + limit_references,
        bytes: prior.bytes,
        nodes: prior.nodes,
      })
    }
  }
  match program_claims(arithmetic, proofs, limits, mixed) {
    Ok(value) => Ok(value)
    Err(issue) => Err(Program(issue))
  }
}
