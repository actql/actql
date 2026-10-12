///|
// The common file selection matcher, not a provider glob translation or a
// new acquisition owner. Cursor steps are retained by the existing row read.
priv enum ListingGlobToken {
  Literal(Int)
  One
  Many
  DeepBoundary
  DeepBody
  DeepTail
  OptionalDeepBoundary
}

///|
priv struct ListingGlob {
  tokens : Array[ListingGlobToken]
}

///|
priv struct ListingGlobCursor {
  glob : ListingGlob
  mut path : String
  mut active : Array[Bool]
  mut next : Array[Bool]
  mut offset : Int
  mut state : Int
  mut transferring : Bool
  mut scalar : Int
  mut scalar_end : Int
  mut finished : Bool
  mut matched : Bool
}

///|
priv enum ListingGlobStep {
  Continue(Int)
  Complete(Bool, Int)
}

///|
fn listing_scalar(text : String, offset : Int) -> (Int, Int)? {
  if offset < 0 || offset >= text.length() {
    return None
  }
  let high = text[offset].to_int()
  if high >= 0xD800 && high <= 0xDBFF {
    if offset + 1 >= text.length() {
      return None
    }
    let low = text[offset + 1].to_int()
    if low < 0xDC00 || low > 0xDFFF {
      return None
    }
    Some((0x10000 + ((high - 0xD800) << 10) + low - 0xDC00, offset + 2))
  } else if high >= 0xDC00 && high <= 0xDFFF {
    None
  } else {
    Some((high, offset + 1))
  }
}

///|
fn compile_listing_glob(
  pattern : String,
  max_units : Int,
) -> Result[ListingGlob, RowSourceIssue] {
  if max_units < 0 || pattern.length() > max_units {
    return Err(ListingLimit("glob_pattern_units"))
  }
  // The input bound precedes split/allocation. Adjacent whole-component **
  // tokens have the same matcher language; do not rewrite the Request text.
  let components : Array[String] = []
  for component in pattern.split("/") {
    if component == "**" && components.last() is Some("**") {
      continue
    }
    components.push(component.to_owned())
  }
  let tokens : Array[ListingGlobToken] = []
  for index in 0..<components.length() {
    let component = components[index]
    let last = index + 1 == components.length()
    if component == "**" {
      if last {
        if tokens.last() is Some(Literal(47)) {
          tokens.pop() |> ignore
          tokens.push(OptionalDeepBoundary)
        }
        tokens.push(DeepTail)
      } else {
        tokens.push(DeepBoundary)
        tokens.push(DeepBody)
      }
      continue
    }
    let mut offset = 0
    while offset < component.length() {
      let (scalar, end) = match listing_scalar(component, offset) {
        Some(value) => value
        None => return Err(ListingGlobInvalid)
      }
      offset = end
      match scalar {
        42 => {
          if offset < component.length() && component[offset] == '*' {
            return Err(ListingGlobInvalid)
          }
          tokens.push(Many)
        }
        63 => tokens.push(One)
        92 => {
          let (escaped, end) = match listing_scalar(component, offset) {
            Some(value) => value
            None => return Err(ListingGlobInvalid)
          }
          if escaped != 42 && escaped != 63 && escaped != 92 {
            return Err(ListingGlobInvalid)
          }
          offset = end
          tokens.push(Literal(escaped))
        }
        _ => tokens.push(Literal(scalar))
      }
    }
    if !last {
      tokens.push(Literal(47))
    }
  }
  Ok({ tokens, })
}

///|
fn begin_listing_glob(
  glob : ListingGlob,
  path : String,
  max_units : Int64,
) -> Result[ListingGlobCursor, RowSourceIssue] {
  if max_units < 0L || path.length().to_int64() > max_units {
    return Err(ListingLimit("maximum_path_length"))
  }
  let states = glob.tokens.length() + 1
  let active = Array::make(states, false)
  active[0] = true
  Ok({
    glob,
    path,
    active,
    next: Array::make(states, false),
    offset: 0,
    state: 0,
    transferring: false,
    scalar: 0,
    scalar_end: 0,
    finished: false,
    matched: false,
  })
}

///|
// One work unit per NFA state transition/epsilon check. Repeated terminal
// polls spend zero. No backtracking scan or hidden whole-string comparison.
fn step_listing_glob(
  cursor : ListingGlobCursor,
  allowance : Int,
) -> Result[ListingGlobStep, RowSourceIssue] {
  if cursor.finished {
    return Ok(Complete(cursor.matched, 0))
  }
  if allowance <= 0 {
    return Err(ListingLimit("glob_work"))
  }
  let mut work = 0
  let count = cursor.glob.tokens.length()
  while work < allowance {
    let state = cursor.state
    work += 1
    if !cursor.transferring {
      if state < count && cursor.active[state] {
        match cursor.glob.tokens[state] {
          Many | DeepTail => cursor.active[state + 1] = true
          DeepBoundary | OptionalDeepBoundary => cursor.active[state + 2] = true
          _ => ()
        }
      }
      cursor.state += 1
      if cursor.state == count + 1 {
        if cursor.offset == cursor.path.length() {
          cursor.finished = true
          cursor.matched = cursor.active[count]
          return Ok(Complete(cursor.matched, work))
        }
        let (scalar, end) = match listing_scalar(cursor.path, cursor.offset) {
          Some(value) => value
          None => return Err(ListingGlobInvalid)
        }
        cursor.scalar = scalar
        cursor.scalar_end = end
        cursor.state = 0
        cursor.transferring = true
      }
    } else {
      if state < count && cursor.active[state] {
        match cursor.glob.tokens[state] {
          Literal(value) =>
            if cursor.scalar == value {
              cursor.next[state + 1] = true
            }
          One => if cursor.scalar != 47 { cursor.next[state + 1] = true }
          Many => if cursor.scalar != 47 { cursor.next[state] = true }
          DeepBoundary =>
            cursor.next[if cursor.scalar == 47 { state } else { state + 1 }] = true
          DeepBody =>
            cursor.next[if cursor.scalar == 47 { state - 1 } else { state }] = true
          DeepTail => cursor.next[state] = true
          OptionalDeepBoundary =>
            if cursor.scalar == 47 {
              cursor.next[state + 1] = true
            }
        }
      }
      cursor.active[state] = false
      cursor.state += 1
      if cursor.state == count + 1 {
        let old = cursor.active
        cursor.active = cursor.next
        cursor.next = old
        cursor.offset = cursor.scalar_end
        cursor.state = 0
        cursor.transferring = false
      }
    }
  }
  Ok(Continue(work))
}

///|
fn cancel_listing_glob(cursor : ListingGlobCursor) -> Unit {
  cursor.path = ""
  cursor.active.clear()
  cursor.next.clear()
  cursor.finished = true
  cursor.matched = false
}
