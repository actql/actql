///|
/// A bounded inverse of the original immutable offset table. This carries no
/// profile selection, execution permission or ambient timezone lookup.
struct LocalResolution {
  table : Table
  local_ms : Int64
  mut segment : Int
  mut remaining_work : Int
  mut first_local : Int64?
  mut last_local : Int64?
  mut best_local : Int64?
  mut best_utc : Int64?
  mut terminal : Bool
}

///|
pub(all) enum LocalResolutionIssue {
  InvalidResolutionLimits
  InvalidLocalInstant
  ResolutionWorkLimit
  OutsideResolutionCoverage
  ResolutionTerminal
} derive(Eq, Debug)

///|
pub(all) enum LocalResolutionPoll {
  ResolutionContinue(work~ : Int)
  ResolutionReady(utc_ms~ : Int64, work~ : Int)
  ResolutionFailed(LocalResolutionIssue, work~ : Int)
} derive(Eq, Debug)

///|
/// Resolve earliest UTC occurrence for a fold, or the first valid local instant
/// after a gap. The local coordinate uses UTC epoch arithmetic for civil fields;
/// it is not itself a UTC instant. The caller retains calendar-domain checks.
pub fn start_local_resolution(
  table : Table,
  local_ms : Int64,
  max_work~ : Int,
) -> Result[LocalResolution, LocalResolutionIssue] {
  if max_work < 0 {
    return Err(InvalidResolutionLimits)
  }
  if local_ms < -9007199254740991L || local_ms > 9007199254740991L {
    return Err(InvalidLocalInstant)
  }
  Ok({
    table,
    local_ms,
    segment: 0,
    remaining_work: max_work,
    first_local: None,
    last_local: None,
    best_local: None,
    best_utc: None,
    terminal: false,
  })
}

///|
/// One logical work unit per offset segment and one for finalization. Scanning
/// every segment avoids assuming local time is monotone across transitions.
/// A caller's existing bounded kernel can stop between these finite polls.
pub fn advance_local_resolution(
  cursor : LocalResolution,
  quantum : Int,
) -> Result[LocalResolutionPoll, LocalResolutionIssue] {
  if quantum <= 0 {
    return Err(InvalidResolutionLimits)
  }
  if cursor.terminal {
    return Err(ResolutionTerminal)
  }
  let mut used = 0
  while used < quantum {
    if cursor.remaining_work == 0 {
      cursor.terminal = true
      return Ok(ResolutionFailed(ResolutionWorkLimit, work=used))
    }
    cursor.remaining_work -= 1
    used += 1
    let index = cursor.segment
    let count = cursor.table.transitions.length()
    if index <= count {
      let start = if index == 0 {
        cursor.table.start_ms
      } else {
        cursor.table.transitions[index - 1].at_ms
      }
      let end = if index == count {
        cursor.table.end_ms
      } else {
        cursor.table.transitions[index].at_ms
      }
      let offset = if index == 0 {
        cursor.table.initial_offset_seconds
      } else {
        cursor.table.transitions[index - 1].offset_seconds
      }
      // Table admission bounds UTC times and Int32 seconds. Their sum and the
      // inverse subtraction remain exact within Int64, without float rounding.
      let offset_ms = offset.to_int64() * 1000L
      let local_start = start + offset_ms
      let local_end = end + offset_ms
      cursor.first_local = Some(
        match cursor.first_local {
          None => local_start
          Some(value) => Int64::min(value, local_start)
        },
      )
      cursor.last_local = Some(
        match cursor.last_local {
          None => local_end
          Some(value) => Int64::max(value, local_end)
        },
      )
      let candidate_local = Int64::max(cursor.local_ms, local_start)
      if candidate_local < local_end {
        let candidate_utc = candidate_local - offset_ms
        let replace = match (cursor.best_local, cursor.best_utc) {
          (Some(local), Some(utc)) =>
            candidate_local < local ||
            (candidate_local == local && candidate_utc < utc)
          _ => true
        }
        if replace {
          cursor.best_local = Some(candidate_local)
          cursor.best_utc = Some(candidate_utc)
        }
      }
      cursor.segment += 1
    } else {
      cursor.terminal = true
      guard cursor.first_local is Some(first) &&
        cursor.last_local is Some(last) &&
        cursor.local_ms >= first &&
        cursor.local_ms < last &&
        cursor.best_utc is Some(utc) else {
        return Ok(ResolutionFailed(OutsideResolutionCoverage, work=used))
      }
      return Ok(ResolutionReady(utc_ms=utc, work=used))
    }
  }
  Ok(ResolutionContinue(work=used))
}
