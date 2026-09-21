///|
pub(all) enum Operation {
  Union
  Difference
} derive(Eq, Debug)

///|
priv enum Phase {
  ReadLeft
  ReadRight
  InitializeSort
  PrepareRun
  MergeRun
  Build
  Finish
}

///|
priv struct State {
  operation : Operation
  contract : @contract.Contract
  item : @contract.Contract
  limits : @value.Limits
  left : @value.CheckedValue
  right : @value.CheckedValue
  values : Map[String, @value.CheckedValue]
  mut phase : Phase
  mut index : Int
  mut source : Array[String]
  mut target : Array[String]
  mut width : Int
  mut start : Int
  mut middle : Int
  mut end : Int
  mut left_index : Int
  mut right_index : Int
  mut output_index : Int
  result : Array[@value.Value]
}

///|
pub(all) enum Issue {
  InvalidSet
  WorkspaceLimit
  ValueLimit
  CompleteOrder(@value.CompleteOrderIssue)
  Execution(@bounded.Issue)
} derive(Eq, Debug)

///|
struct Execution {
  session : @bounded.Session[State, @value.CheckedValue, Issue]
  mut token : @bounded.Token?
  max_noninterruptible_value_nodes : Int
  max_noninterruptible_value_bytes : Int
}

///|
pub enum Poll {
  Continue(progress~ : Int64, work~ : Int64)
  Complete(@value.CheckedValue, progress~ : Int64, work~ : Int64)
  Failed(Issue, progress~ : Int64, work~ : Int64)
  Stopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
fn checked_add(left : Int, right : Int) -> Int? {
  if left < 0 || right < 0 || right > 2147483647 - left {
    None
  } else {
    Some(left + right)
  }
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
fn read_member(
  state : State,
  checked : @value.CheckedValue,
  index : Int,
) -> Result[(@value.CheckedValue, String), Issue] {
  guard checked.value is @value.Array(values) else { return Err(InvalidSet) }
  guard @value.element_at(values, index) is Some(value) &&
    @value.recheck_runtime_value(value, state.item, state.limits)
    is Some(checked) else {
    return Err(ValueLimit)
  }
  @value.complete_order_key(checked, state.limits)
  .map(key => (checked, key))
  .map_err(issue => CompleteOrder(issue))
}

///|
fn step(
  state : State,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[@value.CheckedValue, Issue] {
  let mut work = 0
  let mut progress = 0
  while work < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, work)
    }
    match state.phase {
      ReadLeft => {
        guard state.left.value is @value.Array(left) else {
          return @bounded.Failed(InvalidSet, progress, work)
        }
        if state.index == @value.element_count(left) {
          state.index = 0
          state.phase = ReadRight
          continue
        }
        match read_member(state, state.left, state.index) {
          Err(issue) => return @bounded.Failed(issue, progress, work + 1)
          Ok((value, key)) =>
            if !state.values.contains(key) {
              state.values[key] = value
              state.source.push(key)
            }
        }
        state.index += 1
        work += 1
        progress += 1
      }
      ReadRight => {
        guard state.right.value is @value.Array(right) else {
          return @bounded.Failed(InvalidSet, progress, work)
        }
        if state.index == @value.element_count(right) {
          state.index = 0
          state.phase = InitializeSort
          continue
        }
        match read_member(state, state.right, state.index) {
          Err(issue) => return @bounded.Failed(issue, progress, work + 1)
          Ok((value, key)) =>
            match state.operation {
              Union =>
                if !state.values.contains(key) {
                  state.values[key] = value
                  state.source.push(key)
                }
              Difference => state.values.remove(key)
            }
        }
        state.index += 1
        work += 1
        progress += 1
      }
      InitializeSort => {
        if state.target.length() == state.source.length() {
          if state.source.length() < 2 {
            state.phase = Build
          } else {
            state.phase = PrepareRun
          }
          continue
        }
        state.target.push("")
        work += 1
        progress += 1
      }
      PrepareRun => {
        if state.width >= state.source.length() {
          state.index = 0
          state.phase = Build
          continue
        }
        if state.start >= state.source.length() {
          let previous = state.source
          state.source = state.target
          state.target = previous
          state.start = 0
          if state.width > state.source.length() / 2 {
            state.width = state.source.length()
          } else {
            state.width *= 2
          }
          work += 1
          progress += 1
          continue
        }
        state.middle = state.start +
          Int::min(state.width, state.source.length() - state.start)
        state.end = state.middle +
          Int::min(state.width, state.source.length() - state.middle)
        state.left_index = state.start
        state.right_index = state.middle
        state.output_index = state.start
        state.phase = MergeRun
        work += 1
      }
      MergeRun => {
        if state.output_index == state.end {
          state.start = state.end
          state.phase = PrepareRun
          continue
        }
        let choose_left = if state.left_index == state.middle {
          false
        } else if state.right_index == state.end {
          true
        } else {
          @canonical.compare_utf16(
            state.source[state.left_index],
            state.source[state.right_index],
          ) <=
          0
        }
        if choose_left {
          state.target[state.output_index] = state.source[state.left_index]
          state.left_index += 1
        } else {
          state.target[state.output_index] = state.source[state.right_index]
          state.right_index += 1
        }
        state.output_index += 1
        work += 1
        progress += 1
      }
      Build => {
        if state.index == state.source.length() {
          state.phase = Finish
          continue
        }
        let key = state.source[state.index]
        if state.values.get(key) is Some(value) {
          state.result.push(value.value)
        }
        state.index += 1
        work += 1
        progress += 1
      }
      Finish =>
        match
          @value.recheck_runtime_value(
            @value.array_value(state.result),
            state.contract,
            state.limits,
          ) {
          Some(value) => return @bounded.Complete(value, progress, work + 1)
          None => return @bounded.Failed(ValueLimit, progress, work + 1)
        }
    }
  }
  @bounded.Continue(progress, work)
}

///|
fn cleanup_state(state : State) -> Bool {
  state.values.clear()
  state.source.clear()
  state.target.clear()
  state.result.clear()
  true
}

///|
pub fn start(
  control : @bounded.Control,
  operation : Operation,
  left : @value.CheckedValue,
  right : @value.CheckedValue,
  contract : @contract.Contract,
  limits : @value.Limits,
  workspace_slots : Int,
) -> Result[Execution, Issue] {
  guard contract.shape is @contract.Array(item, ..) &&
    left.value is @value.Array(left_values) &&
    right.value is @value.Array(right_values) else {
    return Err(InvalidSet)
  }
  let left_count = @value.element_count(left_values)
  let right_count = @value.element_count(right_values)
  guard checked_add(left_count, right_count) is Some(count) &&
    checked_multiply(count, 8) is Some(slots) &&
    checked_add(slots, 8) is Some(slots) &&
    slots <= workspace_slots else {
    return Err(WorkspaceLimit)
  }
  guard checked_multiply(limits.max_nodes, 4) is Some(node_work) &&
    checked_add(node_work, 4) is Some(node_work) &&
    checked_multiply(limits.max_text_bytes, 6) is Some(text_bytes) &&
    checked_multiply(limits.max_nodes, 96) is Some(structural_bytes) &&
    checked_add(structural_bytes, 128) is Some(structural_bytes) &&
    checked_add(text_bytes, structural_bytes) is Some(order_bytes) else {
    return Err(InvalidSet)
  }
  let state : State = {
    operation,
    contract,
    item,
    limits,
    left,
    right,
    values: Map([]),
    phase: ReadLeft,
    index: 0,
    source: [],
    target: [],
    width: 1,
    start: 0,
    middle: 0,
    end: 0,
    left_index: 0,
    right_index: 0,
    output_index: 0,
    result: [],
  }
  let (session, token) = @bounded.start(control, state, step, cleanup_state, _ => {
    true
  })
  Ok({
    session,
    token: Some(token),
    max_noninterruptible_value_nodes: node_work,
    max_noninterruptible_value_bytes: order_bytes,
  })
}

///|
pub fn advance(value : Execution, quantum : Int) -> Result[Poll, Issue] {
  guard value.token is Some(token) else {
    return Err(Execution(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(Execution(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(Continue(progress~, work~))
    }
    Ok(@bounded.Completed(result, progress~, work~)) => {
      value.token = None
      Ok(Complete(result, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(Failed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(Stopped(reason, progress~, work~))
    }
  }
}

///|
pub fn stopped(value : Execution) -> Bool {
  @bounded.session_stopped(value.session)
}

///|
pub fn cleanup_pending(value : Execution) -> Bool {
  @bounded.cleanup_pending(value.session)
}

///|
pub fn cleanup(value : Execution) -> Result[Bool, Issue] {
  @bounded.cleanup(value.session).map_err(issue => Execution(issue))
}

///|
pub fn max_noninterruptible_value_nodes(value : Execution) -> Int {
  value.max_noninterruptible_value_nodes
}

///|
pub fn max_noninterruptible_value_bytes(value : Execution) -> Int {
  value.max_noninterruptible_value_bytes
}
