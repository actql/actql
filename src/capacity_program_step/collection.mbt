///|
pub(all) enum ApplicationIssue {
  InvalidLimits
  WorkLimit
  ForeignApplication(Int)
  DuplicateApplication(Int)
  MissingApplication(Int)
  ForeignDependency(Int, Int)
} derive(Eq, Debug)

///|
/// Every ordinary Program proof is bound to an actual operation application.
/// Other source branches and enclosing Program identity remain separate.
struct Applications {
  claims : @wire.ProgramClaims
  entries : Array[StepBound?]
  mut remaining : Int
  mut work : Int
  producers : Array[Applications]
  input_usage : Int
  operand_usage : Int
}

///|
/// Supply one application per ordinary Program proof, including dependencies
/// and unused claims. Entries use the arithmetic collection's index order.
pub fn check_applications(
  claims : @wire.ProgramClaims,
  applications : Array[StepBound],
  max_work~ : Int,
  producers? : Array[Applications] = [],
) -> Result[Applications, ApplicationIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  let arithmetic = @wire.program_claim_arithmetic(claims)
  let n = @wire.claim_count(arithmetic)
  if n > max_work || applications.length() > max_work - n {
    return Err(WorkLimit)
  }
  let mut work = n + applications.length()
  if producers.length() > max_work - work {
    return Err(WorkLimit)
  }
  work += producers.length()
  let entries : Array[StepBound?] = Array::make(n, None)
  let mut input_usage = 0
  let mut operand_usage = 0
  for i, application in applications {
    let id = @wire.cid(@wire.program_proof_witness(application.proof))
    guard @wire.claim_index(arithmetic, id) is Some(index) &&
      @wire.program_claim_proof_at(claims, index) is Some(_) else {
      return Err(ForeignApplication(i))
    }
    if entries[index] is Some(_) {
      return Err(DuplicateApplication(i))
    }
    entries[index] = Some(application)
    if application.input_work > 2147483647 - input_usage ||
      application.operand_work > 2147483647 - operand_usage {
      return Err(WorkLimit)
    }
    input_usage += application.input_work
    operand_usage += application.operand_work
  }
  let mut remaining = 0
  for i in 0..<n {
    if work >= max_work {
      return Err(WorkLimit)
    }
    work = work + 1
    match entries[i] {
      None => {
        if @wire.program_claim_proof_at(claims, i) is Some(_) {
          return Err(MissingApplication(i))
        }
        remaining = remaining + 1
      }
      Some(application) => {
        let mut inherited = false
        for producer in producers {
          if work == max_work {
            return Err(WorkLimit)
          }
          work += 1
          let id = @wire.cid(@wire.program_proof_witness(application.proof))
          if @wire.claim_index(
              @wire.program_claim_arithmetic(producer.claims),
              id,
            )
            is Some(index) &&
            application_at(producer, index) is Some(registered) &&
            physical_equal(application, registered) {
            inherited = true
            break
          }
        }
        // This exact subtree was already checked in its producer collection.
        // The enclosing application closure verifies that collection's owner.
        if inherited {
          continue
        }
        let bound_claims = match application.enforcement {
          Some(SequenceEnforcement(v)) =>
            Some(@host.source_claims(@sequence.checked_sources(v)))
          Some(JoinEnforcement(v)) => Some(@host.source_claims(v.sources))
          Some(ComponentsEnforcement(v)) => Some(@host.source_claims(v.sources))
          Some(TraversalEnforcement(v)) => Some(@host.source_claims(v.sources))
          None => None
        }
        if bound_claims is Some(owner) && !physical_equal(owner, claims) {
          return Err(ForeignApplication(i))
        }
        for j, child in application.inputs {
          if work >= max_work {
            return Err(WorkLimit)
          }
          work = work + 1
          match child {
            StepInput(child) => {
              let id = @wire.cid(@wire.program_proof_witness(child.proof))
              let local_match = @wire.claim_index(arithmetic, id) is Some(index) &&
                entries[index] is Some(registered) &&
                physical_equal(child, registered)
              let mut retained = local_match
              if !retained {
                for producer in producers {
                  if work == max_work {
                    return Err(WorkLimit)
                  }
                  work += 1
                  let owner_claims = @wire.program_claim_arithmetic(
                    producer.claims,
                  )
                  if @wire.claim_index(owner_claims, id) is Some(index) &&
                    application_at(producer, index) is Some(registered) &&
                    physical_equal(child, registered) {
                    retained = true
                    break
                  }
                }
              }
              if !retained {
                return Err(ForeignDependency(i, j))
              }
            }
            GraphInput(input) => {
              // Equal numbers or CIDs do not substitute a detached collection.
              let owner = @graph_input.bound_owner(input)
              let source_claims = @host.source_claims(
                @graph_input.checked_sources(owner),
              )
              if !physical_equal(source_claims, claims) {
                return Err(ForeignDependency(i, j))
              }
            }
          }
        }
      }
    }
  }
  Ok({
    claims,
    entries,
    remaining,
    work,
    producers: producers.copy(),
    input_usage,
    operand_usage,
  })
}

///|
/// Input-link work: preparation includes rejected candidates; a caller-supplied
/// collection reports its supplied applications' checked traversal usage.
pub fn application_input_work(v : Applications) -> Int {
  v.input_usage
}

///|
pub fn application_operand_work(v : Applications) -> Int {
  v.operand_usage
}

///|
/// Exact previously checked collections used for external input occurrences.
/// An enclosing closure must register these owners, not just equal claim CIDs.
pub fn application_producer_count(v : Applications) -> Int {
  v.producers.length()
}

///|
pub fn application_producer_at(v : Applications, index : Int) -> Applications? {
  v.producers.get(index)
}

///|
pub fn application_claims(v : Applications) -> @wire.ProgramClaims {
  v.claims
}

///|
pub fn application_at(v : Applications, index : Int) -> StepBound? {
  v.entries.get(index).bind(x => x)
}

///|
/// Nonordinary sources, including mixed preflight claims, still need consumers.
pub fn remaining_source_count(v : Applications) -> Int {
  v.remaining
}

///|
pub fn application_work(v : Applications) -> Int {
  v.work
}
