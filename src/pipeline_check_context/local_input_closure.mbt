///|
pub enum LocalInputClosureIssue {
  InvalidLimits
  BudgetExceeded
  UnresolvedInput(Int)
  InvalidExecutionBinding(Int, Int)
}

///|
struct ProgramLocalInputClosure {
  owner : ProgramIncomingLinks
  checks : Array[LocalInputExecutionCheck]
  work : Int
}

///|
/// Close all retained Local input occurrences, including unused inputs.
/// The result binds required future admission; it does not contain admitted rows.
pub fn close_program_local_inputs(
  owner : ProgramIncomingLinks,
  max_work~ : Int,
  max_inputs~ : Int,
  max_execution_checks~ : Int,
) -> Result[ProgramLocalInputClosure, LocalInputClosureIssue] {
  if max_work < 0 || max_inputs < 0 || max_execution_checks < 0 {
    return Err(InvalidLimits)
  }
  let count = owner.local_inputs.length()
  if owner.work >= max_work ||
    count > max_inputs ||
    count > max_work - owner.work - 1 {
    return Err(BudgetExceeded)
  }
  let mut work = owner.work + count + 1
  let checks : Array[LocalInputExecutionCheck] = []
  for i in 0..<count {
    let subject = owner.local_inputs[i]
    let n = match local_input_execution_count(subject) {
      Some(v) => v
      None => return Err(UnresolvedInput(i))
    }
    if n > max_work - work || n > max_execution_checks - checks.length() {
      return Err(BudgetExceeded)
    }
    work += n
    for j in 0..<n {
      guard local_input_execution_at(subject, j) is Some(check) else {
        return Err(InvalidExecutionBinding(i, j))
      }
      if !physical_equal(check.subject, subject) {
        return Err(InvalidExecutionBinding(i, j))
      }
      // Validate the entire same-subject prerequisite sequence, not merely a
      // nonzero count. New admission kinds require an explicit closing rule.
      let expected = match check.kind {
        RawBinding => None
        PrimaryKeyComponents => Some(RawBinding)
        PrimaryKeyUniqueness => Some(PrimaryKeyComponents)
      }
      match (expected, local_input_execution_predecessor(check)) {
        (None, None) => if j != 0 { return Err(InvalidExecutionBinding(i, j)) }
        (Some(kind), Some(prior)) => {
          if j == 0 ||
            prior.kind != kind ||
            !physical_equal(prior.subject, subject) {
            return Err(InvalidExecutionBinding(i, j))
          }
          let preceding = checks[checks.length() - 1]
          if preceding.kind != kind ||
            !physical_equal(preceding.subject, subject) {
            return Err(InvalidExecutionBinding(i, j))
          }
        }
        _ => return Err(InvalidExecutionBinding(i, j))
      }
      checks.push(check)
    }
  }
  Ok({ owner, checks, work, })
}

///|
pub fn local_input_closure_owner(
  v : ProgramLocalInputClosure,
) -> ProgramIncomingLinks {
  v.owner
}

///|
pub fn local_input_closure_count(v : ProgramLocalInputClosure) -> Int {
  v.checks.length()
}

///|
pub fn local_input_closure_at(
  v : ProgramLocalInputClosure,
  index : Int,
) -> LocalInputExecutionCheck? {
  v.checks.get(index)
}

///|
pub fn local_input_closure_work(v : ProgramLocalInputClosure) -> Int {
  v.work
}
