///|
pub(all) struct StageRequirementLimits {
  max_work : Int
  max_requirements : Int
  max_local_inputs : Int
}

///|
pub enum StageRequirementIssue {
  InvalidLimits
  BudgetExceeded
  Operations(OperationClosureIssue)
  LocalInputs(LocalInputClosureIssue)
  Incoming(IncomingClosureIssue)
  Publications(PublicationClosureIssue)
  SourceModes(SourceModeClosureIssue)
}

///|
struct StageRequirementClosure {
  owner : ProgramIncomingLinks
  operations : ProgramOperationClosure
  inputs : ProgramLocalInputClosure
  incoming : ProgramIncomingClosure
  publications : ProgramPublicationClosure
  source_modes : ProgramSourceModeClosure
  work : Int
  count : Int
}

///|
/// Close staged requirements and selected source modes from one owner, without independently
/// supplied successes. SourceView/Host, semantic identities and other execution
/// enforcement remain separate requirements of the formal Program constructor.
pub fn close_stage_requirements(
  owner : ProgramIncomingLinks,
  limits : StageRequirementLimits,
) -> Result[StageRequirementClosure, StageRequirementIssue] {
  if limits.max_work < 0 ||
    limits.max_requirements < 0 ||
    limits.max_local_inputs < 0 {
    return Err(InvalidLimits)
  }
  if owner.work >= limits.max_work {
    return Err(BudgetExceeded)
  }
  let mut work = owner.work + 1
  let mut remaining = limits.max_requirements
  let operations = match
    close_program_operations(
      owner.resolutions,
      owner.resolutions.work + (limits.max_work - work),
      remaining,
    ) {
    Ok(v) => v
    Err(e) => return Err(Operations(e))
  }
  work += operations.work - owner.resolutions.work
  remaining -= operations.entries.length()
  let inputs = match
    close_program_local_inputs(
      owner,
      max_work=owner.work + (limits.max_work - work),
      max_inputs=limits.max_local_inputs,
      max_execution_checks=remaining,
    ) {
    Ok(v) => v
    Err(e) => return Err(LocalInputs(e))
  }
  work += inputs.work - owner.work
  remaining -= inputs.checks.length()
  let incoming = match
    close_program_incoming(
      owner,
      owner.work + (limits.max_work - work),
      remaining,
    ) {
    Ok(v) => v
    Err(e) => return Err(Incoming(e))
  }
  work += incoming.work - owner.work
  remaining -= incoming.checks.length()
  let publications = match
    close_program_publications(
      owner,
      owner.work + (limits.max_work - work),
      remaining,
    ) {
    Ok(v) => v
    Err(e) => return Err(Publications(e))
  }
  work += publications.work - owner.work
  remaining -= publications.entries.length() + publications.rows.length()
  let source_modes = match
    close_program_source_modes(
      owner,
      owner.work + (limits.max_work - work),
      remaining,
    ) {
    Ok(v) => v
    Err(e) => return Err(SourceModes(e))
  }
  work += source_modes.work - owner.work
  remaining -= source_modes.checks.length()
  Ok({
    owner,
    operations,
    inputs,
    incoming,
    publications,
    source_modes,
    work,
    count: limits.max_requirements - remaining,
  })
}

///|
pub fn stage_requirement_owner(
  v : StageRequirementClosure,
) -> ProgramIncomingLinks {
  v.owner
}

///|
pub fn stage_requirement_operations(
  v : StageRequirementClosure,
) -> ProgramOperationClosure {
  v.operations
}

///|
pub fn stage_requirement_inputs(
  v : StageRequirementClosure,
) -> ProgramLocalInputClosure {
  v.inputs
}

///|
pub fn stage_requirement_incoming(
  v : StageRequirementClosure,
) -> ProgramIncomingClosure {
  v.incoming
}

///|
pub fn stage_requirement_publications(
  v : StageRequirementClosure,
) -> ProgramPublicationClosure {
  v.publications
}

///|
pub fn stage_requirement_usage(v : StageRequirementClosure) -> (Int, Int) {
  (v.work, v.count)
}

///|
pub fn stage_requirement_source_modes(
  v : StageRequirementClosure,
) -> ProgramSourceModeClosure {
  v.source_modes
}
