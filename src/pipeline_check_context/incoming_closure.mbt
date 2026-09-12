///|
pub enum IncomingClosureIssue {
  InvalidLimits
  BudgetExceeded
  UnresolvedReceipt(Int)
  UnresolvedSuccessContracts(Int)
  InvalidOccurrence(Int)
}

///|
struct ProgramIncomingClosure {
  owner : ProgramIncomingLinks
  checks : Array[IncomingExecutionCheck]
  work : Int
}

///|
/// Close activation-check bindings, not import identities or observed results.
pub fn close_program_incoming(
  owner : ProgramIncomingLinks,
  max_work : Int,
  max_requirements : Int,
) -> Result[ProgramIncomingClosure, IncomingClosureIssue] {
  if max_work < 0 || max_requirements < 0 {
    return Err(InvalidLimits)
  }
  let count = owner.incoming.entries.length()
  if owner.work >= max_work ||
    count > max_requirements ||
    count > max_work - owner.work - 1 {
    return Err(BudgetExceeded)
  }
  let mut work = owner.work + count + 1
  let checks = []
  for i in 0..<count {
    let site = owner.incoming.entries[i]
    // Success readiness inspects the producer's Stage keys. Reserve that scan
    // for each occurrence; repeated references are not free work.
    match site.requirement {
      Success(_, producer) => {
        let index = @program_refs.stage_semantics_index(
          @program_refs.stage_definition_semantics(producer.definition),
        )
        let stage = @stages.stage_at(
          @stage_results.wiring_source(owner.incoming.wiring),
          index,
        ).unwrap()
        let fields = @decode.object_length(@syntax.stage_body(stage)).unwrap()
        if fields > max_work - work {
          return Err(BudgetExceeded)
        }
        work += fields
      }
      Result(_, _, _) | Receipt(_, _, _) => ()
    }
    let check = match incoming_execution_at(owner, i) {
      Some(Connected(v)) => v
      Some(ReceiptUnresolved(_)) => return Err(UnresolvedReceipt(i))
      Some(SuccessContractsUnresolved(_)) =>
        return Err(UnresolvedSuccessContracts(i))
      None => return Err(InvalidOccurrence(i))
    }
    if !physical_equal(check.site, site) {
      return Err(InvalidOccurrence(i))
    }
    checks.push(check)
  }
  Ok({ owner, checks, work, })
}

///|
pub fn incoming_closure_owner(
  v : ProgramIncomingClosure,
) -> ProgramIncomingLinks {
  v.owner
}

///|
pub fn incoming_closure_count(v : ProgramIncomingClosure) -> Int {
  v.checks.length()
}

///|
pub fn incoming_closure_at(
  v : ProgramIncomingClosure,
  index : Int,
) -> IncomingExecutionCheck? {
  v.checks.get(index)
}

///|
pub fn incoming_closure_work(v : ProgramIncomingClosure) -> Int {
  v.work
}
