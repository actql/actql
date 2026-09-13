///|
pub(all) enum OperationResolution {
  AsOfCompletion(AsOfKeyCompletion)
  WindowPublication(WindowPublicationResources)
  Order(OperationOrderLink)
  Scalar(OperationScalarResolution)
  Frame(OperationFrameResolution)
  Fill(OperationFillResolution)
  Range(OperationRangeResolution)
  Query(OperationQueryResolution)
  Cell(OperationCellResolution)
  ProfileResolution(OperationProfileResolution)
  JoinCardinality(JoinCardinalitySelection)
  AssertionConsumption(AssertionConsumptionLink)
}

///|
/// Unresolved is not an execution check and cannot authorize deferral.
pub(all) enum OperationResolutionState {
  Resolved(OperationResolution)
  Execution(OperationExecutionCheck)
  Unresolved
}

///|
pub(all) enum OperationResolutionIndexIssue {
  InvalidLimits
  BudgetExceeded
  ForeignOccurrence(Int)
  DuplicateResolution(Int)
} derive(Eq, Debug)

///|
struct ProgramOperationResolutionIndex {
  profiles : ProgramOperationProfileLinks
  requirements : ProgramOperationRequirements
  states : Array[OperationResolutionState]
  unresolved : Int
  work : Int
  values_bytes : Int
  values_nodes : Int
}

///|
fn resolution_occurrence(
  v : OperationResolution,
) -> (Int, OperationRequirementSite) {
  match v {
    AsOfCompletion(r) => (r.requirement_index, r.site)
    WindowPublication(r) => (r.requirement_index, r.site)
    Order(r) => (r.requirement_index, r.site)
    Scalar(r) => (r.requirement_index, r.site)
    Frame(r) => (r.requirement_index, r.site)
    Fill(r) => (r.requirement_index, r.site)
    Range(r) => (r.requirement_index, r.site)
    Query(r) => (r.requirement_index, r.site)
    Cell(r) => (r.requirement_index, r.site)
    ProfileResolution(r) => (r.requirement_index, r.site)
    JoinCardinality(r) => (r.requirement_index, r.site)
    AssertionConsumption(r) => (r.requirement_index, r.site)
  }
}

///|
/// Index existing resolutions by exact occurrence, not by equivalent values or
/// matching counts. Calendar/lexical operation-wide admissions remain retained
/// through profiles and do not automatically discharge an unrelated obligation.
/// This is not final coverage: Unresolved entries require explicit disposition
/// at the Program boundary, including fully bound execution checks where allowed.
pub fn index_program_operation_resolutions(
  profiles : ProgramOperationProfileLinks,
  max_work : Int,
  max_requirements : Int,
) -> Result[ProgramOperationResolutionIndex, OperationResolutionIndexIssue] {
  if max_work < 0 || max_requirements < 0 {
    return Err(InvalidLimits)
  }
  let cells = profiles.calendar.lexical.cells
  let queries = cells.queries
  let ranges = queries.ranges
  let fills = ranges.fills
  let frames = fills.frames
  let scalars = frames.scalars
  let orders = scalars.orders
  let requirements = orders.requirements
  let count = requirements.entries.length()
  if profiles.work >= max_work || count > max_requirements {
    return Err(BudgetExceeded)
  }
  let mut work = profiles.work + 1
  // Reserve every slot and resolution visit before allocating the index.
  // Sequential subtraction avoids overflowing a sum of caller-bounded counts.
  for
    cost in [
      count,
      count,
      orders.links.length(),
      scalars.entries.length(),
      frames.entries.length(),
      fills.entries.length(),
      ranges.entries.length(),
      queries.entries.length(),
      cells.entries.length(),
      profiles.entries.length(),
    ] {
    if cost > max_work - work {
      return Err(BudgetExceeded)
    }
    work += cost
  }
  let states : Array[OperationResolutionState] = Array::make(count, Unresolved)
  let mut unresolved = count
  let attach = fn(
    resolution : OperationResolution,
  ) -> OperationResolutionIndexIssue? {
    let (index, site) = resolution_occurrence(resolution)
    guard requirements.entries.get(index) is Some(expected) else {
      return Some(ForeignOccurrence(index))
    }
    if !physical_equal(site, expected) {
      return Some(ForeignOccurrence(index))
    }
    if states[index] is Resolved(_) {
      return Some(DuplicateResolution(index))
    }
    states[index] = Resolved(resolution)
    unresolved -= 1
    None
  }
  for r in orders.links {
    if attach(Order(r)) is Some(e) {
      return Err(e)
    }
  }
  for r in scalars.entries {
    if attach(Scalar(r)) is Some(e) {
      return Err(e)
    }
  }
  for r in frames.entries {
    if attach(Frame(r)) is Some(e) {
      return Err(e)
    }
  }
  for r in fills.entries {
    if attach(Fill(r)) is Some(e) {
      return Err(e)
    }
  }
  for r in ranges.entries {
    if attach(Range(r)) is Some(e) {
      return Err(e)
    }
  }
  for r in queries.entries {
    if attach(Query(r)) is Some(e) {
      return Err(e)
    }
  }
  for r in cells.entries {
    if attach(Cell(r)) is Some(e) {
      return Err(e)
    }
  }
  for r in profiles.entries {
    if attach(ProfileResolution(r)) is Some(e) {
      return Err(e)
    }
  }
  let mut needs_consumption = false
  let calendar_selections : Map[(Int, Int, Int), OperationCalendarResolution] = Map([],
  )
  if profiles.calendar.entries.length() > max_work - work {
    return Err(BudgetExceeded)
  }
  work += profiles.calendar.entries.length()
  for selection in profiles.calendar.entries {
    let key = (selection.stage, selection.producer_visit, selection.step)
    if calendar_selections.contains(key) {
      return Err(ForeignOccurrence(0))
    }
    calendar_selections[key] = selection
  }
  for i in 0..<count {
    match asof_key_completion(requirements.entries[i], i) {
      Ok(Some(completion)) =>
        if attach(AsOfCompletion(completion)) is Some(error) {
          return Err(error)
        }
      Ok(None) => ()
      Err(error) => return Err(error)
    }
    if requirements.entries[i].requirement
      is @pipeline.RelationRequirement(pending) &&
      pending.kind is @relation.AssertionConsumption {
      needs_consumption = true
    }
    let (window_candidate, window_work) = window_execution_check(
      requirements.entries[i],
      i,
      requirements,
      states,
      max_work - work,
    )
    work += window_work
    let (watermark_candidate, watermark_work) = watermark_execution_check(
      requirements.entries[i],
      i,
      requirements,
      states,
      max_work - work,
    )
    work += watermark_work
    let candidate = match dedupe_execution_check(requirements.entries[i]) {
      Ok(None) => {
        let site = requirements.entries[i]
        let stages = requirements.expressions.identity.sources.operations.preparation.profiles.context.selected.context.wired.stages
        let stage = stages.contexts[site.stage]
        if !physical_equal(
            @parameter_slots.pipeline(
              stage.visits[site.producer_visit].collected,
            ),
            site.pipeline,
          ) {
          return Err(ForeignOccurrence(i))
        }
        let policy = @capacity.application_closure_policy(
          stage.context.capacity,
        )
        direct_execution_candidate(
          site, policy, window_candidate, watermark_candidate,
        )
      }
      other => other
    }
    let candidate = match candidate {
      Ok(None) => {
        let (session_candidate, session_work) = session_execution_check(
          requirements.entries[i],
          i,
          requirements.entries,
          states,
          max_work - work,
        )
        work += session_work
        session_candidate
      }
      other => other
    }
    let candidate = match candidate {
      Ok(None) => {
        let site = requirements.entries[i]
        let stages = requirements.expressions.identity.sources.operations.preparation.profiles.context.selected.context.wired.stages
        let policy = @capacity.application_closure_policy(
          stages.contexts[site.stage].context.capacity,
        )
        event_output_envelope_check(site, policy)
      }
      other => other
    }
    let candidate = match candidate {
      Ok(None) => {
        let site = requirements.entries[i]
        let stages = requirements.expressions.identity.sources.operations.preparation.profiles.context.selected.context.wired.stages
        let policy = @capacity.application_closure_policy(
          stages.contexts[site.stage].context.capacity,
        )
        let (series_candidate, series_work) = series_execution_check(
          site,
          i,
          requirements.entries,
          states,
          policy,
          max_work - work,
        )
        work += series_work
        series_candidate
      }
      other => other
    }
    let candidate = match candidate {
      Ok(None) => {
        let site = requirements.entries[i]
        let stages = requirements.expressions.identity.sources.operations.preparation.profiles.context.selected.context.wired.stages
        let policy = @capacity.application_closure_policy(
          stages.contexts[site.stage].context.capacity,
        )
        let (result, used) = calendar_execution_check(
          site,
          i,
          requirements.entries,
          states,
          calendar_selections.get((site.stage, site.producer_visit, site.step)),
          policy,
          max_work - work,
        )
        work += used
        result
      }
      other => other
    }
    let candidate = match candidate {
      Ok(None) => sequence_execution_check(requirements.entries[i])
      other => other
    }
    let candidate = match candidate {
      Ok(None) => {
        let (result, used) = sequence_match_check(
          requirements.entries[i],
          i,
          requirements.entries,
          states,
          max_work - work,
        )
        work += used
        result
      }
      other => other
    }
    let candidate = match candidate {
      Ok(None) =>
        sequence_limits_candidate(requirements, requirements.entries[i])
      other => other
    }
    match candidate {
      Err(BudgetExceeded) => return Err(BudgetExceeded)
      Err(_) => return Err(ForeignOccurrence(i))
      Ok(None) => ()
      Ok(Some(check)) => {
        guard states[i] is Unresolved else {
          return Err(DuplicateResolution(i))
        }
        states[i] = Execution(check)
        unresolved -= 1
      }
    }
  }
  if needs_consumption {
    let (links, used) = match
      assertion_consumption_links(requirements, max_work - work) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    work += used
    for link in links {
      if attach(AssertionConsumption(link)) is Some(error) {
        return Err(error)
      }
    }
  }
  Ok({
    profiles,
    requirements,
    states,
    unresolved,
    work,
    values_bytes: 0,
    values_nodes: 0,
  })
}

///|
pub fn operation_resolution_profiles(
  v : ProgramOperationResolutionIndex,
) -> ProgramOperationProfileLinks {
  v.profiles
}

///|
pub fn operation_resolution_requirements(
  v : ProgramOperationResolutionIndex,
) -> ProgramOperationRequirements {
  v.requirements
}

///|
pub fn operation_resolution_count(v : ProgramOperationResolutionIndex) -> Int {
  v.states.length()
}

///|
/// None denotes an out-of-range index, not an unresolved obligation.
pub fn operation_resolution_at(
  v : ProgramOperationResolutionIndex,
  index : Int,
) -> OperationResolutionState? {
  v.states.get(index)
}

///|
pub fn operation_resolution_unresolved_count(
  v : ProgramOperationResolutionIndex,
) -> Int {
  v.unresolved
}

///|
pub fn operation_resolution_work(v : ProgramOperationResolutionIndex) -> Int {
  v.work
}

///|
/// Aggregate values payload-measurement bytes and traversal nodes; metadata
/// artifact passes have the separate ceilings in ValuesPublicationLimits.
pub fn operation_resolution_values_usage(
  v : ProgramOperationResolutionIndex,
) -> (Int, Int) {
  (v.values_bytes, v.values_nodes)
}
