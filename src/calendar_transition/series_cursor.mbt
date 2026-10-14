///|
pub(all) enum SeriesIssue {
  InvalidSeriesLimits
  InvalidSeriesRange
  SeriesRowLimit
  SeriesWorkLimit
  SeriesBoundary(IntervalIssue)
  SeriesTerminal
} derive(Eq, Debug)

///|
pub(all) enum SeriesPoll {
  CalendarSeriesContinue(work~ : Int)
  CalendarSeriesRow(start_ms~ : Int64, end_ms~ : Int64, work~ : Int)
  CalendarSeriesComplete(work~ : Int)
  CalendarSeriesFailed(SeriesIssue, work~ : Int)
} derive(Eq, Debug)

///|
struct SeriesCursor {
  table : Table
  end_ms : Int64
  unit : @options.CalendarUnit
  week_start : @options.WeekStart?
  max_rows : Int
  mut next_ms : Int64
  mut rows : Int
  mut remaining_work : Int
  mut interval : IntervalCursor?
  mut terminal : Bool
}

///|
/// Retains one interval cursor and emits full intersecting intervals, without
/// materializing a boundary array or clipping to the requested range. This
/// cursor has no output-port, storage, resource or publication authority.
pub fn start_series(
  table : Table,
  start_ms : Int64,
  end_ms : Int64,
  unit : @options.CalendarUnit,
  week_start~ : @options.WeekStart?,
  max_rows~ : Int,
  max_work~ : Int,
) -> Result[SeriesCursor, SeriesIssue] {
  if max_rows < 0 || max_work < 0 { return Err(InvalidSeriesLimits) }
  if start_ms < calendar_domain_start || end_ms >= calendar_domain_end ||
    start_ms > end_ms {
    return Err(InvalidSeriesRange)
  }
  if (unit == @options.Week) != (week_start is Some(_)) {
    return Err(SeriesBoundary(InvalidWeekOrigin))
  }
  Ok({ table, end_ms, unit, week_start, max_rows, next_ms: start_ms,
    rows: 0, remaining_work: max_work, interval: None, terminal: false })
}

///|
pub fn advance_series(
  cursor : SeriesCursor,
  quantum : Int,
) -> Result[SeriesPoll, SeriesIssue] {
  if quantum <= 0 { return Err(InvalidSeriesLimits) }
  if cursor.terminal { return Err(SeriesTerminal) }
  let mut used = 0
  while used < quantum {
    if cursor.next_ms >= cursor.end_ms {
      cursor.terminal = true
      return Ok(CalendarSeriesComplete(work=used))
    }
    if cursor.rows >= cursor.max_rows {
      cursor.terminal = true
      return Ok(CalendarSeriesFailed(SeriesRowLimit, work=used))
    }
    if cursor.remaining_work == 0 {
      cursor.terminal = true
      return Ok(CalendarSeriesFailed(SeriesWorkLimit, work=used))
    }
    if cursor.interval is None {
      cursor.remaining_work -= 1
      used += 1
      cursor.interval = match start_interval(cursor.table, cursor.next_ms,
        cursor.unit, week_start=cursor.week_start, max_work=cursor.remaining_work) {
        Ok(value) => Some(value)
        Err(issue) => {
          cursor.terminal = true
          return Ok(CalendarSeriesFailed(SeriesBoundary(issue), work=used))
        }
      }
      continue
    }
    let interval = cursor.interval.unwrap()
    let poll = advance_interval(interval,
      Int::min(quantum - used, cursor.remaining_work)).unwrap()
    let work = match poll {
      IntervalContinue(work~) | IntervalReady(work~, ..) | IntervalFailed(_, work~) => work
    }
    used += work
    cursor.remaining_work -= work
    match poll {
      IntervalContinue(_) => ()
      IntervalFailed(issue, ..) => {
        cursor.terminal = true
        return Ok(CalendarSeriesFailed(SeriesBoundary(issue), work=used))
      }
      IntervalReady(start_ms~, end_ms~, ..) => {
        cursor.rows += 1
        cursor.next_ms = end_ms
        cursor.interval = None
        return Ok(CalendarSeriesRow(start_ms~, end_ms~, work=used))
      }
    }
  }
  Ok(CalendarSeriesContinue(work=used))
}
