///|
/// Resumable form of the existing stable merge. Structural charges and
/// comparison order match the draining entry point.
priv struct StableOrderExecution[T] {
  table : T
  order : Array[ColumnOrder]
  control : ControlBudget
  workspace : RowWorkspace
  baseline : Int
  count : Int
  comparison : BoundedRowComparison
  mut phase : Int
  mut cursor : Int
  mut source : Array[Int]
  mut target : Array[Int]
  mut width : Int
  mut start : Int
  mut middle : Int
  mut end : Int
  mut left : Int
  mut right : Int
  mut output : Int
  mut merge_charged : Bool
  mut closed : Bool
}

///|
fn[T : IndexedRows] start_stable_order(
  table : T,
  order : Array[ColumnOrder],
  control : ControlBudget,
  workspace : RowWorkspace,
) -> StableOrderExecution[T] {
  {
    table,
    order,
    control,
    workspace,
    baseline: workspace.live,
    count: table.row_count(),
    comparison: {
      left: -1,
      right: -1,
      terms: 0,
      term: 0,
      phase: -1,
      offset: 0,
      charge: { offset: 0, next: 0, remaining: 0, },
      tree: None,
    },
    phase: 0,
    cursor: 0,
    source: [],
    target: [],
    width: 1,
    start: 0,
    middle: 0,
    end: 0,
    left: 0,
    right: 0,
    output: 0,
    merge_charged: false,
    closed: false,
  }
}

///|
fn[T] close_stable_order(state : StableOrderExecution[T]) -> Unit {
  if state.closed {
    return
  }
  state.source = []
  state.target = []
  release_slots(state.workspace, state.workspace.live - state.baseline)
  state.closed = true
}

///|
fn[T : IndexedRows] advance_stable_order(
  state : StableOrderExecution[T],
) -> Result[Array[Int]?, OrderingIssue] {
  if state.closed {
    return Err(InvalidInput)
  }
  let result = advance_stable_order_impl(state)
  if result is Err(_) {
    close_stable_order(state)
  }
  result
}

///|
fn[T : IndexedRows] advance_stable_order_impl(
  s : StableOrderExecution[T],
) -> Result[Array[Int]?, OrderingIssue] {
  match s.phase {
    0 => {
      if s.control.remaining < 0 ||
        !workspace_healthy(s.workspace) ||
        s.count < 0 {
        return Err(InvalidInput)
      }
      if !reserve_slots(s.workspace, s.order.length()) {
        return Err(Limit)
      }
      s.phase = 1
    }
    1 =>
      if s.cursor < s.order.length() {
        if !spend_control(s.control, 1) {
          return Err(Limit)
        }
        let column = s.order[s.cursor].column
        if column < 0 || column >= s.table.column_count() {
          return Err(InvalidInput)
        }
        s.cursor += 1
      } else {
        s.cursor = 0
        s.phase = 2
      }
    2 =>
      if s.cursor < s.count {
        if !spend_control(s.control, 1) {
          return Err(Limit)
        }
        if s.table.row_width(s.cursor) != s.table.column_count() {
          return Err(InvalidInput)
        }
        s.cursor += 1
      } else {
        if s.control.remaining < s.count || !reserve_slots(s.workspace, s.count) {
          return Err(Limit)
        }
        s.phase = 3
      }
    3 =>
      if s.source.length() < s.count {
        if !spend_control(s.control, 1) {
          return Err(Limit)
        }
        s.source.push(s.source.length())
      } else if s.count < 2 || s.order.is_empty() {
        s.phase = 7
      } else {
        if s.control.remaining < s.count || !reserve_slots(s.workspace, s.count) {
          return Err(Limit)
        }
        s.phase = 4
      }
    4 =>
      if s.target.length() < s.count {
        if !spend_control(s.control, 1) {
          return Err(Limit)
        }
        s.target.push(0)
      } else {
        s.phase = 5
      }
    5 =>
      if s.width >= s.count {
        s.phase = 7
      } else if s.start >= s.count {
        let previous = s.source
        s.source = s.target
        s.target = previous
        s.start = 0
        s.width = if s.width > s.count / 2 { s.count } else { s.width * 2 }
      } else {
        s.middle = s.start + Int::min(s.width, s.count - s.start)
        s.end = s.middle + Int::min(s.width, s.count - s.middle)
        s.left = s.start
        s.right = s.middle
        s.output = s.start
        s.phase = 6
      }
    6 => {
      if s.output == s.end {
        s.start = s.end
        s.phase = 5
        return Ok(None)
      }
      if !s.merge_charged {
        if !spend_control(s.control, 1) {
          return Err(Limit)
        }
        s.merge_charged = true
        return Ok(None)
      }
      let choose_left = if s.left == s.middle {
        false
      } else if s.right == s.end {
        true
      } else {
        match
          bounded_row_comparison_step_with(
            s.comparison,
            s.order,
            s.control,
            (row, column) => Some(s.table.read_cell(row, column)),
            s.source[s.left],
            s.source[s.right],
            s.order.length(),
          ) {
          Err(issue) => return Err(issue)
          Ok(None) => return Ok(None)
          Ok(Some(value)) => value <= 0
        }
      }
      if choose_left {
        s.target[s.output] = s.source[s.left]
        s.left += 1
      } else {
        s.target[s.output] = s.source[s.right]
        s.right += 1
      }
      s.output += 1
      s.merge_charged = false
    }
    7 => {
      release_slots(s.workspace, s.workspace.live - s.baseline - s.count)
      s.target = []
      s.closed = true
      return Ok(Some(s.source))
    }
    _ => return Err(InvalidInput)
  }
  Ok(None)
}
