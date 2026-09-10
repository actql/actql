///|
pub(all) struct Transition {
  at_ms : Int64
  offset_seconds : Int
} derive(Eq, Debug)

///|
pub(all) enum Issue {
  InvalidLimit
  TransitionLimit
  InvalidCoverage
  InvalidOffset(Int)
  InvalidTransition(Int)
  RedundantTransition(Int)
} derive(Eq, Debug)

///|
struct Table {
  start_ms : Int64
  end_ms : Int64
  initial_offset_seconds : Int
  transitions : Array[Transition]
}

///|
/// Validates an offset table, not its provenance or membership in a TZDB profile.
/// Coverage is closed-open. Transitions take effect at their UTC millisecond.
pub fn admit(
  start_ms : Int64,
  end_ms : Int64,
  initial_offset_seconds : Int,
  transitions : Array[Transition],
  max_transitions~ : Int,
) -> Result[Table, Issue] {
  if max_transitions < 0 {
    return Err(InvalidLimit)
  }
  if transitions.length() > max_transitions {
    return Err(TransitionLimit)
  }
  // Safe JSON integers also leave room for adding any TZif offset in Int64.
  if start_ms < -9007199254740991L ||
    end_ms > 9007199254740991L ||
    start_ms >= end_ms {
    return Err(InvalidCoverage)
  }
  if initial_offset_seconds == -2147483648 {
    return Err(InvalidOffset(-1))
  }
  let mut previous_time = start_ms
  let mut previous_offset = initial_offset_seconds
  for i in 0..<transitions.length() {
    let t = transitions[i]
    if t.offset_seconds == -2147483648 {
      return Err(InvalidOffset(i))
    }
    if t.at_ms <= previous_time || t.at_ms >= end_ms {
      return Err(InvalidTransition(i))
    }
    if t.offset_seconds == previous_offset {
      return Err(RedundantTransition(i))
    }
    previous_time = t.at_ms
    previous_offset = t.offset_seconds
  }
  Ok({
    start_ms,
    end_ms,
    initial_offset_seconds,
    transitions: transitions.copy(),
  })
}

///|
pub fn coverage(v : Table) -> (Int64, Int64) {
  (v.start_ms, v.end_ms)
}

///|
pub fn initial_offset(v : Table) -> Int {
  v.initial_offset_seconds
}

///|
pub fn transition_count(v : Table) -> Int {
  v.transitions.length()
}

///|
pub fn transition_at(v : Table, index : Int) -> Transition? {
  if index < 0 || index >= v.transitions.length() {
    None
  } else {
    Some(v.transitions[index])
  }
}

///|
/// Does not extrapolate beyond the declared coverage. O(log transition count).
pub fn offset_at(v : Table, utc_ms : Int64) -> Int? {
  if utc_ms < v.start_ms || utc_ms >= v.end_ms {
    return None
  }
  let mut lo = 0
  let mut hi = v.transitions.length()
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    if v.transitions[mid].at_ms <= utc_ms {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  Some(
    if lo == 0 {
      v.initial_offset_seconds
    } else {
      v.transitions[lo - 1].offset_seconds
    },
  )
}
