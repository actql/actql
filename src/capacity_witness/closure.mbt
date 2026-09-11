///|
pub(all) struct ClosureLimits {
  max_witnesses : Int
  max_references : Int
}

///|
pub(all) enum ClosureIssue {
  InvalidClosureLimits
  ClosureBudgetExceeded
  UnresolvedEnforcement(Int, String)
  InvalidArithmetic(@arithmetic.ReferenceIssue)
} derive(Eq, Debug)

///|
/// Canonical claims with a complete checked arithmetic graph. External sources,
/// governing law applications and exact dependency sets still need validation.
struct ArithmeticClaims {
  witnesses : Array[WireWitness]
  graph : @arithmetic.LinkedArithmetic
  references : Int
}

///|
fn operand_count(d : Derivation) -> Int {
  match d {
    SourceValue | Clamp(None, _) => 0
    Preserve(_) | Multiply(_, _) | Clamp(Some(_), _) | EnforcedCeiling(_) => 1
    Add(_, _) => 2
    Minimum(ids) => ids.length()
  }
}

///|
/// Check every supplied claim, not only a consumer's selected candidates.
/// Reference budget counts declared dependencies plus operand occurrences.
/// No externally enforced ceiling is silently converted into a numeric leaf.
pub fn check_arithmetic_claims(
  witnesses : Array[WireWitness],
  limits : ClosureLimits,
) -> Result[ArithmeticClaims, ClosureIssue] {
  arithmetic_claims(witnesses, limits, false)
}

///|
// The mixed-closure owner may provisionally defer enforced leaves, but must
// bind their limits and check union cycles before exposing any result.
fn arithmetic_claims(
  witnesses : Array[WireWitness],
  limits : ClosureLimits,
  defer_enforcement : Bool,
) -> Result[ArithmeticClaims, ClosureIssue] {
  if limits.max_witnesses < 0 || limits.max_references < 0 {
    return Err(InvalidClosureLimits)
  }
  if witnesses.length() > limits.max_witnesses {
    return Err(ClosureBudgetExceeded)
  }
  let mut references = 0
  for w in witnesses {
    let declared = w.dependencies.length()
    if declared > limits.max_references - references {
      return Err(ClosureBudgetExceeded)
    }
    references = references + declared
    let operands = operand_count(w.derivation)
    if operands > limits.max_references - references {
      return Err(ClosureBudgetExceeded)
    }
    references = references + operands
  }
  let nodes : Array[@arithmetic.ReferencedNode] = []
  for i = 0; i < witnesses.length(); i = i + 1 {
    let w = witnesses[i]
    let derivation = match w.derivation {
      SourceValue => @arithmetic.Source
      Preserve(id) => @arithmetic.PreserveReference(id)
      Minimum(ids) => @arithmetic.MinimumReferences(ids)
      Add(left, right) => @arithmetic.AddReferences(left, right)
      Multiply(id, factor) => @arithmetic.MultiplyReference(id, factor)
      Clamp(input, maximum) => @arithmetic.ClampReference(input, maximum)
      EnforcedCeiling(id) =>
        if defer_enforcement {
          @arithmetic.Source
        } else {
          return Err(UnresolvedEnforcement(i, id))
        }
    }
    nodes.push({ cid: w.cid, unit: w.unit, claimed: w.value, derivation, })
  }
  match
    @arithmetic.link_references(nodes, {
      max_nodes: limits.max_witnesses,
      max_edges: limits.max_references,
    }) {
    Ok(graph) => Ok({ witnesses: witnesses.copy(), graph, references, })
    Err(issue) => Err(InvalidArithmetic(issue))
  }
}

///|
pub fn claim_count(claims : ArithmeticClaims) -> Int {
  claims.witnesses.length()
}

///|
pub fn claim_at(claims : ArithmeticClaims, index : Int) -> WireWitness? {
  claims.witnesses.get(index)
}

///|
pub fn claim_index(claims : ArithmeticClaims, identity : String) -> Int? {
  if !valid_cid(identity) {
    return None
  }
  @arithmetic.linked_index(claims.graph, identity)
}

///|
pub fn claim_arithmetic(
  claims : ArithmeticClaims,
) -> @arithmetic.CheckedArithmetic {
  @arithmetic.linked_arithmetic(claims.graph)
}

///|
pub fn claim_reference_count(claims : ArithmeticClaims) -> Int {
  claims.references
}
