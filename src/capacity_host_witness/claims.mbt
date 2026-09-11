///|
pub(all) struct BindingLimits {
  max_entries : Int
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
}

///|
pub(all) enum BindingIssue {
  InvalidBindingLimits
  BindingBudgetExceeded
  DuplicatePolicy(String)
  MissingPolicy(Int, String)
  InvalidHostSource(Int, Issue)
} derive(Eq, Debug)

///|
/// Host-source bodies bound within a dependency-checked collection. Other
/// sources, policy selection authority and consumer applicability remain open.
struct HostSources {
  claims : @wire.ProgramClaims
  sources : Array[Witness?]
  count : Int
  bytes : Int
  nodes : Int
}

///|
/// Verify every Host source, including witnesses unused by a selected limit.
/// No policy field, role, law or quantity is trusted independently of its body.
pub fn bind_claim_sources(
  claims : @wire.ProgramClaims,
  policies : Array[@policy.Policy],
  limits : BindingLimits,
) -> Result[HostSources, BindingIssue] {
  if limits.max_entries < 0 ||
    limits.max_bytes < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 {
    return Err(InvalidBindingLimits)
  }
  let arithmetic = @wire.program_claim_arithmetic(claims)
  let n = @wire.claim_count(arithmetic)
  if n > limits.max_entries || policies.length() > limits.max_entries - n {
    return Err(BindingBudgetExceeded)
  }
  let by_cid : Map[String, @policy.Policy] = Map([])
  for policy in policies {
    let cid = @policy.cid(policy)
    if by_cid.contains(cid) {
      return Err(DuplicatePolicy(cid))
    }
    by_cid[cid] = policy
  }
  let sources : Array[Witness?] = []
  let mut count = 0
  let mut bytes = 0
  let mut nodes = 0
  for i in 0..<n {
    let wire = @wire.claim_at(arithmetic, i).unwrap()
    guard @wire.source(wire) is @wire.HostPolicy(_, id) else {
      sources.push(None)
      continue
    }
    guard by_cid.get(id) is Some(policy) else {
      return Err(MissingPolicy(i, id))
    }
    let witness = match
      admit_wire(wire, policy, {
        max_bytes: limits.max_bytes - bytes,
        max_nodes: limits.max_nodes - nodes,
        max_depth: limits.max_depth,
      }) {
      Ok(v) => v
      Err(BudgetExceeded) => return Err(BindingBudgetExceeded)
      Err(e) => return Err(InvalidHostSource(i, e))
    }
    try {
      // Charge full artifacts, including identity members, not just preimages.
      let writer = @encode.hashing_writer(
        limits.max_bytes - bytes,
        limits.max_nodes - nodes,
        limits.max_depth,
      )
      emit(witness, writer)
      let (_, size, length) = @encode.finish_hash_usage(writer)
      bytes += size
      nodes += length
    } catch {
      _ => return Err(BindingBudgetExceeded)
    }
    count += 1
    sources.push(Some(witness))
  }
  Ok({ claims, sources, count, bytes, nodes, })
}

///|
pub fn source_claims(v : HostSources) -> @wire.ProgramClaims {
  v.claims
}

///|
pub fn source_count(v : HostSources) -> Int {
  v.count
}

///|
pub fn source_at(v : HostSources, witness_index : Int) -> Witness? {
  match v.sources.get(witness_index) {
    Some(v) => v
    None => None
  }
}

///|
pub fn source_usage(v : HostSources) -> (Int, Int) {
  (v.bytes, v.nodes)
}
