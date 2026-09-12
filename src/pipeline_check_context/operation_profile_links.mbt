///|
pub(all) enum OperationProfileLinksIssue {
  InvalidLimits
  BudgetExceeded
  ForeignOwner(Int)
  MissingDemand(Int)
  LexicalMismatch(Int)
  UnconsumedLexical
} derive(Eq, Debug)

///|
pub struct OperationProfileResolution {
  requirement_index : Int
  site : OperationRequirementSite
  profile : @pipeline.OperationProfile
  checks : OperationProfileChecks
  lexical : OperationLexicalResolution?
}

///|
struct ProgramOperationProfileLinks {
  calendar : ProgramOperationCalendar
  entries : Array[OperationProfileResolution]
  work : Int
}

///|
/// Reuse owned checker-profile checks, not a new declaration or Host capability.
/// All non-profile obligations remain in the retained original inventory.
pub fn link_program_operation_profiles(
  calendar : ProgramOperationCalendar,
  max_work : Int,
  max_resolutions : Int,
) -> Result[ProgramOperationProfileLinks, OperationProfileLinksIssue] {
  if max_work < 0 || max_resolutions < 0 {
    return Err(InvalidLimits)
  }
  if calendar.work >= max_work {
    return Err(BudgetExceeded)
  }
  let requirements = calendar.lexical.cells.queries.ranges.fills.frames.scalars.orders.requirements
  let checks = requirements.expressions.identity.sources.operations
  let stages = checks.preparation.profiles.context.selected.context.wired.stages
  let entries : Array[OperationProfileResolution] = []
  let mut work = calendar.work + 1
  let mut lexical_index = 0
  for i in 0..<requirements.entries.length() {
    if work == max_work {
      return Err(BudgetExceeded)
    }
    work += 1
    let site = requirements.entries[i]
    guard @pipeline.operation_profile_requirement(site.requirement)
      is Some(profile) else {
      continue
    }
    if entries.length() == max_resolutions {
      return Err(BudgetExceeded)
    }
    let owner = @parameter_slots.pipeline(
      stages.contexts[site.stage].visits[site.producer_visit].collected,
    )
    if !physical_equal(owner, site.pipeline) {
      return Err(ForeignOwner(i))
    }
    let operation = @pipeline.step_at(owner, site.step).unwrap().operation
    let count = @pipeline.operation_profile_count(operation)
    if count > max_work - work {
      return Err(BudgetExceeded)
    }
    work += count
    let mut found = false
    for j in 0..<count {
      if @pipeline.operation_profile_at(operation, j) == Some(profile) {
        found = true
      }
    }
    if !found {
      return Err(MissingDemand(i))
    }
    let lexical = if profile == @pipeline.TextRankProfile {
      if work == max_work {
        return Err(BudgetExceeded)
      }
      work += 1
      let entry = match calendar.lexical.entries.get(lexical_index) {
        Some(e) => e
        None => return Err(LexicalMismatch(i))
      }
      if entry.stage != site.stage ||
        entry.producer_visit != site.producer_visit ||
        entry.step != site.step {
        return Err(LexicalMismatch(i))
      }
      match operation {
        @pipeline.TextRank(checked~, ..) =>
          if !physical_equal(checked, entry.operation) {
            return Err(LexicalMismatch(i))
          }
        _ => return Err(LexicalMismatch(i))
      }
      lexical_index += 1
      Some(entry)
    } else {
      None
    }
    entries.push({ requirement_index: i, site, profile, checks, lexical, })
  }
  if lexical_index != calendar.lexical.entries.length() {
    return Err(UnconsumedLexical)
  }
  Ok({ calendar, entries, work, })
}

///|
pub fn operation_profile_links_calendar(
  v : ProgramOperationProfileLinks,
) -> ProgramOperationCalendar {
  v.calendar
}

///|
pub fn operation_profile_links_count(v : ProgramOperationProfileLinks) -> Int {
  v.entries.length()
}

///|
pub fn operation_profile_links_at(
  v : ProgramOperationProfileLinks,
  index : Int,
) -> OperationProfileResolution? {
  v.entries.get(index)
}

///|
pub fn operation_profile_links_work(v : ProgramOperationProfileLinks) -> Int {
  v.work
}

///|
/// Additional roots for the exact resolved profile site, not backend capability
/// or complete Unit closure. Repeated sites retain separate owners.
pub fn operation_profile_adopted_law_count(
  v : OperationProfileResolution,
) -> Int {
  @pipeline.operation_profile_adopted_law_count(v.profile)
}

///|
pub fn operation_profile_adopted_law_at(
  v : OperationProfileResolution,
  index : Int,
) -> @pipeline.AdoptedOperationLaw? {
  @pipeline.operation_profile_adopted_law_at(v.profile, index)
}
