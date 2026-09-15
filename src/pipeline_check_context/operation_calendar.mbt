///|
pub(all) enum OperationCalendarIssue {
  InvalidLimits
  BudgetExceeded
  ForeignEnvironment
  MissingArtifact(@environment.CalendarSelection)
  Selection(@environment.CalendarSelectionIssue)
  MissingProfile(Int, Int, Int)
  ProfileMismatch(Int, Int, Int)
}

///|
pub struct OperationCalendarResolution {
  stage : Int
  producer_visit : Int
  step : Int
  operation : @calendar.CheckedCalendar
  selected : @environment.SelectedCalendarProfile
}

///|
struct ProgramOperationCalendar {
  requirements : ProgramOperationRequirements
  lexical : ProgramOperationLexical
  profile : @environment.SelectedCalendarProfile?
  entries : Array[OperationCalendarResolution]
  work : Int
}

///|
pub fn check_program_operation_calendar(
  lexical : ProgramOperationLexical,
  profile : @environment.SelectedCalendarProfile?,
  max_work : Int,
  max_resolutions : Int,
) -> Result[ProgramOperationCalendar, OperationCalendarIssue] {
  if max_work < 0 || max_resolutions < 0 {
    return Err(InvalidLimits)
  }
  if lexical.work >= max_work {
    return Err(BudgetExceeded)
  }
  let b = { remaining: max_work - lexical.work - 1, }
  let requirements = lexical.requirements
  let environment = @environment.capacity_environment(requirements.capacity)
  let stages = requirements.stages
  let entries : Array[OperationCalendarResolution] = []
  try {
    match profile {
      Some(p) => {
        let selection = @environment.selected_calendar_selection(p)
        if !physical_equal(
            @environment.calendar_selection_environment(selection),
            environment,
          ) {
          return Err(ForeignEnvironment)
        }
        scalar_spend(b, @environment.calendar_selection_work(selection))
      }
      None =>
        match @environment.read_calendar_selection(environment, b.remaining) {
          Ok(selection) => return Err(MissingArtifact(selection))
          Err(MissingSelection) =>
            scalar_spend(
              b,
              @decode.object_length(@environment.host_policy(environment)).unwrap() +
              1,
            )
          Err(BudgetExceeded) => return Err(BudgetExceeded)
          Err(issue) => return Err(Selection(issue))
        }
    }
    for stage in 0..<stages.contexts.length() {
      scalar_spend(b, 1)
      let visits = stages.contexts[stage].visits
      for visit in 0..<visits.length() {
        scalar_spend(b, 1)
        let pipeline = @parameter_slots.pipeline(visits[visit].collected)
        for step in 0..<@pipeline.step_count(pipeline) {
          scalar_spend(b, 1)
          guard @pipeline.step_at(pipeline, step).unwrap().operation
            is @pipeline.Calendar(operation) else {
            continue
          }
          guard profile is Some(selected) else {
            return Err(MissingProfile(stage, visit, step))
          }
          if entries.length() == max_resolutions {
            return Err(BudgetExceeded)
          }
          let existing = @calendar.profile(operation)
          let chosen = @environment.selected_calendar_profile(selected)
          let actual = @calendar_profile.cid(existing)
          let expected = @calendar_profile.cid(chosen)
          let actual_release = @calendar_profile.tzdb_version(existing)
          let expected_release = @calendar_profile.tzdb_version(chosen)
          for
            cost in [
              actual.length(),
              expected.length(),
              actual_release.length(),
              expected_release.length(),
            ] {
            scalar_spend(b, cost)
          }
          if actual != expected || actual_release != expected_release {
            return Err(ProfileMismatch(stage, visit, step))
          }
          entries.push({
            stage,
            producer_visit: visit,
            step,
            operation,
            selected,
          })
        }
      }
    }
    Ok({
      lexical,
      requirements,
      profile,
      entries,
      work: max_work - b.remaining,
    })
  } catch {
    OperationScalarStop(_) => Err(BudgetExceeded)
  }
}

///|
pub fn operation_calendar_lexical(
  v : ProgramOperationCalendar,
) -> ProgramOperationLexical {
  v.lexical
}

///|
pub fn operation_calendar_profile(
  v : ProgramOperationCalendar,
) -> @environment.SelectedCalendarProfile? {
  v.profile
}

///|
pub fn operation_calendar_count(v : ProgramOperationCalendar) -> Int {
  v.entries.length()
}

///|
pub fn operation_calendar_at(
  v : ProgramOperationCalendar,
  index : Int,
) -> OperationCalendarResolution? {
  v.entries.get(index)
}

///|
pub fn operation_calendar_work(v : ProgramOperationCalendar) -> Int {
  v.work
}
