///|
/// Return only the Profile retained by this original checker. This neither
/// admits provider JSON nor selects a default, installation, Source or grant.
/// The Host still owns passing its same checked-environment original here.
#export_name("calendarEventsProfileFromEnvironment")
pub fn calendar_events_profile_from_environment(
  environment : @program_check.CheckEnvironment,
) -> Result[@calendar_profile.Profile, @catalog.CalendarEventsIssue] {
  match @program_check.checking_environment_calendar_profile(environment) {
    Some(selected) => Ok(@check_environment.selected_calendar_profile(selected))
    None => Err(@catalog.TimeZoneUnavailable)
  }
}
