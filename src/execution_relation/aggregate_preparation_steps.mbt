///|
/// One owner spans expression collection, aggregate-local ordering, and
/// permutation. Intermediate arrays cannot escape as a completed aggregate.
priv struct AggregatePreparation[T] {
  input : T
  order : Array[ColumnOrder]
  control : ControlBudget
  workspace : RowWorkspace
  baseline : Int
  collector : AggregateContributorExecution[T]
  mut sources : Array[Int]
  mut values : Array[Value]
  mut ordered : Array[Int]
  mut sorter : StableOrderExecution[AggregateContributorRows[T]]?
  mut permutation : AggregatePermutationExecution?
  mut phase : Int
  mut closed : Bool
}

///|
fn[T] start_aggregate_preparation(
  input : T,
  names : Array[String],
  indices : Array[Int],
  range : AggregateGroupRange,
  argument : AggregateInput,
  filter : @lower.Expression?,
  aggregate : Int,
  order : Array[ColumnOrder],
  control : ControlBudget,
  workspace : RowWorkspace,
  scope : ExpressionRoots?,
) -> AggregatePreparation[T] {
  {
    input,
    order,
    control,
    workspace,
    baseline: workspace.live,
    collector: start_aggregate_contributors(
      input, names, indices, range, argument, filter, aggregate, control, workspace,
      scope,
    ),
    sources: [],
    values: [],
    ordered: [],
    sorter: None,
    permutation: None,
    phase: 0,
    closed: false,
  }
}

///|
fn[T] close_aggregate_preparation(state : AggregatePreparation[T]) -> Unit {
  if state.closed {
    return
  }
  if state.permutation is Some(permutation) {
    close_aggregate_permutation(permutation)
  }
  if state.sorter is Some(sorter) {
    close_stable_order(sorter)
  }
  close_aggregate_contributors(state.collector)
  state.sources.clear()
  state.values.clear()
  state.ordered.clear()
  state.sources = []
  state.values = []
  state.ordered = []
  state.sorter = None
  state.permutation = None
  release_slots(state.workspace, state.workspace.live - state.baseline)
  state.closed = true
}

///|
fn[T : IndexedRows] advance_aggregate_preparation(
  state : AggregatePreparation[T],
) -> Result[(Array[Value], Array[Int])?, RowIssue] {
  if state.closed {
    return Err(InvalidRows)
  }
  let result = advance_aggregate_preparation_impl(state)
  if result is Err(_) {
    close_aggregate_preparation(state)
  }
  result
}

///|
fn[T : IndexedRows] advance_aggregate_preparation_impl(
  state : AggregatePreparation[T],
) -> Result[(Array[Value], Array[Int])?, RowIssue] {
  match state.phase {
    0 =>
      match advance_aggregate_contributors(state.collector) {
        Err(issue) => return Err(issue)
        Ok(None) => ()
        Ok(Some((sources, values))) => {
          state.sources = sources
          state.values = values
          state.phase = 1
        }
      }
    1 =>
      if state.order.is_empty() {
        let count = state.values.length()
        if state.control.remaining < count ||
          !reserve_slots(state.workspace, count) {
          return Err(RowLimit)
        }
        state.phase = 2
      } else {
        state.sorter = Some(
          start_stable_order(
            AggregateContributorRows::{
              input: state.input,
              sources: state.sources,
            },
            state.order,
            state.control,
            state.workspace,
          ),
        )
        state.phase = 3
      }
    2 =>
      if state.ordered.length() < state.values.length() {
        if !spend_control(state.control, 1) {
          return Err(RowLimit)
        }
        state.ordered.push(state.ordered.length())
      } else {
        state.phase = 4
      }
    3 => {
      guard state.sorter is Some(sorter) else { return Err(InvalidRows) }
      match advance_stable_order(sorter) {
        Err(issue) => return Err(ordering_row_issue(issue))
        Ok(None) => ()
        Ok(Some(ordered)) => {
          state.ordered = ordered
          state.sorter = None
          state.phase = 4
        }
      }
    }
    4 => {
      state.permutation = Some(
        start_aggregate_permutation(
          state.values,
          state.ordered,
          state.control,
          state.workspace,
        ),
      )
      state.phase = 5
    }
    5 => {
      guard state.permutation is Some(permutation) else {
        return Err(InvalidRows)
      }
      match advance_aggregate_permutation(permutation) {
        Err(issue) => return Err(issue)
        Ok(None) => ()
        Ok(Some(result)) => {
          state.closed = true
          return Ok(Some(result))
        }
      }
    }
    _ => return Err(InvalidRows)
  }
  Ok(None)
}
