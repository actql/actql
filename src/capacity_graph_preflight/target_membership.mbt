///|
pub(all) enum TargetMembershipIssue {
  InvalidVisit
  InvalidClaim
  ForeignConsumer
  ForeignBound
} derive(Eq, Debug)

///|
struct TargetMembership {
  closure : ApplicationClosure
  rows : @program.TargetRows
  visit : Int
  claim : Int
  producer : Int
}

///|
/// Coordinates select a checked occurrence; they are not persistent identities.
/// The closure has already verified producer dependencies and Parameter bindings.
pub fn bind_target_membership(
  closure : ApplicationClosure,
  rows : @program.TargetRows,
  visit : Int,
  claim : Int,
) -> Result[TargetMembership, TargetMembershipIssue] {
  guard closure.entries.get(visit) is Some(entry) else {
    return Err(InvalidVisit)
  }
  if !physical_equal(
      @program.target_rows_pipeline(rows),
      checked_pipeline(entry.sources.graph),
    ) {
    return Err(ForeignConsumer)
  }
  guard @program.application_at(entry.sources.program, claim) is Some(bound) &&
    closure.proof_owners.get((visit, claim)) is Some(producer) else {
    return Err(InvalidClaim)
  }
  if !physical_equal(bound, @program.target_rows_bound(rows)) {
    return Err(ForeignBound)
  }
  Ok({ closure, rows, visit, claim, producer, })
}

///|
pub fn target_membership_closure(v : TargetMembership) -> ApplicationClosure {
  v.closure
}

///|
pub fn target_membership_rows(v : TargetMembership) -> @program.TargetRows {
  v.rows
}

///|
pub fn target_membership_coordinates(v : TargetMembership) -> (Int, Int, Int) {
  (v.visit, v.claim, v.producer)
}
