///|
pub(all) enum IncomingLinksIssue {
  InvalidLimits
  ForeignIdentity
  BudgetExceeded
} derive(Eq, Debug)

///|
/// Owned incoming requirements and operation checks, not an executable Program.
struct ProgramIncomingLinks {
  profiles : ProgramOperationProfileLinks
  incoming : ProgramIncomingRequirements
  work : Int
}

///|
/// Join two checked branches only at their exact shared identity owner.
/// Public CID equality cannot substitute for common admission ownership.
pub fn link_program_incoming(
  profiles : ProgramOperationProfileLinks,
  incoming : ProgramIncomingRequirements,
  limits : IncomingLimits,
) -> Result[ProgramIncomingLinks, IncomingLinksIssue] {
  if limits.max_work < 0 ||
    limits.max_name_units < 0 ||
    limits.max_requirements < 0 {
    return Err(InvalidLimits)
  }
  let identity = profiles.calendar.lexical.cells.queries.ranges.fills.frames.scalars.orders.requirements.expressions.identity
  if !physical_equal(identity, incoming.identity) {
    return Err(ForeignIdentity)
  }
  // Both branches already include identity.work. Count that shared prefix once,
  // but include all branch-specific work and the joining check itself.
  let extra = incoming.work - identity.work
  if profiles.work >= limits.max_work ||
    extra > limits.max_work - profiles.work - 1 ||
    incoming.name_units > limits.max_name_units ||
    incoming.entries.length() > limits.max_requirements {
    return Err(BudgetExceeded)
  }
  Ok({ profiles, incoming, work: profiles.work + extra + 1, })
}

///|
pub fn incoming_links_profiles(
  v : ProgramIncomingLinks,
) -> ProgramOperationProfileLinks {
  v.profiles
}

///|
pub fn incoming_links_requirements(
  v : ProgramIncomingLinks,
) -> ProgramIncomingRequirements {
  v.incoming
}

///|
pub fn incoming_links_work(v : ProgramIncomingLinks) -> Int {
  v.work
}
