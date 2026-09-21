///|
priv enum BoundedIndexSortPhase {
  Initialize
  PrepareRun
  MergeRun
  Terminal
}

///|
priv struct BoundedIndexSortState {
  count : Int
  compare : (Int, Int) -> Result[Int, RowIssue]
  mut phase : BoundedIndexSortPhase
  mut source : Array[Int]
  mut target : Array[Int]
  mut width : Int
  mut start : Int
  mut middle : Int
  mut end : Int
  mut left : Int
  mut right : Int
  mut output : Int
}

///|
priv struct BoundedIndexSort {
  session : @bounded.Session[BoundedIndexSortState, Array[Int], RowIssue]
  mut token : @bounded.Token?
}

///|
priv enum BoundedIndexSortPoll {
  BoundedIndexSortContinue
  BoundedIndexSortComplete(Array[Int])
  BoundedIndexSortFailed(RowIssue)
  BoundedIndexSortStopped(@bounded.StopReason)
}

///|
fn bounded_index_sort_step(
  state : BoundedIndexSortState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[Array[Int], RowIssue] {
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    match state.phase {
      Initialize => {
        if state.source.length() == state.count {
          if state.count < 2 {
            state.phase = Terminal
            return @bounded.Complete(state.source, progress, used)
          }
          state.phase = PrepareRun
          continue
        }
        state.source.push(state.source.length())
        state.target.push(0)
        used += 1
        progress += 1
      }
      PrepareRun => {
        if state.width >= state.count {
          state.phase = Terminal
          return @bounded.Complete(state.source, progress, used)
        }
        if state.start >= state.count {
          let previous = state.source
          state.source = state.target
          state.target = previous
          state.start = 0
          if state.width > state.count / 2 {
            state.width = state.count
          } else {
            state.width *= 2
          }
          used += 1
          progress += 1
          continue
        }
        state.middle = state.start +
          Int::min(state.width, state.count - state.start)
        state.end = state.middle +
          Int::min(state.width, state.count - state.middle)
        state.left = state.start
        state.right = state.middle
        state.output = state.start
        state.phase = MergeRun
        used += 1
      }
      MergeRun => {
        if state.output == state.end {
          state.start = state.end
          state.phase = PrepareRun
          continue
        }
        let choose_left = if state.left == state.middle {
          false
        } else if state.right == state.end {
          true
        } else {
          match
            (state.compare)(state.source[state.left], state.source[state.right]) {
            Ok(value) => value <= 0
            Err(issue) => return @bounded.Failed(issue, progress, used + 1)
          }
        }
        if choose_left {
          state.target[state.output] = state.source[state.left]
          state.left += 1
        } else {
          state.target[state.output] = state.source[state.right]
          state.right += 1
        }
        state.output += 1
        used += 1
        progress += 1
      }
      Terminal => return @bounded.Failed(InvalidRows, progress, used)
    }
  }
  @bounded.Continue(progress, used)
}

///|
fn start_bounded_index_sort(
  control : @bounded.Control,
  count : Int,
  compare : (Int, Int) -> Result[Int, RowIssue],
) -> BoundedIndexSort? {
  if count < 0 {
    return None
  }
  let state : BoundedIndexSortState = {
    count,
    compare,
    phase: Initialize,
    source: [],
    target: [],
    width: 1,
    start: 0,
    middle: 0,
    end: 0,
    left: 0,
    right: 0,
    output: 0,
  }
  let (session, token) = @bounded.start(
    control,
    state,
    bounded_index_sort_step,
    value => {
      value.source = []
      value.target = []
      true
    },
    _ => true,
  )
  Some({ session, token: Some(token), })
}

///|
fn advance_bounded_index_sort(
  value : BoundedIndexSort,
  quantum : Int,
) -> Result[BoundedIndexSortPoll, RowIssue] {
  guard value.token is Some(token) else { return Err(InvalidRows) }
  match @bounded.advance(value.session, token, quantum) {
    Err(_) => Err(InvalidRows)
    Ok(@bounded.ContinueWith(next, ..)) => {
      value.token = Some(next)
      Ok(BoundedIndexSortContinue)
    }
    Ok(@bounded.Completed(indices, ..)) => {
      value.token = None
      Ok(BoundedIndexSortComplete(indices))
    }
    Ok(@bounded.FailedWith(issue, ..)) => {
      value.token = None
      Ok(BoundedIndexSortFailed(issue))
    }
    Ok(@bounded.StoppedWith(reason, ..)) => {
      value.token = None
      Ok(BoundedIndexSortStopped(reason))
    }
  }
}

///|
fn cleanup_bounded_index_sort(value : BoundedIndexSort) -> Bool {
  @bounded.cleanup(value.session).unwrap_or(false)
}
