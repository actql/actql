///|
pub(all) enum ProgramClosureIssue {
  InvalidProgramLimits
  ProgramBudgetExceeded
  ForeignProgramProof(Int)
  DuplicateProgramProof(Int)
  MissingProgramProof(Int)
  MissingProgramInput(Int, String)
  ProgramOperandMismatch(Int)
  CyclicProgramInputs
} derive(Eq, Debug)

///|
/// Proof bodies and arithmetic claims with all Program input edges resolved.
/// External sources and semantic law application are still unvalidated.
struct ProgramClaims {
  claims : ArithmeticClaims
  proofs : Array[ProgramProofClaim?]
  references : Int
}

///|
fn proof_operands_match(proof : ProgramProofClaim) -> Bool {
  let inputs = proof.inputs
  match proof.witness.derivation {
    // Source proofs may depend on other witnesses without encoding arithmetic.
    SourceValue => true
    EnforcedCeiling(_) => false
    Preserve(id) | Multiply(id, _) | Clamp(Some(id), _) =>
      inputs.length() == 1 && inputs[0] == id
    Clamp(None, _) => inputs.is_empty()
    Add(left, right) =>
      inputs.length() == 2 &&
      (if left <= right {
        inputs[0] == left && inputs[1] == right
      } else {
        inputs[0] == right && inputs[1] == left
      })
    Minimum(ids) => {
      // The proof preserves repeated occurrences; min's wire operands are a set.
      let mut next = 0
      let mut previous = ""
      for id in inputs {
        if id != previous {
          if next >= ids.length() || ids[next] != id {
            return false
          }
          next = next + 1
          previous = id
        }
      }
      next == ids.length()
    }
  }
}

///|
/// Link every Program proof to this arithmetic collection, including unused
/// claims. max_witnesses counts claims plus proof bodies; max_references counts
/// the arithmetic collection's charged references plus proof input occurrences.
pub fn check_program_claims(
  claims : ArithmeticClaims,
  proofs : Array[ProgramProofClaim],
  limits : ClosureLimits,
) -> Result[ProgramClaims, ProgramClosureIssue] {
  if limits.max_witnesses < 0 || limits.max_references < 0 {
    return Err(InvalidProgramLimits)
  }
  let n = claims.witnesses.length()
  if n > limits.max_witnesses || proofs.length() > limits.max_witnesses - n {
    return Err(ProgramBudgetExceeded)
  }
  let mut references = claims.references
  if references > limits.max_references {
    return Err(ProgramBudgetExceeded)
  }
  for proof in proofs {
    if proof.inputs.length() > limits.max_references - references {
      return Err(ProgramBudgetExceeded)
    }
    references = references + proof.inputs.length()
  }
  let indexed : Array[ProgramProofClaim?] = Array::make(n, None)
  for i, proof in proofs {
    guard claim_index(claims, proof.witness.cid) is Some(index) else {
      return Err(ForeignProgramProof(i))
    }
    if indexed[index] is Some(_) {
      return Err(DuplicateProgramProof(i))
    }
    indexed[index] = Some(proof)
  }
  let successors : Array[Array[Int]] = Array::makei(n, _ => [])
  let indegrees = Array::make(n, 0)
  for i, witness in claims.witnesses {
    if witness.source is Program(_, _) {
      guard indexed[i] is Some(proof) else {
        return Err(MissingProgramProof(i))
      }
      if !proof_operands_match(proof) {
        return Err(ProgramOperandMismatch(i))
      }
      for id in proof.inputs {
        guard claim_index(claims, id) is Some(input) else {
          return Err(MissingProgramInput(i, id))
        }
        successors[input].push(i)
        indegrees[i] = indegrees[i] + 1
      }
    } else {
      // Non-Program arithmetic dependencies still participate in the union
      // graph. Their external source validation belongs to its own owner.
      let operands : Array[String] = match witness.derivation {
        SourceValue | Clamp(None, _) => []
        Preserve(id) | Multiply(id, _) | Clamp(Some(id), _) => [id]
        Add(a, b) => [a, b]
        Minimum(ids) => ids
        EnforcedCeiling(id) => [id]
      }
      for id in operands {
        guard claim_index(claims, id) is Some(input) else {
          return Err(MissingProgramInput(i, id))
        }
        successors[input].push(i)
        indegrees[i] = indegrees[i] + 1
      }
    }
  }
  if !program_inputs_acyclic(successors, indegrees) {
    return Err(CyclicProgramInputs)
  }
  Ok({ claims, proofs: indexed, references, })
}

///|
fn program_inputs_acyclic(
  successors : Array[Array[Int]],
  indegrees : Array[Int],
) -> Bool {
  let ready : Array[Int] = []
  for i, degree in indegrees {
    if degree == 0 {
      ready.push(i)
    }
  }
  let mut head = 0
  while head < ready.length() {
    let i = ready[head]
    head = head + 1
    for dependent in successors[i] {
      indegrees[dependent] = indegrees[dependent] - 1
      if indegrees[dependent] == 0 {
        ready.push(dependent)
      }
    }
  }
  head == indegrees.length()
}

///|
pub fn program_claim_arithmetic(claims : ProgramClaims) -> ArithmeticClaims {
  claims.claims
}

///|
/// Indexed in arithmetic claim order, not the supplied proof-array order.
pub fn program_claim_proof_at(
  claims : ProgramClaims,
  index : Int,
) -> ProgramProofClaim? {
  match claims.proofs.get(index) {
    Some(proof) => proof
    None => None
  }
}

///|
pub fn program_claim_reference_count(claims : ProgramClaims) -> Int {
  claims.references
}
