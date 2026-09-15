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
  origin : SourceOrigin
  dependencies : Array[HostSources]
  local_claims : Int
  local_limits : Int
}

///|
// Identity of the original admitted evidence set, independent of ordinary proof
// extension. Pipeline applicability and selected-policy checks remain separate.
priv struct SourceOrigin {
  claims : @wire.ProgramClaims
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
  Ok({
    claims,
    sources,
    count,
    bytes,
    nodes,
    origin: { claims, },
    dependencies: [],
    local_claims: n,
    local_limits: match @wire.program_claim_mixed(claims) {
      Some(mixed) => @wire.mixed_limit_count(mixed)
      None => 0
    },
  })
}

///|
pub fn source_dependency_count(v : HostSources) -> Int {
  v.dependencies.length()
}

///|
pub fn source_dependency_at(v : HostSources, index : Int) -> HostSources? {
  v.dependencies.get(index)
}

///|
/// Whether an enforced witness lies in the original local source prefix.
/// Ordinary generated proofs have separate operation application ownership.
pub fn source_enforcement_is_local(v : HostSources, index : Int) -> Bool {
  index >= 0 && index < v.local_claims
}

///|
pub fn source_local_limit_count(v : HostSources) -> Int {
  v.local_limits
}

///|
/// Exact source admission shared by ordinary proof extensions. This is not
/// equality of the current claim tables, pipeline ownership, or policy choice.
pub fn same_source_origin(left : HostSources, right : HostSources) -> Bool {
  physical_equal(left.origin, right.origin)
}

///|
/// Original closed evidence collection; generated ordinary proofs do not alter it.
pub fn source_origin_claims(v : HostSources) -> @wire.ProgramClaims {
  v.origin.claims
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
