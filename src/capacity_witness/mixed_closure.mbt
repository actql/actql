///|
pub(all) struct MixedLimits {
  max_entities : Int
  max_references : Int
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
}

///|
pub(all) enum MixedIssue {
  InvalidMixedLimits
  MixedBudgetExceeded
  MixedArithmetic(ClosureIssue)
  InvalidLimit(Int, Issue)
  DuplicateLimit(String)
  MissingLimit(Int, String)
  InvalidEnforcedClaim(Int)
  CyclicLimitDependencies
} derive(Eq, Debug)

///|
/// Arithmetic and limit dependency consistency, not source or execution proof.
struct MixedClaims {
  arithmetic : ArithmeticClaims
  limits : Array[LimitClaim]
  bound : Array[Int?]
  references : Int
  bytes : Int
  nodes : Int
}

///|
pub fn check_mixed_claims(
  witnesses : Array[WireWitness],
  artifacts : Array[(Bytes, String)],
  limits : MixedLimits,
) -> Result[MixedClaims, MixedIssue] {
  if limits.max_entities < 0 ||
    limits.max_references < 0 ||
    limits.max_bytes < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 {
    return Err(InvalidMixedLimits)
  }
  let n = witnesses.length()
  if n > limits.max_entities || artifacts.length() > limits.max_entities - n {
    return Err(MixedBudgetExceeded)
  }
  let arithmetic = match
    arithmetic_claims(
      witnesses,
      {
        max_witnesses: limits.max_entities,
        max_references: limits.max_references,
      },
      true,
    ) {
    Ok(v) => v
    Err(e) => return Err(MixedArithmetic(e))
  }
  let admitted : Array[LimitClaim] = []
  let index : Map[String, Int] = Map([])
  let mut references = arithmetic.references
  let mut bytes_used = 0
  let mut nodes_used = 0
  for i, (bytes, cid) in artifacts {
    if index.contains(cid) || claim_index(arithmetic, cid) is Some(_) {
      return Err(DuplicateLimit(cid))
    }
    let v = match
      admit_limit(bytes, cid, arithmetic, {
        max_bytes: limits.max_bytes - bytes_used,
        max_nodes: limits.max_nodes - nodes_used,
        max_depth: limits.max_depth,
        max_candidates: limits.max_references - references,
      }) {
      Ok(v) => v
      Err(BudgetExceeded) => return Err(MixedBudgetExceeded)
      Err(e) => return Err(InvalidLimit(i, e))
    }
    bytes_used += bytes.length()
    nodes_used += v.nodes
    references += @arithmetic.minimum_candidate_count(v.minimum)
    index[cid] = i
    admitted.push(v)
  }
  let successors : Array[Array[Int]] = Array::makei(n + admitted.length(), _ => {
    []
  })
  let indegrees = Array::make(n + admitted.length(), 0)
  let bound : Array[Int?] = Array::make(n, None)
  for i, w in arithmetic.witnesses {
    let inputs : Array[Int] = match w.derivation {
      EnforcedCeiling(id) => {
        guard index.get(id) is Some(j) else { return Err(MissingLimit(i, id)) }
        let limit = admitted[j]
        guard w.source is Program(_, proof) &&
          proof == id &&
          w.dependencies.length() == 1 &&
          w.dependencies[0] == id &&
          limit.enforcement == UnitPreflight &&
          @arithmetic.minimum_unit(limit.minimum) == w.unit &&
          @arithmetic.minimum_value(limit.minimum) == w.value else {
          return Err(InvalidEnforcedClaim(i))
        }
        bound[i] = Some(j)
        [n + j]
      }
      _ => {
        let ids = match w.derivation {
          SourceValue | Clamp(None, _) => []
          Preserve(id) | Multiply(id, _) | Clamp(Some(id), _) => [id]
          Minimum(ids) => ids
          Add(a, b) => [a, b]
          EnforcedCeiling(_) => []
        }
        // These references were resolved by arithmetic_claims.
        ids.map(id => claim_index(arithmetic, id).unwrap())
      }
    }
    for input in inputs {
      successors[input].push(i)
      indegrees[i] += 1
    }
  }
  for j, limit in admitted {
    for k in 0..<@arithmetic.minimum_candidate_count(limit.minimum) {
      let input = @arithmetic.minimum_candidate_at(limit.minimum, k).unwrap().node
      successors[input].push(n + j)
      indegrees[n + j] += 1
    }
  }
  if !program_inputs_acyclic(successors, indegrees) {
    return Err(CyclicLimitDependencies)
  }
  Ok({
    arithmetic,
    limits: admitted,
    bound,
    references,
    bytes: bytes_used,
    nodes: nodes_used,
  })
}

///|
pub fn mixed_arithmetic(v : MixedClaims) -> ArithmeticClaims {
  v.arithmetic
}

///|
pub fn mixed_limit_count(v : MixedClaims) -> Int {
  v.limits.length()
}

///|
pub fn mixed_limit_at(v : MixedClaims, index : Int) -> LimitClaim? {
  v.limits.get(index)
}

///|
pub fn mixed_enforced_limit(
  v : MixedClaims,
  witness_index : Int,
) -> LimitClaim? {
  match v.bound.get(witness_index) {
    Some(Some(i)) => Some(v.limits[i])
    _ => None
  }
}

///|
pub fn mixed_usage(v : MixedClaims) -> (Int, Int, Int) {
  (v.references, v.bytes, v.nodes)
}
