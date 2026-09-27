///|
/// Run a selected common numeric reduction for one aggregate occurrence.
/// Contributors are copied one per advance, the Host-owned reduction step
/// advances one call at a time, and its reported work is then paid one
/// control unit per advance, as the atomic direct aggregate charged it.
/// Without a step form the selected reduction runs in one advance; product
/// Local execution installs the step form.
priv struct AggregateNumeric {
  values : Array[Value]
  execution : NumericAggregateExecution
  step : Int
  name : String
  occurrence : Int
  control : ControlBudget
  workspace : RowWorkspace
  contributors : Array[Double]
  pending : PendingUnits
  mut reduction : NumericAggregateStep?
  mut outcome : @numeric.Outcome?
  mut phase : Int
  mut index : Int
  mut closed : Bool
}

///|
fn start_aggregate_numeric(
  values : Array[Value],
  execution : NumericAggregateExecution,
  step : Int,
  name : String,
  occurrence : Int,
  control : ControlBudget,
  workspace : RowWorkspace,
) -> AggregateNumeric {
  {
    values,
    execution,
    step,
    name,
    occurrence,
    control,
    workspace,
    contributors: [],
    pending: { remaining: 0, },
    reduction: None,
    outcome: None,
    phase: 0,
    index: 0,
    closed: false,
  }
}

///|
fn close_aggregate_numeric(state : AggregateNumeric) -> Unit {
  if state.closed {
    return
  }
  if state.reduction is Some(reduction) {
    (reduction.close)() |> ignore
    state.reduction = None
  }
  state.closed = true
}

///|
fn numeric_reduction_row_issue(issue : @numeric.ReductionIssue) -> RowIssue {
  match issue {
    InvalidLimits | ContributorLimit | WorkLimit => RowLimit
    NonfiniteContributor(_) | NonfiniteIntermediate =>
      Aggregation(ArithmeticFailure)
  }
}

///|
fn advance_aggregate_numeric(
  state : AggregateNumeric,
) -> Result[Value?, RowIssue] {
  if state.closed {
    return Err(InvalidRows)
  }
  let result = advance_aggregate_numeric_impl(state)
  match result {
    Err(_) => close_aggregate_numeric(state)
    Ok(Some(_)) => state.closed = true
    Ok(None) => ()
  }
  result
}

///|
fn advance_aggregate_numeric_impl(
  s : AggregateNumeric,
) -> Result[Value?, RowIssue] {
  match s.phase {
    // Reserve the contributor array.
    0 => {
      if !reserve_slots(s.workspace, s.values.length()) {
        return Err(RowLimit)
      }
      s.phase = 1
      Ok(None)
    }
    // Copy one contributor.
    1 => {
      if s.index < s.values.length() {
        guard s.values[s.index] is Number(number) else {
          return Err(InvalidRows)
        }
        s.contributors.push(number)
        s.index += 1
        return Ok(None)
      }
      s.phase = 2
      Ok(None)
    }
    // Start the selected reduction under the remaining budget.
    2 => {
      match s.execution.start {
        Some(start) =>
          match
            start(
              s.step,
              s.name,
              s.occurrence,
              s.contributors,
              s.contributors.length(),
              s.control.remaining,
            ) {
            None => return Err(InvalidRows)
            Some(Err(issue)) => return Err(numeric_reduction_row_issue(issue))
            Some(Ok(reduction)) => {
              s.reduction = Some(reduction)
              s.phase = 3
            }
          }
        None =>
          match
            (s.execution.reduce)(
              s.step,
              s.name,
              s.occurrence,
              s.contributors,
              s.contributors.length(),
              s.control.remaining,
            ) {
            None => return Err(InvalidRows)
            Some(Err(issue)) => return Err(numeric_reduction_row_issue(issue))
            Some(Ok(outcome)) => {
              s.outcome = Some(outcome)
              s.pending.remaining = @numeric.outcome_work(outcome)
              s.phase = 4
            }
          }
      }
      Ok(None)
    }
    // Advance the Host-owned reduction.
    3 => {
      guard s.reduction is Some(reduction) else { return Err(InvalidRows) }
      match (reduction.advance)() {
        None => Err(InvalidRows)
        Some(Err(issue)) => Err(numeric_reduction_row_issue(issue))
        Some(Ok(None)) => Ok(None)
        Some(Ok(Some(outcome))) => {
          s.reduction = None
          s.outcome = Some(outcome)
          s.pending.remaining = @numeric.outcome_work(outcome)
          s.phase = 4
          Ok(None)
        }
      }
    }
    // Pay the reported work, then publish the value.
    _ =>
      match pay_pending_unit(s.pending, s.control) {
        Err(issue) => Err(issue)
        Ok(false) => Ok(None)
        Ok(true) => {
          guard s.outcome is Some(outcome) else { return Err(InvalidRows) }
          Ok(
            Some(
              match @numeric.outcome_value(outcome) {
                None => Null
                Some(value) => Number(value)
              },
            ),
          )
        }
      }
  }
}
