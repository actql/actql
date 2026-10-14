///|
/// A bounded inverse of the original immutable offset table. This carries no
/// profile selection, execution permission or ambient timezone lookup.
struct LocalResolution {
  table : Table
  local_ms : Int64
  mut segment : Int
  mut remaining_work : Int
  mut exact_utc : Int64?
  mut gap_utc : Int64?
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
    exact_utc: None,
    gap_utc: None,
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
      if cursor.local_ms >= local_start && cursor.local_ms < local_end {
        let candidate = cursor.local_ms - offset_ms
        cursor.exact_utc = Some(
          match cursor.exact_utc {
            None => candidate
            Some(previous) => Int64::min(previous, candidate)
          },
        )
      }
      if index < count {
        let next_offset = cursor.table.transitions[index].offset_seconds.to_int64() *
          1000L
        let next_local_start = end + next_offset
        if cursor.local_ms >= local_end && cursor.local_ms < next_local_start {
          // Match the selected conversion law: if no exact occurrence exists,
          // a forward gap advances to its earliest original transition instant.
          cursor.gap_utc = Some(
            match cursor.gap_utc {
              None => end
              Some(previous) => Int64::min(previous, end)
            },
          )
        }
      }
      cursor.segment += 1
    } else {
      cursor.terminal = true
      let utc = match (cursor.exact_utc, cursor.gap_utc) {
        (Some(value), _) | (None, Some(value)) => value
        _ => return Ok(ResolutionFailed(OutsideResolutionCoverage, work=used))
      }
      return Ok(ResolutionReady(utc_ms=utc, work=used))
    }
  }
  Ok(ResolutionContinue(work=used))
}
