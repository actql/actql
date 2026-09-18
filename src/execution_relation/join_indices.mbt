///|
/// Physical row coordinates only. Owning checked ports, cardinality evidence,
/// value admission and output publication remain the caller's responsibility.
priv enum JoinIndexIssue {
  InvalidInput
  Limit
  NullKey(left~ : Bool, row~ : Int, key~ : Int)
  DuplicateKey(left~ : Bool, row~ : Int, previous~ : Int)
  Scalar(ScalarIssue)
}

///|
priv struct JoinPair {
  left : Int?
  right : Int?
}

///|
/// Verify a side's non-NULL equality tuples. Sorted coordinates preserve the
/// first occurrence in each tuple; choose the earliest duplicate in original
/// input order, rather than reporting whichever key sorts first. The caller
/// selects this obligation from checked cardinality evidence, never estimates.
fn[T : IndexedRows] validate_join_unique_indices(
  input : T,
  order : Array[ColumnOrder],
  left : Bool,
  control : ControlBudget,
  workspace : RowWorkspace,
) -> Result[Unit, JoinIndexIssue] {
  if order.is_empty() {
    return Err(InvalidInput)
  }
  let indices = match stable_order_indices(input, order, control, workspace) {
    Ok(v) => v
    Err(InvalidInput) => return Err(InvalidInput)
    Err(Limit) => return Err(Limit)
    Err(Scalar(e)) => return Err(Scalar(e))
  }
  let check = fn() -> Result[Unit, JoinIndexIssue] {
    let mut first : Int? = None
    let mut duplicate : (Int, Int)? = None
    for row in indices {
      if !spend_control(control, 1) {
        return Err(Limit)
      }
      let mut nullable = false
      for term in order {
        if !spend_control(control, 1) {
          return Err(Limit)
        }
        if input.read_cell(row, term.column) is Null {
          nullable = true
          break
        }
      }
      if nullable {
        continue
      }
      if first is Some(previous) {
        let c = match
          compare_row_indices(input, previous, row, order, control) {
          Ok(c) => c
          Err(InvalidInput) => return Err(InvalidInput)
          Err(Limit) => return Err(Limit)
          Err(Scalar(e)) => return Err(Scalar(e))
        }
        if c == 0 {
          if duplicate is None || row < duplicate.unwrap().0 {
            duplicate = Some((row, previous))
          }
          continue
        }
      }
      first = Some(row)
    }
    match duplicate {
      Some((row, previous)) => Err(DuplicateKey(left~, row~, previous~))
      None => Ok(())
    }
  }
  let result = check()
  release_slots(workspace, indices.length())
  result
}

///|
fn[L : IndexedRows, R : IndexedRows] compare_join_indices(
  left : L,
  lrow : Int,
  right : R,
  rrow : Int,
  keys : Array[(Int, Int)],
  control : ControlBudget,
) -> Result[Int, JoinIndexIssue] {
  for (lc, rc) in keys {
    if !spend_control(control, 1) {
      return Err(Limit)
    }
    let l = left.read_cell(lrow, lc)
    let r = right.read_cell(rrow, rc)
    match charge_comparison_pair(control, l, r) {
      Ok(_) => ()
      Err(ComparisonChargeLimit) => return Err(Limit)
      Err(ComparisonChargeInvalidOperand) =>
        return Err(Scalar(InvalidOperand))
    }
    let c = match (l, r) {
      (Null, Null) => 0
      (Null, _) => -1
      (_, Null) => 1
      _ =>
        match compare(l, r) {
          Ok(c) => c
          Err(e) => return Err(Scalar(e))
        }
    }
    if c != 0 {
      return Ok(c)
    }
  }
  Ok(0)
}

///|
fn[T : IndexedRows] validate_join_index_input(
  input : T,
  keys : Array[(Int, Int)],
  left : Bool,
  fail_null : Bool,
  control : ControlBudget,
) -> Result[Unit, JoinIndexIssue] {
  for row in 0..<input.row_count() {
    if !spend_control(control, 1) {
      return Err(Limit)
    }
    if input.row_width(row) != input.column_count() {
      return Err(InvalidInput)
    }
    if fail_null {
      for key, (lc, rc) in keys {
        if !spend_control(control, 1) {
          return Err(Limit)
        }
        if input.read_cell(row, if left { lc } else { rc }) is Null {
          return Err(NullKey(left~, row~, key~))
        }
      }
    }
  }
  Ok(())
}

///|
/// Stable right index plus a lower-bound lookup for each left row. Equal right
/// keys retain input order. No input row is copied and no content hash replaces
/// scalar equality (in particular decimal equality across scales).
/// On success the returned pair coordinates occupy two slots each; all scratch
/// is released. On failure all allocations from this invocation are released,
/// but spent comparison/search work is never refunded.
fn[L : IndexedRows, R : IndexedRows] inner_join_indices(
  left : L,
  right : R,
  keys : Array[(Int, Int)],
  fail_null : Bool,
  max_output_rows : Int,
  control : ControlBudget,
  workspace : RowWorkspace,
) -> Result[Array[(Int, Int)], JoinIndexIssue] {
  if keys.is_empty() ||
    max_output_rows < 0 ||
    control.remaining < 0 ||
    workspace.live < 0 ||
    workspace.live > workspace.limit ||
    workspace.peak < workspace.live {
    return Err(InvalidInput)
  }
  let baseline = workspace.live
  let mut kept = 0
  let run = fn() -> Result[Array[(Int, Int)], JoinIndexIssue] {
    if !reserve_slots(workspace, keys.length()) ||
      !spend_control(control, keys.length()) {
      return Err(Limit)
    }
    let order : Array[ColumnOrder] = []
    for (lc, rc) in keys {
      if lc < 0 ||
        lc >= left.column_count() ||
        rc < 0 ||
        rc >= right.column_count() {
        return Err(InvalidInput)
      }
      order.push({ column: rc, descending: false, nulls_first: true, })
    }
    // Both inputs are checked even when the opposite input is empty.
    if validate_join_index_input(left, keys, true, fail_null, control) is Err(e) {
      return Err(e)
    }
    if validate_join_index_input(right, keys, false, fail_null, control)
      is Err(e) {
      return Err(e)
    }
    let indices = match stable_order_indices(right, order, control, workspace) {
      Ok(v) => v
      Err(InvalidInput) => return Err(InvalidInput)
      Err(Limit) => return Err(Limit)
      Err(Scalar(e)) => return Err(Scalar(e))
    }
    let output : Array[(Int, Int)] = []
    for lrow in 0..<left.row_count() {
      if !spend_control(control, 1) {
        return Err(Limit)
      }
      let mut null_key = false
      for (lc, _) in keys {
        if !spend_control(control, 1) {
          return Err(Limit)
        }
        if left.read_cell(lrow, lc) is Null {
          null_key = true
          break
        }
      }
      if null_key {
        continue
      }
      let mut low = 0
      let mut high = indices.length()
      while low < high {
        let middle = low + (high - low) / 2
        let c = match
          compare_join_indices(
            left,
            lrow,
            right,
            indices[middle],
            keys,
            control,
          ) {
          Ok(c) => c
          Err(e) => return Err(e)
        }
        if c > 0 {
          low = middle + 1
        } else {
          high = middle
        }
      }
      for position = low; position < indices.length(); position = position + 1 {
        let rrow = indices[position]
        let c = match
          compare_join_indices(left, lrow, right, rrow, keys, control) {
          Ok(c) => c
          Err(e) => return Err(e)
        }
        if c != 0 {
          break
        }
        if output.length() >= max_output_rows ||
          !spend_control(control, 1) ||
          !reserve_slots(workspace, 2) {
          return Err(Limit)
        }
        kept += 2
        output.push((lrow, rrow))
      }
    }
    Ok(output)
  }
  let result = run()
  let retained = match result {
    Ok(_) => kept
    Err(_) => 0
  }
  release_slots(workspace, workspace.live - baseline - retained)
  result
}

///|
/// Determine only whether each left row has a matching right occurrence. This
/// avoids materializing the right-side multiplicity for semi and anti joins.
fn[L : IndexedRows, R : IndexedRows] join_left_match_flags(
  left : L,
  right : R,
  keys : Array[(Int, Int)],
  control : ControlBudget,
  workspace : RowWorkspace,
) -> Result[Array[Bool], JoinIndexIssue] {
  if keys.is_empty() ||
    control.remaining < 0 ||
    workspace.live < 0 ||
    workspace.live > workspace.limit ||
    workspace.peak < workspace.live {
    return Err(InvalidInput)
  }
  let baseline = workspace.live
  let run = fn() -> Result[Array[Bool], JoinIndexIssue] {
    if !reserve_slots(workspace, keys.length()) ||
      !spend_control(control, keys.length()) {
      return Err(Limit)
    }
    let order : Array[ColumnOrder] = []
    for (lc, rc) in keys {
      if lc < 0 ||
        lc >= left.column_count() ||
        rc < 0 ||
        rc >= right.column_count() {
        return Err(InvalidInput)
      }
      order.push({ column: rc, descending: false, nulls_first: true, })
    }
    if validate_join_index_input(left, keys, true, false, control) is Err(e) {
      return Err(e)
    }
    if validate_join_index_input(right, keys, false, false, control) is Err(e) {
      return Err(e)
    }
    let indices = match stable_order_indices(right, order, control, workspace) {
      Ok(value) => value
      Err(InvalidInput) => return Err(InvalidInput)
      Err(Limit) => return Err(Limit)
      Err(Scalar(e)) => return Err(Scalar(e))
    }
    if !reserve_slots(workspace, left.row_count()) {
      return Err(Limit)
    }
    let matches = Array::make(left.row_count(), false)
    for lrow in 0..<left.row_count() {
      if !spend_control(control, 1) {
        return Err(Limit)
      }
      let mut null_key = false
      for (lc, _) in keys {
        if !spend_control(control, 1) {
          return Err(Limit)
        }
        if left.read_cell(lrow, lc) is Null {
          null_key = true
          break
        }
      }
      if null_key {
        continue
      }
      let mut low = 0
      let mut high = indices.length()
      while low < high {
        let middle = low + (high - low) / 2
        let comparison = match
          compare_join_indices(
            left,
            lrow,
            right,
            indices[middle],
            keys,
            control,
          ) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        if comparison > 0 {
          low = middle + 1
        } else {
          high = middle
        }
      }
      if low < indices.length() {
        matches[lrow] = match
          compare_join_indices(left, lrow, right, indices[low], keys, control) {
          Ok(value) => value == 0
          Err(issue) => return Err(issue)
        }
      }
    }
    release_slots(workspace, indices.length() + keys.length())
    Ok(matches)
  }
  let result = run()
  if result is Err(_) {
    release_slots(workspace, workspace.live - baseline)
  }
  result
}

///|
/// Produce the exact semantic row coordinates for non-inner equality joins.
/// Missing-side coordinates are explicit and never stand in for an input row.
fn[L : IndexedRows, R : IndexedRows] non_inner_join_indices(
  kind : @join.Kind,
  left : L,
  right : R,
  keys : Array[(Int, Int)],
  max_output_rows : Int,
  control : ControlBudget,
  workspace : RowWorkspace,
) -> Result[Array[JoinPair], JoinIndexIssue] {
  if max_output_rows < 0 || kind == @join.Inner {
    return Err(InvalidInput)
  }
  let baseline = workspace.live
  if kind == @join.Semi || kind == @join.Anti {
    let matches = match
      join_left_match_flags(left, right, keys, control, workspace) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let output : Array[JoinPair] = []
    for row, matched in matches {
      if matched == (kind == @join.Semi) {
        if output.length() >= max_output_rows ||
          !spend_control(control, 1) ||
          !reserve_slots(workspace, 2) {
          release_slots(workspace, workspace.live - baseline)
          return Err(Limit)
        }
        output.push({ left: Some(row), right: None, })
      }
    }
    release_slots(workspace, matches.length())
    return Ok(output)
  }
  let pairs = match
    inner_join_indices(
      left, right, keys, false, max_output_rows, control, workspace,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let right_matches = if kind == @join.Full {
    if !reserve_slots(workspace, right.row_count()) {
      release_slots(workspace, workspace.live - baseline)
      return Err(Limit)
    }
    Some(Array::make(right.row_count(), false))
  } else {
    None
  }
  let output : Array[JoinPair] = []
  let mut cursor = 0
  let append = fn(left : Int?, right : Int?) -> Bool {
    if output.length() >= max_output_rows ||
      !spend_control(control, 1) ||
      !reserve_slots(workspace, 2) {
      return false
    }
    output.push({ left, right, })
    true
  }
  for lrow in 0..<left.row_count() {
    let start = cursor
    while cursor < pairs.length() && pairs[cursor].0 == lrow {
      let rrow = pairs[cursor].1
      if right_matches is Some(flags) {
        flags[rrow] = true
      }
      if !append(Some(lrow), Some(rrow)) {
        release_slots(workspace, workspace.live - baseline)
        return Err(Limit)
      }
      cursor += 1
    }
    if cursor == start && !append(Some(lrow), None) {
      release_slots(workspace, workspace.live - baseline)
      return Err(Limit)
    }
  }
  if right_matches is Some(flags) {
    for rrow, matched in flags {
      if !matched && !append(None, Some(rrow)) {
        release_slots(workspace, workspace.live - baseline)
        return Err(Limit)
      }
    }
  }
  release_slots(
    workspace,
    pairs.length() * 2 + right_matches.map(flags => flags.length()).unwrap_or(0),
  )
  Ok(output)
}
