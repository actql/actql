///|
priv enum Phase {
  Initialize
  PrepareRun
  MergeRun
  Finished
} derive(Eq)

///|
struct Sort {
  keys : Array[Array[String]]
  validation_arity : Int?
  mut source : Array[Int]
  mut target : Array[Int]
  mut phase : Phase
  mut index : Int
  mut width : Int
  mut start : Int
  mut middle : Int
  mut end : Int
  mut left : Int
  mut right : Int
  mut output : Int
  mut comparison_component : Int
  mut comparison_offset : Int
}

///|
pub(all) enum Issue {
  InvalidLimits
  InvalidKey
  WorkspaceLimit
  Terminal
} derive(Eq, Debug)

///|
pub enum Poll {
  Continue(progress~ : Int64, work~ : Int64)
  Complete(progress~ : Int64, work~ : Int64)
}

///|
fn checked_multiply(left : Int, right : Int) -> Int? {
  if left < 0 || right < 0 || (left != 0 && right > 2147483647 / left) {
    None
  } else {
    Some(left * right)
  }
}

///|
/// Eagerly validate every key shape before returning. Bounded callers must use
/// prepare_deferred so validation advances within the supplied work quantum.
pub fn prepare(
  keys : Array[Array[String]],
  max_workspace_slots : Int,
) -> Result[Sort, Issue] {
  if max_workspace_slots < 0 {
    return Err(InvalidLimits)
  }
  let arity = if keys.is_empty() { 1 } else { keys[0].length() }
  if arity < 1 || keys.any(key => key.length() != arity) {
    return Err(InvalidKey)
  }
  prepare_sort(keys, max_workspace_slots, None)
}

///|
/// Retain the existing sorter without a synchronous all-key shape scan. Shape
/// admission remains pending until Initialize visits every key. Completion,
/// never preparation alone, establishes a valid sorted index.
pub fn prepare_deferred(
  keys : Array[Array[String]],
  max_workspace_slots : Int,
) -> Result[Sort, Issue] {
  if max_workspace_slots < 0 {
    return Err(InvalidLimits)
  }
  let arity = if keys.is_empty() { 1 } else { keys[0].length() }
  if arity < 1 {
    return Err(InvalidKey)
  }
  prepare_sort(keys, max_workspace_slots, Some(arity))
}

///|
fn prepare_sort(
  keys : Array[Array[String]],
  max_workspace_slots : Int,
  validation_arity : Int?,
) -> Result[Sort, Issue] {
  guard checked_multiply(keys.length(), 2) is Some(required) else {
    return Err(WorkspaceLimit)
  }
  if required > max_workspace_slots {
    return Err(WorkspaceLimit)
  }
  Ok({
    keys,
    validation_arity,
    source: [],
    target: [],
    phase: Initialize,
    index: 0,
    width: 1,
    start: 0,
    middle: 0,
    end: 0,
    left: 0,
    right: 0,
    output: 0,
    comparison_component: 0,
    comparison_offset: 0,
  })
}

///|
pub fn advance(value : Sort, quantum : Int) -> Result[Poll, Issue] {
  if quantum < 1 {
    return Err(InvalidLimits)
  }
  if value.phase == Finished {
    return Err(Terminal)
  }
  let mut work = 0
  let mut progress = 0
  while work < quantum {
    match value.phase {
      Initialize => {
        if value.index == value.keys.length() {
          value.index = 0
          if value.source.length() < 2 {
            value.phase = Finished
            return Ok(
              Complete(progress=progress.to_int64(), work=work.to_int64()),
            )
          }
          value.phase = PrepareRun
          continue
        }
        if value.validation_arity is Some(arity) &&
          value.keys[value.index].length() != arity {
          return Err(InvalidKey)
        }
        value.source.push(value.index)
        value.target.push(0)
        value.index += 1
        work += 1
        progress += 1
      }
      PrepareRun => {
        if value.width >= value.source.length() {
          value.phase = Finished
          return Ok(
            Complete(progress=progress.to_int64(), work=work.to_int64()),
          )
        }
        if value.start >= value.source.length() {
          let previous = value.source
          value.source = value.target
          value.target = previous
          value.start = 0
          value.width = if value.width > value.source.length() / 2 {
            value.source.length()
          } else {
            value.width * 2
          }
          work += 1
          progress += 1
          continue
        }
        value.middle = value.start +
          Int::min(value.width, value.source.length() - value.start)
        value.end = value.middle +
          Int::min(value.width, value.source.length() - value.middle)
        value.left = value.start
        value.right = value.middle
        value.output = value.start
        value.phase = MergeRun
        work += 1
      }
      MergeRun => {
        if value.output == value.end {
          value.start = value.end
          value.phase = PrepareRun
          continue
        }
        let choose_left = if value.left == value.middle {
          false
        } else if value.right == value.end {
          true
        } else {
          let left = value.source[value.left]
          let right = value.source[value.right]
          let lhs = value.keys[left]
          let rhs = value.keys[right]
          guard !lhs.is_empty() &&
            lhs.length() == rhs.length() &&
            lhs.get(value.comparison_component) is Some(a) &&
            rhs.get(value.comparison_component) is Some(b) else {
            return Err(InvalidKey)
          }
          let (compared, offset, _) = @canonical.compare_utf16_fragment(
            a,
            b,
            value.comparison_offset,
            64,
          )
          value.comparison_offset = offset
          match compared {
            None => {
              work += 1
              continue
            }
            Some(0) if value.comparison_component + 1 < lhs.length() => {
              value.comparison_component += 1
              work += 1
              continue
            }
            Some(compared) => compared <= 0
          }
        }
        value.comparison_component = 0
        value.comparison_offset = 0
        if choose_left {
          value.target[value.output] = value.source[value.left]
          value.left += 1
        } else {
          value.target[value.output] = value.source[value.right]
          value.right += 1
        }
        value.output += 1
        work += 1
        progress += 1
      }
      Finished => return Err(Terminal)
    }
  }
  Ok(Continue(progress=progress.to_int64(), work=work.to_int64()))
}

///|
pub fn count(value : Sort) -> Int {
  if value.phase == Finished {
    value.source.length()
  } else {
    0
  }
}

///|
pub fn index_at(value : Sort, index : Int) -> Int? {
  if value.phase != Finished {
    None
  } else {
    value.source.get(index)
  }
}

///|
pub fn key_component_at(value : Sort, index : Int, component : Int) -> String? {
  guard value.phase == Finished &&
    value.source.get(index) is Some(source) &&
    value.keys.get(source) is Some(key) else {
    return None
  }
  key.get(component)
}

///|
pub fn cleanup(value : Sort) -> Bool {
  value.source.clear()
  value.target.clear()
  value.comparison_component = 0
  value.comparison_offset = 0
  true
}
