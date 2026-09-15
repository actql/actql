///|
/// Extend arithmetic dependencies without interpreting foreign limits as local
/// source requirements. An application closure must register the exact producers.
pub fn extend_source_dependencies(
  original : HostSources,
  dependencies : Array[HostSources],
  additional : Array[@wire.ProgramProofClaim],
  limits : @wire.ClosureLimits,
  max_work~ : Int,
) -> Result[(HostSources, Int), @wire.ProgramDependencyIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  let mut remaining = max_work
  if dependencies.length() > remaining / 2 ||
    remaining - dependencies.length() * 2 < 1 {
    return Err(BudgetExceeded)
  }
  remaining -= dependencies.length() * 2 + 1
  let origins = [original.claims]
  for dependency in dependencies {
    origins.push(dependency.claims)
  }
  let joined = match
    @wire.collect_program_dependencies(origins, limits, max_work=remaining) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  remaining -= @wire.program_dependency_work(joined)
  let base = @wire.program_dependency_claims(joined)
  let arithmetic = @wire.program_claim_arithmetic(base)
  let added : Array[@wire.ProgramProofClaim] = []
  if additional.length() > remaining {
    return Err(BudgetExceeded)
  }
  remaining -= additional.length()
  for proof in additional {
    let cid = @wire.cid(@wire.program_proof_witness(proof))
    if @wire.claim_index(arithmetic, cid) is None {
      added.push(proof)
    }
  }
  // Existing extension reserves the full graph. The dependency constructor's
  // work limit also bounds this pass, including every retained input reference.
  let mut cost = @wire.claim_count(arithmetic)
  if cost > remaining {
    return Err(BudgetExceeded)
  }
  remaining -= cost
  if cost > remaining {
    return Err(BudgetExceeded)
  }
  remaining -= cost
  for index in 0..<cost {
    if @wire.program_claim_proof_at(base, index) is Some(_) {
      if remaining == 0 {
        return Err(BudgetExceeded)
      }
      remaining -= 1
    }
  }
  let limit_count = match @wire.program_claim_mixed(base) {
    Some(mixed) => @wire.mixed_limit_count(mixed)
    None => 0
  }
  if limit_count > remaining {
    return Err(BudgetExceeded)
  }
  remaining -= limit_count
  cost = @wire.program_claim_reference_count(base)
  if cost > remaining {
    return Err(BudgetExceeded)
  }
  remaining -= cost
  for proof in added {
    let witness = @wire.program_proof_witness(proof)
    for
      amount in [
        2,
        @wire.dependency_count(witness),
        @wire.witness_operand_count(witness),
        @wire.program_proof_input_count(proof),
      ] {
      if amount > remaining {
        return Err(BudgetExceeded)
      }
      remaining -= amount
    }
  }
  let claims = match @wire.extend_program_claims(base, added, limits) {
    Ok(value) => value
    Err(issue) => return Err(Extension(issue))
  }
  let count = @wire.claim_count(@wire.program_claim_arithmetic(claims))
  if count > remaining {
    return Err(BudgetExceeded)
  }
  remaining -= count
  let sources : Array[Witness?] = Array::make(count, None)
  let all = [original]
  all.append(dependencies)
  let mut host_count = 0
  for source in all {
    if source.sources.length() > remaining {
      return Err(BudgetExceeded)
    }
    remaining -= source.sources.length()
    for witness in source.sources {
      if witness is Some(witness) {
        let index = @wire.claim_index(arithmetic, cid(witness)).unwrap()
        if sources[index] is None {
          sources[index] = Some(witness)
          host_count += 1
        }
      }
    }
  }
  if original.dependencies.length() > remaining {
    return Err(BudgetExceeded)
  }
  remaining -= original.dependencies.length()
  let retained = original.dependencies.copy()
  retained.append(dependencies)
  for dependency in dependencies {
    if dependency.dependencies.length() > remaining {
      return Err(BudgetExceeded)
    }
    remaining -= dependency.dependencies.length()
    retained.append(dependency.dependencies)
  }
  Ok(
    (
      {
        claims,
        sources,
        count: host_count,
        bytes: original.bytes,
        nodes: original.nodes,
        origin: original.origin,
        dependencies: retained,
        local_claims: original.local_claims,
        local_limits: original.local_limits,
      },
      max_work - remaining,
    ),
  )
}
