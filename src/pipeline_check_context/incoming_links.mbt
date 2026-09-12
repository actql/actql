///|
pub(all) enum IncomingLinksIssue {
  InvalidLimits
  ForeignIdentity
  BudgetExceeded
  OperationCoverage(OperationResolutionIndexIssue)
  LocalInputOwner(Int, Int)
} derive(Eq, Debug)

///|
/// Owned incoming requirements and operation checks, not an executable Program.
struct ProgramIncomingLinks {
  profiles : ProgramOperationProfileLinks
  incoming : ProgramIncomingRequirements
  resolutions : ProgramOperationResolutionIndex
  local_inputs : Array[LocalInputRequirement]
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
  let requirements = profiles.calendar.lexical.cells.queries.ranges.fills.frames.scalars.orders.requirements
  let identity = requirements.expressions.identity
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
  // Reserve incoming-branch work before allocating the operation index. Its
  // complete original inventory is bounded by the remaining aggregate work;
  // max_requirements retains its incoming-occurrence meaning.
  let resolutions = match
    index_program_operation_resolutions(
      profiles,
      limits.max_work - extra - 1,
      requirements.entries.length(),
    ) {
    Ok(v) => v
    Err(BudgetExceeded) => return Err(BudgetExceeded)
    Err(issue) => return Err(OperationCoverage(issue))
  }
  let (local_inputs, local_work) = collect_local_input_requirements(
    identity.sources.operations.preparation.profiles.context.selected.context,
    limits.max_work - extra - 1 - resolutions.work,
  ) catch {
    Stop(issue) => return Err(issue)
  }
  Ok({
    profiles,
    incoming,
    resolutions,
    local_inputs,
    work: resolutions.work + extra + 1 + local_work,
  })
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

///|
pub fn incoming_links_resolutions(
  v : ProgramIncomingLinks,
) -> ProgramOperationResolutionIndex {
  v.resolutions
}

///|
pub fn incoming_links_local_input_count(v : ProgramIncomingLinks) -> Int {
  v.local_inputs.length()
}

///|
pub fn incoming_links_local_input_at(
  v : ProgramIncomingLinks,
  index : Int,
) -> LocalInputRequirement? {
  v.local_inputs.get(index)
}
