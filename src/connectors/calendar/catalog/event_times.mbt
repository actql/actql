///|
pub(all) struct CalendarEventTimeLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_resolution_work : Int
}

///|
pub(all) enum CalendarEventTimeIssue {
  InvalidLimits
  BudgetExceeded
  InvalidEvent
  InvalidTime
  MixedTimeKinds
  ReversedInterval
  TimeZoneUnavailable
  TimeZoneCoverage
  ResolutionWorkLimit
} derive(Eq, Debug)

///|
/// Checked provider DATA only. A selected CalendarProfile is not a Calendar
/// account, Site, event version, read grant or Source acquisition owner.
pub struct CalendarEventTimes {
  start : String
  end : String
  all_day : Bool
  response_sha256 : String
  calendar_profile_cid : String
}

///|
fn event_time_text(value : @decode.ObjectView, name : String) -> String? {
  match @decode.field(value, name) {
    Present(value) =>
      match @decode.text(value) {
        Ok(text) if !text.is_empty() => Some(text)
        _ => None
      }
    _ => None
  }
}

///|
fn event_resolve_local_time(
  local : String,
  zone : String,
  profile : @calendar_profile.Profile,
  remaining : Int,
) -> Result[(String, Int), CalendarEventTimeIssue] {
  if local.length() > 39 {
    return Err(InvalidTime)
  }
  guard @calendar_profile.zone(profile, zone) is Some(table) else {
    return Err(TimeZoneUnavailable)
  }
  // The appended Z admits civil fields in an epoch coordinate only. The
  // original selected table, never this spelling, supplies their UTC meaning.
  guard @admitted.normalize_timestamp_text(local + "Z", 40) is Some(spelling) &&
    @admitted.timestamp_instant(spelling) is Some(instant) else {
    return Err(InvalidTime)
  }
  if remaining <= 0 {
    return Err(ResolutionWorkLimit)
  }
  let local_ms = instant.seconds * 1000L +
    (instant.nanoseconds / 1000000).to_int64()
  let cursor = match
    @transition.start_local_resolution(table, local_ms, max_work=remaining) {
    Ok(cursor) => cursor
    Err(_) => return Err(InvalidTime)
  }
  let (utc, work) = match
    @transition.advance_local_resolution(cursor, remaining) {
    Ok(@transition.ResolutionReady(utc_ms~, work~)) => (utc_ms, work)
    Ok(@transition.ResolutionFailed(@transition.OutsideResolutionCoverage, ..)) =>
      return Err(TimeZoneCoverage)
    _ => return Err(ResolutionWorkLimit)
  }
  let mut seconds = utc / 1000L
  let mut within_second = utc % 1000L
  if within_second < 0L {
    seconds -= 1L
    within_second += 1000L
  }
  // Exact/fold resolution preserves finer precision. A forward-gap boundary
  // is the first valid instant selected by the existing table law, not that
  // boundary plus the original nonexistent local time's fractional remainder.
  let extra = match @transition.offset_at(table, utc) {
    Some(offset) if utc + offset.to_int64() * 1000L == local_ms =>
      instant.nanoseconds % 1000000
    _ => 0
  }
  let nanoseconds = within_second.to_int() * 1000000 + extra
  guard @admitted.epoch_parts_timestamp(seconds, nanoseconds) is Some(text) else {
    return Err(InvalidTime)
  }
  Ok((text, work))
}

///|
fn event_endpoint(
  value : @decode.Cursor,
  calendar_time_zone : String,
  profile : @calendar_profile.Profile,
  remaining : Int,
) -> Result[(String, Bool, Int), CalendarEventTimeIssue] {
  guard @decode.open_object(value) is Ok(object) else {
    return Err(InvalidTime)
  }
  match @decode.field(object, "timeZone") {
    Missing => ()
    Present(_) if event_time_text(object, "timeZone") is Some(_) => ()
    _ => return Err(InvalidTime)
  }
  let date = @decode.field(object, "date")
  let datetime = @decode.field(object, "dateTime")
  match (date, datetime) {
    (Present(value), Missing) => {
      guard @decode.text(value) is Ok(date) && date.length() == 10 else {
        return Err(InvalidTime)
      }
      let (text, work) = match
        event_resolve_local_time(
          date + "T00:00:00",
          calendar_time_zone,
          profile,
          remaining,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      Ok((text, true, work))
    }
    (Missing, Present(value)) => {
      guard @decode.text(value) is Ok(text) else { return Err(InvalidTime) }
      if @admitted.normalize_timestamp_text(text, 40) is Some(instant) {
        return Ok((instant, false, 0))
      }
      // Google permits an omitted offset only with this endpoint's explicit
      // timeZone. A calendar/process default is not a replacement for it.
      guard event_time_text(object, "timeZone") is Some(zone) else {
        return Err(InvalidTime)
      }
      let (text, work) = match
        event_resolve_local_time(text, zone, profile, remaining) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      Ok((text, false, work))
    }
    _ => Err(InvalidTime)
  }
}

///|
/// Interpret the original Event's actual start/end pair. All-day dates use
/// the supplied original calendar zone; timed endpoints preserve explicit
/// offsets or use their explicit zone in the same admitted CalendarProfile.
/// Cancelled tombstones with no pair remain outside this pair projection.
pub fn project_calendar_event_times(
  bytes : Bytes,
  calendar_time_zone : String,
  profile : @calendar_profile.Profile,
  limits : CalendarEventTimeLimits,
) -> Result[CalendarEventTimes, CalendarEventTimeIssue] {
  if limits.max_bytes <= 0 ||
    limits.max_nodes <= 0 ||
    limits.max_depth <= 0 ||
    limits.max_resolution_work < 0 {
    return Err(InvalidLimits)
  }
  if bytes.length() > limits.max_bytes ||
    calendar_time_zone.is_empty() ||
    calendar_time_zone.length() > limits.max_bytes ||
    @utf8.encode(calendar_time_zone).length() > limits.max_bytes {
    return Err(BudgetExceeded)
  }
  let source = match
    @source.parse_json_bytes(bytes, {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        match issue.issue {
          InputLimit | NodeLimit | DepthLimit => BudgetExceeded
          _ => InvalidEvent
        },
      )
  }
  let cursor = match
    @decode.admit(source, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    }) {
    Ok(value) => value
    Err(_) => return Err(BudgetExceeded)
  }
  guard @decode.open_object(cursor) is Ok(event) &&
    event_time_text(event, "kind") == Some("calendar#event") &&
    @decode.lookup(event, "start") is Some(original_start) &&
    @decode.lookup(event, "end") is Some(original_end) else {
    return Err(InvalidEvent)
  }
  let (start, all_day, used) = match
    event_endpoint(
      original_start,
      calendar_time_zone,
      profile,
      limits.max_resolution_work,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let (end, end_all_day, _) = match
    event_endpoint(
      original_end,
      calendar_time_zone,
      profile,
      limits.max_resolution_work - used,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if all_day != end_all_day {
    return Err(MixedTimeKinds)
  }
  if all_day &&
    event_time_text(@decode.open_object(original_start).unwrap(), "date").unwrap() >
    event_time_text(@decode.open_object(original_end).unwrap(), "date").unwrap() {
    return Err(ReversedInterval)
  }
  guard @admitted.compare_timestamp_text(start, end) is Some(order) else {
    return Err(InvalidTime)
  }
  if order > 0 {
    return Err(ReversedInterval)
  }
  Ok({
    start,
    end,
    all_day,
    response_sha256: @sha.hex(bytes),
    calendar_profile_cid: @calendar_profile.cid(profile),
  })
}
