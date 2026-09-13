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
  consumer_visit : Int
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
  bind_producer_target_membership(closure, rows, visit, visit, claim)
}

///|
/// Associate a target in one checked visit with the exact admitted application
/// in another visit of the same closure. TargetRows already proves the bound's
/// reachability through the retained producer graph; neither CID equality nor
/// matching schema can replace that checked association.
pub fn bind_producer_target_membership(
  closure : ApplicationClosure,
  rows : @program.TargetRows,
  consumer_visit : Int,
  visit : Int,
  claim : Int,
) -> Result[TargetMembership, TargetMembershipIssue] {
  guard closure.entries.get(consumer_visit) is Some(consumer) else {
    return Err(InvalidVisit)
  }
  guard closure.entries.get(visit) is Some(entry) else {
    return Err(InvalidVisit)
  }
  if !physical_equal(
      @program.target_rows_pipeline(rows),
      checked_pipeline(consumer.sources.graph),
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
  Ok({ closure, rows, consumer_visit, visit, claim, producer, })
}

///|
pub fn target_membership_consumer_visit(v : TargetMembership) -> Int {
  v.consumer_visit
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
/// Claim-table visit, original claim index and admitted proof-owner visit.
pub fn target_membership_coordinates(v : TargetMembership) -> (Int, Int, Int) {
  (v.visit, v.claim, v.producer)
}
