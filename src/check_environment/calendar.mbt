///|
pub(all) enum CalendarSelectionIssue {
  InvalidLimits
  BudgetExceeded
  MissingSelection
  InvalidComponent
} derive(Eq, Debug)

///|
struct CalendarSelection {
  environment : WireEnvironment
  table_bytes_cid : String
  tzdb_version : String
  work : Int
}

///|
pub fn read_calendar_selection(
  environment : WireEnvironment,
  max_work : Int,
) -> Result[CalendarSelection, CalendarSelectionIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  let count = @decode.object_length(environment.policy).unwrap()
  if count >= max_work {
    return Err(BudgetExceeded)
  }
  let mut remaining = max_work - count - 1
  let policy = @decode.open_object(environment.policy).unwrap()
  guard @decode.lookup(policy, "calendar") is Some(body) else {
    return Err(MissingSelection)
  }
  guard @decode.object_length(body) is Some(4) else {
    return Err(InvalidComponent)
  }
  if remaining < 5 {
    return Err(BudgetExceeded)
  }
  remaining -= 5
  let object = match
    @decode.closed_object(body, [
      "version", "table_bytes_cid", "tzdb_version", "conversion_law",
    ]) {
    Ok(v) => v
    Err(_) => return Err(InvalidComponent)
  }
  let fields = Some(
    (
      string(object, "version"),
      string(object, "table_bytes_cid"),
      string(object, "tzdb_version"),
      string(object, "conversion_law"),
    ),
  ) catch {
    _ => None
  }
  guard fields is Some((version, pin, release, law)) else {
    return Err(InvalidComponent)
  }
  for n in [version.length(), pin.length(), release.length(), law.length()] {
    if n > remaining {
      return Err(BudgetExceeded)
    }
    remaining -= n
  }
  if version != "actql-calendar-selection/0.1" ||
    law != "actql-calendar-boundaries/0.1" ||
    release.is_empty() ||
    pin.length() != 71 ||
    !pin.has_prefix("sha256:") {
    return Err(InvalidComponent)
  }
  for i in 7..<71 {
    let c = pin[i].to_int()
    if !((c >= 48 && c <= 57) || (c >= 97 && c <= 102)) {
      return Err(InvalidComponent)
    }
  }
  Ok({
    environment,
    table_bytes_cid: pin,
    tzdb_version: release,
    work: max_work - remaining,
  })
}

///|
struct SelectedCalendarProfile {
  selection : CalendarSelection
  profile : @calendar.Profile
}

///|
pub fn admit_calendar_profile(
  selection : CalendarSelection,
  bytes : Bytes,
  limits : @calendar.Limits,
) -> Result[SelectedCalendarProfile, @calendar.Issue] {
  match
    @calendar.admit(
      bytes,
      selection.table_bytes_cid,
      selection.tzdb_version,
      limits,
    ) {
    Ok(profile) => Ok({ selection, profile, })
    Err(issue) => Err(issue)
  }
}

///|
pub fn calendar_selection_environment(v : CalendarSelection) -> WireEnvironment {
  v.environment
}

///|
pub fn calendar_selection_cid(v : CalendarSelection) -> String {
  v.table_bytes_cid
}

///|
pub fn calendar_selection_release(v : CalendarSelection) -> String {
  v.tzdb_version
}

///|
pub fn calendar_selection_work(v : CalendarSelection) -> Int {
  v.work
}

///|
pub fn selected_calendar_selection(
  v : SelectedCalendarProfile,
) -> CalendarSelection {
  v.selection
}

///|
pub fn selected_calendar_profile(
  v : SelectedCalendarProfile,
) -> @calendar.Profile {
  v.profile
}
