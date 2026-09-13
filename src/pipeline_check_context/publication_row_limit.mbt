///|
pub(all) enum PublicationRowLimitIssue {
  InvalidLimits
  InvalidResult
  BudgetExceeded
  MissingHostCeiling
} derive(Eq, Debug)

///|
/// Static selection for a Result's output-row scope. The Host ceiling is an
/// enforcement restriction, never proof that this many rows were observed.
/// Canonical resolved-limit emission and binding to the final semantic subject
/// are separate; this value is not a runnable Plan or an execution receipt.
struct PublicationRowLimit {
  owner : ProgramPublicationClosure
  result : Int
  host : @policy.Ceiling
  maximum : Int64
  first : Int
  count : Int
  work : Int
}

///|
/// Select every retained applicable Program candidate plus the exact context's
/// Host artifact-row ceiling. The Result grammar has no authored row guard.
/// No caller-supplied policy, bound, or numeric override is accepted.
pub fn select_publication_row_limit(
  owner : ProgramPublicationClosure,
  result : Int,
  max_work : Int,
  max_candidates : Int,
) -> Result[PublicationRowLimit, PublicationRowLimitIssue] {
  if max_work < 0 || max_candidates < 0 {
    return Err(InvalidLimits)
  }
  guard owner.entries.get(result) is Some(publication) else {
    return Err(InvalidResult)
  }
  let (first, count) = owner.row_ranges[result]
  if max_work <= owner.work ||
    count > max_work - owner.work - 1 ||
    max_candidates == 0 ||
    count > max_candidates - 1 {
    return Err(BudgetExceeded)
  }
  let policy = @capacity.application_closure_policy(
    publication.context.capacity,
  )
  guard @policy.ceiling(policy, "max_artifact_rows") is Some(host) else {
    return Err(MissingHostCeiling)
  }
  let mut maximum = @policy.ceiling_value(host)
  for i in first..<(first + count) {
    let rows = @capacity.target_membership_rows(owner.rows[i].membership)
    maximum = Int64::min(maximum, @step_bounds.target_rows_value(rows))
  }
  Ok({
    owner,
    result,
    host,
    maximum,
    first,
    count,
    work: owner.work + count + 1,
  })
}

///|
pub fn publication_row_limit_owner(
  v : PublicationRowLimit,
) -> ProgramPublicationClosure {
  v.owner
}

///|
pub fn publication_row_limit_result(
  v : PublicationRowLimit,
) -> PublicationResolution {
  v.owner.entries[v.result]
}

///|
pub fn publication_row_limit_host(v : PublicationRowLimit) -> @policy.Ceiling {
  v.host
}

///|
pub fn publication_row_limit_maximum(v : PublicationRowLimit) -> Int64 {
  v.maximum
}

///|
pub fn publication_row_limit_program_count(v : PublicationRowLimit) -> Int {
  v.count
}

///|
pub fn publication_row_limit_program_at(
  v : PublicationRowLimit,
  index : Int,
) -> PublicationRowCandidate? {
  if index < 0 || index >= v.count {
    None
  } else {
    Some(v.owner.rows[v.first + index])
  }
}

///|
pub fn publication_row_limit_work(v : PublicationRowLimit) -> Int {
  v.work
}
