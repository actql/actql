///|
/// Collect direct aggregate contributors one source position at a time.
/// The enclosing group owns the transferred values and their reservations.
priv struct AggregateDirectCollection[T] {
  input : T
  indices : Array[Int]
  range : AggregateGroupRange
  argument : Int?
  function : @relation.AggregateFunction
  control : ControlBudget
  workspace : RowWorkspace
  baseline : Int
  values : Array[Value]
  mut count : Int
  mut position : Int
  mut closed : Bool
}

///|
fn[T] start_aggregate_direct_collection(
  input : T,
  indices : Array[Int],
  range : AggregateGroupRange,
  argument : Int?,
  function : @relation.AggregateFunction,
  control : ControlBudget,
  workspace : RowWorkspace,
) -> AggregateDirectCollection[T] {
  {
    input,
    indices,
    range,
    argument,
    function,
    control,
    workspace,
    baseline: workspace.live,
    values: [],
    count: 0,
    position: range.start,
    closed: false,
  }
}

///|
fn[T] close_aggregate_direct_collection(
  state : AggregateDirectCollection[T],
) -> Unit {
  if state.closed {
    return
  }
  state.values.clear()
  release_slots(state.workspace, state.workspace.live - state.baseline)
  state.closed = true
}

///|
fn[T : IndexedRows] advance_aggregate_direct_collection(
  state : AggregateDirectCollection[T],
) -> Result[(Array[Value], Int)?, RowIssue] {
  if state.closed {
    return Err(InvalidRows)
  }
  let result = advance_aggregate_direct_collection_impl(state)
  if result is Err(_) {
    close_aggregate_direct_collection(state)
  }
  result
}

///|
fn[T : IndexedRows] advance_aggregate_direct_collection_impl(
  state : AggregateDirectCollection[T],
) -> Result[(Array[Value], Int)?, RowIssue] {
  if state.position == state.range.end {
    state.closed = true
    return Ok(Some((state.values, state.count)))
  }
  if state.position < state.range.start ||
    state.position > state.range.end ||
    state.position < 0 ||
    state.position >= state.indices.length() ||
    !spend_control(state.control, 1) {
    return Err(RowLimit)
  }
  let value = match state.argument {
    None => Null
    Some(column) =>
      IndexedRows::read_cell(state.input, state.indices[state.position], column)
  }
  match state.function {
    @relation.Count =>
      if state.argument is None {
        state.count += 1
      } else if !(value is Null) {
        if !reserve_slots(state.workspace, 1) {
          return Err(RowLimit)
        }
        state.values.push(value)
      }
    @relation.CountIf =>
      match value {
        Boolean(true) => state.count += 1
        Boolean(false) | Null => ()
        _ => return Err(InvalidRows)
      }
    @relation.Sum
    | @relation.Avg
    | @relation.Min
    | @relation.Max
    | @relation.PercentileDisc
    | @relation.PercentileCont
    | @relation.VarPop
    | @relation.VarSamp
    | @relation.StddevPop
    | @relation.StddevSamp =>
      if !(value is Null) {
        if !reserve_slots(state.workspace, 1) {
          return Err(RowLimit)
        }
        state.values.push(value)
      }
    _ => return Err(InvalidRows)
  }
  state.position += 1
  Ok(None)
}
