///|
/// A resumable bottom-up stable merge sort. Each advance performs one copy
/// or one comparator step; the comparator pays at most one control unit per
/// step and returns `None` until its comparison is decided. Every pass writes
/// its output in order, so no advance initializes a whole array.
priv struct AggregateMergeSort[T] {
  compare : (T, T) -> Result[Int?, RowIssue]
  count : Int
  mut source : Array[T]
  mut target : Array[T]
  mut input : Array[T]
  mut phase : Int
  mut width : Int
  mut start : Int
  mut middle : Int
  mut end : Int
  mut left : Int
  mut right : Int
  mut closed : Bool
}

///|
fn[T] start_aggregate_merge_sort(
  items : Array[T],
  compare : (T, T) -> Result[Int?, RowIssue],
) -> AggregateMergeSort[T] {
  {
    compare,
    count: items.length(),
    source: [],
    target: [],
    input: items,
    phase: 0,
    width: 1,
    start: 0,
    middle: 0,
    end: 0,
    left: 0,
    right: 0,
    closed: false,
  }
}

///|
fn[T] close_aggregate_merge_sort(state : AggregateMergeSort[T]) -> Unit {
  state.source = []
  state.target = []
  state.input = []
  state.closed = true
}

///|
fn[T] advance_aggregate_merge_sort(
  state : AggregateMergeSort[T],
) -> Result[Array[T]?, RowIssue] {
  if state.closed {
    return Err(InvalidRows)
  }
  let result = advance_aggregate_merge_sort_impl(state)
  match result {
    Err(_) => close_aggregate_merge_sort(state)
    Ok(Some(_)) => state.closed = true
    Ok(None) => ()
  }
  result
}

///|
fn[T] advance_aggregate_merge_sort_impl(
  s : AggregateMergeSort[T],
) -> Result[Array[T]?, RowIssue] {
  match s.phase {
    // Copy the input one element per advance.
    0 => {
      if s.source.length() < s.count {
        s.source.push(s.input[s.source.length()])
        return Ok(None)
      }
      s.input = []
      s.phase = if s.count < 2 { 3 } else { 1 }
      Ok(None)
    }
    // Start the next run pair, or finish or swap a pass.
    1 => {
      if s.width >= s.count {
        s.phase = 3
      } else if s.start >= s.count {
        s.source = s.target
        s.target = []
        s.start = 0
        s.width = if s.width > s.count / 2 { s.count } else { s.width * 2 }
      } else {
        s.middle = s.start + Int::min(s.width, s.count - s.start)
        s.end = s.middle + Int::min(s.width, s.count - s.middle)
        s.left = s.start
        s.right = s.middle
        s.phase = 2
      }
      Ok(None)
    }
    // Merge one element of the current run pair.
    2 => {
      if s.left == s.middle && s.right == s.end {
        s.start = s.end
        s.phase = 1
        return Ok(None)
      }
      let take_left = if s.left == s.middle {
        false
      } else if s.right == s.end {
        true
      } else {
        match (s.compare)(s.source[s.left], s.source[s.right]) {
          Err(issue) => return Err(issue)
          Ok(None) => return Ok(None)
          Ok(Some(order)) => order <= 0
        }
      }
      if take_left {
        s.target.push(s.source[s.left])
        s.left += 1
      } else {
        s.target.push(s.source[s.right])
        s.right += 1
      }
      Ok(None)
    }
    _ => Ok(Some(s.source))
  }
}

///|
/// Compare two complete values one bounded step at a time.
fn complete_value_step_comparator(
  control : ControlBudget,
) -> (Value, Value) -> Result[Int?, RowIssue] {
  let cursor = bounded_complete_value_comparison()
  (left, right) => {
    match bounded_complete_value_comparison_step(cursor, left, right, control) {
      Ok(value) => Ok(value)
      Err(issue) => Err(ordering_row_issue(issue))
    }
  }
}

///|
/// Order canonical identity entries by CID: charge both CIDs one UTF-8 byte
/// per advance, then compare them in UTF-16 order.
fn identity_step_comparator(
  control : ControlBudget,
) -> ((String, Double), (String, Double)) -> Result[Int?, RowIssue] {
  let charge : BoundedTextCharge = { offset: 0, next: 0, remaining: 0, }
  let phase = Ref(0)
  (left, right) => {
    match phase.val {
      0 =>
        match advance_bounded_text_charge(charge, control, left.0) {
          Err(_) => Err(RowLimit)
          Ok(false) => Ok(None)
          Ok(true) => {
            reset_bounded_text_charge(charge)
            phase.val = 1
            Ok(None)
          }
        }
      _ =>
        match advance_bounded_text_charge(charge, control, right.0) {
          Err(_) => Err(RowLimit)
          Ok(false) => Ok(None)
          Ok(true) => {
            reset_bounded_text_charge(charge)
            phase.val = 0
            Ok(Some(@canonical.compare_utf16(left.0, right.0)))
          }
        }
    }
  }
}
