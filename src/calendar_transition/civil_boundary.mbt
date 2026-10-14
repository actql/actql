///|
let calendar_domain_start : Int64 = -62135596800000L

///|
let calendar_domain_end : Int64 = 253402300800000L

///|
fn calendar_day_floor(coordinate : Int64) -> Int64 {
  let remainder = coordinate % 86400000L
  coordinate - remainder - (if remainder < 0L { 86400000L } else { 0L })
}

///|
fn calendar_digits(text : String, start : Int, count : Int) -> Int {
  let mut result = 0
  for index in start..<(start + count) {
    result = result * 10 + text[index].to_int() - 48
  }
  result
}

///|
fn calendar_month_boundary(year : Int, month : Int) -> Int64? {
  if year < 1 || year > 9999 || month < 1 || month > 12 {
    return None
  }
  let year_text = year.to_string()
  let month_text = month.to_string()
  let text = "0".repeat(4 - year_text.length()) +
    year_text +
    "-" +
    "0".repeat(2 - month_text.length()) +
    month_text +
    "-01T00:00:00.000Z"
  @value.timestamp_epoch_milliseconds(text)
}

///|
/// Epoch arithmetic represents local civil coordinates only. UTC conversion
/// still uses the original selected offset table, including gaps and folds.
fn calendar_boundary_floor(
  coordinate : Int64,
  unit : @options.CalendarUnit,
  week_start : @options.WeekStart?,
) -> Int64? {
  let day = calendar_day_floor(coordinate)
  match unit {
    Day => Some(day)
    Week => {
      let monday_index = ((day / 86400000L + 3L) % 7L + 7L) % 7L
      let origin = match week_start {
        Some(Monday) => 0L
        Some(Sunday) => 6L
        None => return None
      }
      Some(day - (monday_index - origin + 7L) % 7L * 86400000L)
    }
    Month | Quarter | Year => {
      guard @value.epoch_milliseconds_timestamp(coordinate) is Some(text) else {
        return None
      }
      let year = calendar_digits(text, 0, 4)
      let month = calendar_digits(text, 5, 2)
      let first_month = match unit {
        Quarter => (month - 1) / 3 * 3 + 1
        Year => 1
        _ => month
      }
      calendar_month_boundary(year, first_month)
    }
  }
}

///|
fn calendar_boundary_next(
  coordinate : Int64,
  unit : @options.CalendarUnit,
) -> Int64? {
  match unit {
    Day | Week => {
      let next = coordinate + (if unit == Day { 86400000L } else { 604800000L })
      if next < calendar_domain_end {
        Some(next)
      } else {
        None
      }
    }
    Month | Quarter | Year => {
      guard @value.epoch_milliseconds_timestamp(coordinate) is Some(text) else {
        return None
      }
      let year = calendar_digits(text, 0, 4)
      let month = calendar_digits(text, 5, 2)
      let stride = match unit {
        Month => 1
        Quarter => 3
        _ => 12
      }
      let index = (year - 1) * 12 + month - 1 + stride
      calendar_month_boundary(index / 12 + 1, index % 12 + 1)
    }
  }
}

///|
fn calendar_maximum_span(unit : @options.CalendarUnit) -> Int64 {
  match unit {
    Day => 86400000L
    Week => 604800000L
    Month => 2678400000L
    Quarter => 7948800000L
    Year => 31622400000L
  }
}

///|
pub(all) enum IntervalIssue {
  InvalidIntervalLimits
  InvalidWeekOrigin
  CalendarBoundaryDomain
  IntervalWorkLimit
  IntervalTerminal
} derive(Eq, Debug)

///|
pub(all) enum IntervalPoll {
  IntervalContinue(work~ : Int)
  IntervalReady(start_ms~ : Int64, end_ms~ : Int64, work~ : Int)
  IntervalFailed(IntervalIssue, work~ : Int)
} derive(Eq, Debug)

///|
struct IntervalCursor {
  table : Table
  instant : Int64
  unit : @options.CalendarUnit
  week_start : @options.WeekStart?
  mut remaining_work : Int
  mut offset_index : Int
  mut minimum_offset : Int64
  mut maximum_offset : Int64
  mut initialized : Bool
  mut candidate : Int64?
  mut last_candidate : Int64
  mut inverse : LocalResolution?
  mut left : Int64?
  mut right : Int64?
  mut terminal : Bool
}

///|
/// This is semantic calculation material, not a selected-profile capability,
/// execution permit or resource envelope. The calling owner retains those.
pub fn start_interval(
  table : Table,
  instant : Int64,
  unit : @options.CalendarUnit,
  week_start~ : @options.WeekStart?,
  max_work~ : Int,
) -> Result[IntervalCursor, IntervalIssue] {
  if max_work < 0 {
    return Err(InvalidIntervalLimits)
  }
  if (unit == @options.Week) != (week_start is Some(_)) {
    return Err(InvalidWeekOrigin)
  }
  if instant < calendar_domain_start ||
    instant >= calendar_domain_end ||
    offset_at(table, instant) is None {
    return Err(CalendarBoundaryDomain)
  }
  let initial = table.initial_offset_seconds.to_int64() * 1000L
  Ok({
    table,
    instant,
    unit,
    week_start,
    remaining_work: max_work,
    offset_index: 0,
    minimum_offset: initial,
    maximum_offset: initial,
    initialized: false,
    candidate: None,
    last_candidate: 0L,
    inverse: None,
    left: None,
    right: None,
    terminal: false,
  })
}

///|
/// Scan candidate civil boundaries and choose adjacent distinct UTC instants.
/// Local-to-UTC inversion is not assumed monotone for admitted Int32 offsets.
/// The window follows the offset extrema and the unit's largest civil span;
/// it never changes the offset table, domain, interpretation or work limit.
pub fn advance_interval(
  cursor : IntervalCursor,
  quantum : Int,
) -> Result[IntervalPoll, IntervalIssue] {
  if quantum <= 0 {
    return Err(InvalidIntervalLimits)
  }
  if cursor.terminal {
    return Err(IntervalTerminal)
  }
  let mut used = 0
  while used < quantum {
    if cursor.remaining_work == 0 {
      cursor.terminal = true
      return Ok(IntervalFailed(IntervalWorkLimit, work=used))
    }
    if cursor.inverse is Some(inverse) {
      let slice = Int::min(quantum - used, cursor.remaining_work)
      let poll = advance_local_resolution(inverse, slice).unwrap()
      let (work, resolved) = match poll {
        ResolutionContinue(work~) => (work, None)
        ResolutionReady(utc_ms~, work~) => (work, Some(utc_ms))
        ResolutionFailed(_, work~) => (work, None)
      }
      used += work
      cursor.remaining_work -= work
      if poll is ResolutionContinue(_) {
        continue
      }
      if resolved is Some(utc) {
        if utc >= calendar_domain_start && utc < calendar_domain_end {
          if utc <= cursor.instant {
            cursor.left = Some(
              match cursor.left {
                Some(previous) => Int64::max(previous, utc)
                None => utc
              },
            )
          } else {
            cursor.right = Some(
              match cursor.right {
                Some(previous) => Int64::min(previous, utc)
                None => utc
              },
            )
          }
        }
      }
      cursor.inverse = None
      cursor.candidate = calendar_boundary_next(
        cursor.candidate.unwrap(),
        cursor.unit,
      )
      continue
    }
    cursor.remaining_work -= 1
    used += 1
    if cursor.offset_index < cursor.table.transitions.length() {
      let offset = cursor.table.transitions[cursor.offset_index].offset_seconds.to_int64() *
        1000L
      cursor.minimum_offset = Int64::min(cursor.minimum_offset, offset)
      cursor.maximum_offset = Int64::max(cursor.maximum_offset, offset)
      cursor.offset_index += 1
      continue
    }
    if !cursor.initialized {
      let spread = cursor.maximum_offset - cursor.minimum_offset
      let span = calendar_maximum_span(cursor.unit)
      let first = Int64::max(
        calendar_domain_start,
        cursor.instant + cursor.minimum_offset - spread - span,
      )
      cursor.last_candidate = Int64::min(
        calendar_domain_end - 1L,
        cursor.instant + cursor.maximum_offset + spread + span,
      )
      cursor.candidate = calendar_boundary_floor(
        first,
        cursor.unit,
        cursor.week_start,
      )
      // A weekly floor can precede year 0001. Skip that unrepresentable civil
      // boundary; absence of a valid adjacent start still fails at completion.
      if cursor.candidate is Some(value) {
        if value < calendar_domain_start {
          cursor.candidate = calendar_boundary_next(value, cursor.unit)
        }
      }
      cursor.initialized = true
      continue
    }
    if cursor.candidate is Some(value) {
      if value <= cursor.last_candidate {
        cursor.inverse = Some(
          start_local_resolution(
            cursor.table,
            value,
            max_work=cursor.remaining_work,
          ).unwrap(),
        )
        continue
      }
    }
    cursor.terminal = true
    match (cursor.left, cursor.right) {
      (Some(start), Some(end)) =>
        return Ok(IntervalReady(start_ms=start, end_ms=end, work=used))
      _ => return Ok(IntervalFailed(CalendarBoundaryDomain, work=used))
    }
  }
  Ok(IntervalContinue(work=used))
}
