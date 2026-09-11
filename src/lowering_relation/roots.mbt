///|
/// Location sidecars for the very same expressions emitted in the step graph.
/// Not a sealed fragment: canonical source and demand evidence remain to bind.
struct RootIndex {
  sequence : PreparedSequence
  entries : Array[ExpressionRoot]
}

///|
pub struct ExpressionRoot {
  step_index : Int
  step_id : String
  parameter_pointer : String
  expression : Expression
}

///|
pub(all) struct RootLimits {
  max_roots : Int
  max_pointer_bytes : Int
  max_work : Int
}

///|
pub(all) enum RootIssue {
  InvalidRootLimits
  RootLimit
}

///|
pub fn root_count(index : RootIndex) -> Int {
  index.entries.length()
}

///|
pub fn root_at(index : RootIndex, i : Int) -> ExpressionRoot? {
  index.entries.get(i)
}

///|
pub fn root_sequence(index : RootIndex) -> PreparedSequence {
  index.sequence
}

///|
// RFC6901 escaping changes sort order: '/' precedes 'a', but '~1' follows it.
// Budget UTF-8 bytes before constructing the escaped pointer.
fn root_pointer(name : String, available : Int) -> String? {
  if available < 7 || name.length() > available - 7 {
    return None
  }
  let mut bytes = 7
  for c in name {
    let n = c.to_int()
    let size = if c == '~' || c == '/' {
      2
    } else if n <= 0x7f {
      1
    } else if n <= 0x7ff {
      2
    } else if n <= 0xffff {
      3
    } else {
      4
    }
    if size > available - bytes {
      return None
    }
    bytes += size
  }
  let out = StringBuilder()
  out.write_string("/exprs/")
  for c in name {
    match c {
      '~' => out.write_string("~0")
      '/' => out.write_string("~1")
      _ => out.write_char(c)
    }
  }
  Some(out.to_string())
}

///|
pub fn prepare_roots(
  sequence : PreparedSequence,
  limits : RootLimits,
) -> Result[RootIndex, RootIssue] {
  if limits.max_roots < 0 || limits.max_pointer_bytes < 0 || limits.max_work < 0 {
    return Err(InvalidRootLimits)
  }
  let mut work = limits.max_work
  let mut bytes = limits.max_pointer_bytes
  let mut sorted : Array[ExpressionRoot] = []
  for step_index = 0
      step_index < sequence.steps.length()
      step_index = step_index + 1 {
    if work == 0 {
      return Err(RootLimit)
    }
    work -= 1
    let bindings = match sequence.steps[step_index] {
      ValuesStep(_) => continue
      RowStep(kernel) =>
        match kernel.body {
          Select(_) => continue
          Filter(expr) => {
            if sorted.length() == limits.max_roots || bytes < 5 || work < 6 {
              return Err(RootLimit)
            }
            bytes -= 5
            work -= 6
            sorted.push({
              step_index,
              step_id: sequence.owner.prepared.nodes[step_index].id,
              parameter_pointer: "/expr",
              expression: expr,
            })
            continue
          }
          SnapshotMap(bindings) => bindings
        }
    }
    if bindings.length() > limits.max_roots - sorted.length() {
      return Err(RootLimit)
    }
    for (name, expr) in bindings {
      // A scan is charged even if the subsequent pointer byte ceiling fails.
      if work == 0 || name.length() > work - 1 {
        return Err(RootLimit)
      }
      work -= 1 + name.length()
      guard root_pointer(name, bytes) is Some(pointer) else {
        return Err(RootLimit)
      }
      let size = @utf8.encode(pointer).length()
      if size > work {
        return Err(RootLimit)
      }
      work -= size
      bytes -= size
      sorted.push({
        step_index,
        step_id: sequence.owner.prepared.nodes[step_index].id,
        parameter_pointer: pointer,
        expression: expr,
      })
    }
  }
  // Bounded bottom-up merge: sorting never changes the row evaluation order.
  // At most two root-reference arrays coexist; each is bounded by max_roots.
  let mut width = 1
  while width < sorted.length() {
    let next : Array[ExpressionRoot] = []
    let mut start = 0
    while start < sorted.length() {
      let middle = start + Int::min(width, sorted.length() - start)
      let end = middle + Int::min(width, sorted.length() - middle)
      let mut left = start
      let mut right = middle
      while left < middle || right < end {
        if work == 0 {
          return Err(RootLimit)
        }
        work -= 1
        let take_left = if left == middle {
          false
        } else if right == end {
          true
        } else if sorted[left].step_index != sorted[right].step_index {
          sorted[left].step_index < sorted[right].step_index
        } else {
          for
            pointer in [
              sorted[left].parameter_pointer,
              sorted[right].parameter_pointer,
            ] {
            if pointer.length() > work {
              return Err(RootLimit)
            }
            work -= pointer.length()
          }
          @canonical.compare_utf16(
            sorted[left].parameter_pointer,
            sorted[right].parameter_pointer,
          ) <=
          0
        }
        if take_left {
          next.push(sorted[left])
          left += 1
        } else {
          next.push(sorted[right])
          right += 1
        }
      }
      start = end
    }
    sorted = next
    if width >= sorted.length() - width {
      break
    }
    width += width
  }
  Ok({ sequence, entries: sorted, })
}
