///|
pub enum CalendarEnvironmentIssue {
  CapabilityDisabled
  Selection(@environment.CalendarSelectionIssue)
  Artifact(@calendar_profile.Issue)
}

///|
/// Supplement an installed checker with its explicitly selected semantic bytes.
/// Selection and artifact admission belong to the original wire Environment.
/// Preserve every other profile, ModelTask and request-policy owner. This does
/// not enable a disabled capability or establish Calendar execution support.
pub fn checking_environment_with_calendar_artifact(
  value : CheckEnvironment,
  bytes : Bytes,
  limits : @calendar_profile.Limits,
  max_selection_work~ : Int,
) -> Result[CheckEnvironment, CalendarEnvironmentIssue] {
  if !value.operations.calendar {
    return Err(CapabilityDisabled)
  }
  let selection = match
    @environment.read_calendar_selection(value.wire, max_selection_work) {
    Ok(selected) => selected
    Err(issue) => return Err(Selection(issue))
  }
  let profile = match
    @environment.admit_calendar_profile(selection, bytes, limits) {
    Ok(selected) => selected
    Err(issue) => return Err(Artifact(issue))
  }
  Ok({ ..value, calendar: Some(profile), })
}
