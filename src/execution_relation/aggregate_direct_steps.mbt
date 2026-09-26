///|
/// One aggregate over one group or analytic frame: collect or order
/// contributors, remove distinct duplicates, then run the function's
/// finishing state. Every phase advances with at most one control unit.
priv struct AggregateDirect[R] {
  aggregate : @lower.PreparedAggregate
  function : @relation.AggregateFunction
  input : R
  indices : Array[Int]
  range : AggregateGroupRange
  argument : Int?
  order : Array[ColumnOrder]
  control : ControlBudget
  workspace : RowWorkspace
  selected : Array[SelectedAggregateOutput]
  identity_limits : ValueLimits
  numeric : NumericAggregateExecution?
  numeric_step : Int
  numeric_occurrence : Int
  mut phase : Int
  mut values : Array[Value]
  mut count : Int
  mut ordered : AggregateOrderedValues[R]?
  mut endpoint : AggregateEndpoint[R]?
  mut collection : AggregateDirectCollection[R]?
  mut distinct : AggregateDistinct?
  mut finish : (() -> Result[Value?, RowIssue])?
  mut close_finish : (() -> Unit)?
  mut closed : Bool
}

///|
fn[R] start_aggregate_direct(
  aggregate : @lower.PreparedAggregate,
  input : R,
  indices : Array[Int],
  range : AggregateGroupRange,
  argument : Int?,
  order : Array[ColumnOrder],
  control : ControlBudget,
  workspace : RowWorkspace,
  selected : Array[SelectedAggregateOutput],
  identity_limits : ValueLimits,
  numeric : NumericAggregateExecution?,
  numeric_step : Int,
  numeric_occurrence : Int,
) -> AggregateDirect[R] {
  {
    aggregate,
    function: @lower.group_aggregate_function(aggregate),
    input,
    indices,
    range,
    argument,
    order,
    control,
    workspace,
    selected,
    identity_limits,
    numeric,
    numeric_step,
    numeric_occurrence,
    phase: 0,
    values: [],
    count: 0,
    ordered: None,
    endpoint: None,
    collection: None,
    distinct: None,
    finish: None,
    close_finish: None,
    closed: false,
  }
}

///|
fn[R] close_aggregate_direct(state : AggregateDirect[R]) -> Unit {
  if state.closed {
    return
  }
  if state.ordered is Some(value) {
    close_aggregate_ordered_values(value)
  }
  if state.endpoint is Some(value) {
    close_aggregate_endpoint(value)
  }
  if state.collection is Some(value) {
    close_aggregate_direct_collection(value)
  }
  if state.close_finish is Some(close) {
    close()
  }
  state.closed = true
}

///|
fn[R : IndexedRows] advance_aggregate_direct(
  state : AggregateDirect[R],
) -> Result[Value?, RowIssue] {
  if state.closed {
    return Err(InvalidRows)
  }
  let result = advance_aggregate_direct_impl(state)
  match result {
    Err(_) => close_aggregate_direct(state)
    Ok(Some(_)) => state.closed = true
    Ok(None) => ()
  }
  result
}

///|
fn aggregate_ordered_function(function : @relation.AggregateFunction) -> Bool {
  function is @relation.ArrayAgg || function is @relation.StringAgg
}

///|
fn[R : IndexedRows] advance_aggregate_direct_impl(
  s : AggregateDirect[R],
) -> Result[Value?, RowIssue] {
  match s.phase {
    // Select the contributor phase.
    0 => {
      let members : AggregateRangeRows[R] = {
        input: s.input,
        indices: s.indices,
        start: s.range.start,
        end: s.range.end,
      }
      if aggregate_ordered_function(s.function) ||
        s.function is @relation.First ||
        s.function is @relation.Last {
        guard s.argument is Some(column) && !s.order.is_empty() else {
          return Err(InvalidRows)
        }
        if aggregate_ordered_function(s.function) {
          s.ordered = Some(
            start_aggregate_ordered_values(
              members,
              s.order,
              column,
              s.control,
              s.workspace,
            ),
          )
          s.phase = 1
        } else {
          s.endpoint = Some(
            start_aggregate_endpoint(
              members,
              s.order,
              column,
              s.function is @relation.First,
              s.control,
              s.workspace,
            ),
          )
          s.phase = 2
        }
      } else {
        s.collection = Some(
          start_aggregate_direct_collection(
            s.input,
            s.indices,
            s.range,
            s.argument,
            s.function,
            s.control,
            s.workspace,
          ),
        )
        s.phase = 3
      }
      Ok(None)
    }
    // Ordered array or string contributors.
    1 => {
      guard s.ordered is Some(ordered) else { return Err(InvalidRows) }
      match advance_aggregate_ordered_values(ordered) {
        Err(issue) => Err(issue)
        Ok(None) => Ok(None)
        Ok(Some(values)) => {
          s.ordered = None
          s.values = values
          aggregate_direct_after_contributors(s)
        }
      }
    }
    // first or last.
    2 => {
      guard s.endpoint is Some(endpoint) else { return Err(InvalidRows) }
      match advance_aggregate_endpoint(endpoint) {
        Err(issue) => Err(issue)
        Ok(None) => Ok(None)
        Ok(Some(value)) => {
          s.endpoint = None
          Ok(Some(value))
        }
      }
    }
    // Direct contributor collection.
    3 => {
      guard s.collection is Some(collection) else { return Err(InvalidRows) }
      match advance_aggregate_direct_collection(collection) {
        Err(issue) => Err(issue)
        Ok(None) => Ok(None)
        Ok(Some((values, count))) => {
          s.collection = None
          s.values = values
          s.count = count
          aggregate_direct_after_contributors(s)
        }
      }
    }
    // Distinct removal.
    4 => {
      guard s.distinct is Some(distinct) else { return Err(InvalidRows) }
      match advance_aggregate_distinct(distinct) {
        Err(issue) => Err(issue)
        Ok(None) => Ok(None)
        Ok(Some(values)) => {
          s.distinct = None
          s.values = values
          aggregate_direct_start_finish(s)
        }
      }
    }
    // The function's finishing state.
    _ => {
      guard s.finish is Some(finish) else { return Err(InvalidRows) }
      finish()
    }
  }
}

///|
fn[R] aggregate_direct_after_contributors(
  s : AggregateDirect[R],
) -> Result[Value?, RowIssue] {
  if @lower.group_aggregate_distinct(s.aggregate) == Some(true) {
    s.distinct = Some(
      start_aggregate_distinct(
        s.values,
        s.control,
        s.workspace,
        s.identity_limits,
      ),
    )
    s.phase = 4
    return Ok(None)
  }
  aggregate_direct_start_finish(s)
}

///|
fn[R] aggregate_direct_finish_with(
  s : AggregateDirect[R],
  advance : () -> Result[Value?, RowIssue],
  close : () -> Unit,
) -> Result[Value?, RowIssue] {
  s.finish = Some(advance)
  s.close_finish = Some(close)
  s.phase = 5
  Ok(None)
}

///|
/// Start the finishing state, or return a value decided without one.
fn[R] aggregate_direct_start_finish(
  s : AggregateDirect[R],
) -> Result[Value?, RowIssue] {
  let values = s.values
  match s.function {
    @relation.ArrayAgg => {
      guard selected_aggregate_output_limit(s.selected, s.aggregate, ArrayItems)
        is Some(maximum) else {
        return Err(InvalidRows)
      }
      if values.length().to_int64() > maximum {
        return Err(RowLimit)
      }
      let state = start_aggregate_array(values, s.control, s.workspace)
      return aggregate_direct_finish_with(
        s,
        () => advance_aggregate_array(state),
        () => state.closed = true,
      )
    }
    @relation.StringAgg => {
      if values.is_empty() {
        return Ok(Some(Null))
      }
      guard selected_aggregate_output_limit(
          s.selected,
          s.aggregate,
          StringBytes,
        )
        is Some(maximum) &&
        @lower.group_aggregate_delimiter(s.aggregate) is Some(delimiter) else {
        return Err(InvalidRows)
      }
      let delimiter_bytes = if values.length() > 1 {
        match @scalar.admit_utf8_length64(delimiter, maximum) {
          Ok(bytes) => bytes
          Err(_) => return Err(RowLimit)
        }
      } else {
        0L
      }
      if !reserve_slots(s.workspace, values.length()) {
        return Err(RowLimit)
      }
      let state = start_aggregate_string(
        values,
        delimiter,
        delimiter_bytes,
        maximum,
        s.control,
      )
      return aggregate_direct_finish_with(
        s,
        () => advance_aggregate_string(state),
        () => state.closed = true,
      )
    }
    _ => ()
  }
  if @lower.group_aggregate_requires_numeric_observation(s.aggregate) {
    guard s.numeric is Some(execution) &&
      s.numeric_step >= 0 &&
      s.numeric_occurrence >= 0 else {
      return Err(InvalidRows)
    }
    let state = start_aggregate_numeric(
      values,
      execution,
      s.numeric_step,
      @lower.group_aggregate_name(s.aggregate),
      s.numeric_occurrence,
      s.control,
      s.workspace,
    )
    return aggregate_direct_finish_with(
      s,
      () => advance_aggregate_numeric(state),
      () => close_aggregate_numeric(state),
    )
  }
  match s.function {
    @relation.Count => {
      let total = if s.argument is None { s.count } else { values.length() }
      Ok(Some(Number(total.to_double())))
    }
    @relation.CountIf => Ok(Some(Number(s.count.to_double())))
    @relation.Min | @relation.Max => {
      let state = start_aggregate_extremum(
        values,
        s.function is @relation.Min,
        s.control,
      )
      aggregate_direct_finish_with(s, () => advance_aggregate_extremum(state), () => {
        close_aggregate_extremum(state)
      })
    }
    @relation.Sum => {
      if values.is_empty() {
        return Ok(Some(Null))
      }
      guard @lower.group_aggregate_result(s.aggregate).shape
        is @contract.Decimal(precision~, scale~) else {
        return Err(InvalidRows)
      }
      let state = start_aggregate_decimal_sum(
        values,
        precision,
        scale,
        s.control,
        s.workspace,
      )
      aggregate_direct_finish_with(
        s,
        () => advance_aggregate_decimal_sum(state),
        () => close_aggregate_decimal_sum(state),
      )
    }
    @relation.PercentileDisc | @relation.PercentileCont => {
      if values.is_empty() {
        return Ok(Some(Null))
      }
      guard @lower.group_aggregate_fraction(s.aggregate) is Some(fraction) else {
        return Err(InvalidRows)
      }
      let state = start_aggregate_percentile(
        values,
        fraction,
        s.function is @relation.PercentileDisc,
        s.control,
        s.workspace,
      )
      aggregate_direct_finish_with(
        s,
        () => advance_aggregate_percentile(state),
        () => state.closed = true,
      )
    }
    @relation.VarPop
    | @relation.VarSamp
    | @relation.StddevPop
    | @relation.StddevSamp => {
      let sample = s.function is @relation.VarSamp ||
        s.function is @relation.StddevSamp
      if values.is_empty() || (sample && values.length() < 2) {
        return Ok(Some(Null))
      }
      let state = start_aggregate_statistical(
        values,
        sample,
        s.function is @relation.StddevPop || s.function is @relation.StddevSamp,
        s.control,
        s.workspace,
        s.identity_limits,
      )
      aggregate_direct_finish_with(
        s,
        () => advance_aggregate_statistical(state),
        () => state.closed = true,
      )
    }
    _ => Err(InvalidRows)
  }
}

///|
/// One aggregate over one group. A filtered or expression aggregate first
/// prepares its contributors with the resumable preparation owner, then
/// finishes over those values like `evaluate_dynamic_aggregate`.
priv struct AggregateEvaluation[T] {
  aggregate : @lower.PreparedAggregate
  control : ControlBudget
  workspace : RowWorkspace
  selected : Array[SelectedAggregateOutput]
  identity_limits : ValueLimits
  numeric : NumericAggregateExecution?
  numeric_step : Int
  numeric_occurrence : Int
  argument_rows : Bool
  mut preparation : AggregatePreparation[T]?
  direct : AggregateDirect[T]?
  mut dynamic : AggregateDirect[DynamicAggregateRows]?
  mut closed : Bool
}

///|
fn[T] start_aggregate_evaluation(
  aggregate : @lower.PreparedAggregate,
  input : T,
  names : Array[String],
  indices : Array[Int],
  range : AggregateGroupRange,
  argument : AggregateInput,
  order : Array[ColumnOrder],
  aggregate_index : Int,
  control : ControlBudget,
  workspace : RowWorkspace,
  selected : Array[SelectedAggregateOutput],
  identity_limits : ValueLimits,
  scope : ExpressionRoots?,
  numeric : NumericAggregateExecution?,
  numeric_step : Int,
  numeric_occurrence : Int,
) -> AggregateEvaluation[T] {
  let dynamic = @lower.group_aggregate_filter(aggregate) is Some(_) ||
    argument is AggregateInputExpression(_)
  {
    aggregate,
    control,
    workspace,
    selected,
    identity_limits,
    numeric,
    numeric_step,
    numeric_occurrence,
    argument_rows: argument is AggregateInputRows,
    preparation: if dynamic {
      Some(
        start_aggregate_preparation(
          input,
          names,
          indices,
          range,
          argument,
          @lower.group_aggregate_filter(aggregate),
          aggregate_index,
          order,
          control,
          workspace,
          scope,
        ),
      )
    } else {
      None
    },
    direct: if dynamic {
      None
    } else {
      Some(
        start_aggregate_direct(
          aggregate,
          input,
          indices,
          range,
          match argument {
            AggregateInputField(column) => Some(column)
            _ => None
          },
          order,
          control,
          workspace,
          selected,
          identity_limits,
          numeric,
          numeric_step,
          numeric_occurrence,
        ),
      )
    },
    dynamic: None,
    closed: false,
  }
}

///|
fn[T] close_aggregate_evaluation(state : AggregateEvaluation[T]) -> Unit {
  if state.closed {
    return
  }
  if state.preparation is Some(value) {
    close_aggregate_preparation(value)
  }
  if state.direct is Some(value) {
    close_aggregate_direct(value)
  }
  if state.dynamic is Some(value) {
    close_aggregate_direct(value)
  }
  state.closed = true
}

///|
fn[T : IndexedRows] advance_aggregate_evaluation(
  state : AggregateEvaluation[T],
) -> Result[Value?, RowIssue] {
  if state.closed {
    return Err(InvalidRows)
  }
  let result = if state.direct is Some(direct) {
    advance_aggregate_direct(direct)
  } else if state.dynamic is Some(dynamic) {
    advance_aggregate_direct(dynamic)
  } else if state.preparation is Some(preparation) {
    match advance_aggregate_preparation(preparation) {
      Err(issue) => Err(issue)
      Ok(None) => Ok(None)
      Ok(Some((sorted, local_indices))) => {
        state.preparation = None
        let ordered_function = match
          @lower.group_aggregate_function(state.aggregate) {
          @relation.First
          | @relation.Last
          | @relation.ArrayAgg
          | @relation.StringAgg => true
          _ => false
        }
        state.dynamic = Some(
          start_aggregate_direct(
            state.aggregate,
            { values: sorted, },
            local_indices,
            {
              representative: if local_indices.is_empty() {
                None
              } else {
                Some(0)
              },
              start: 0,
              end: local_indices.length(),
            },
            if state.argument_rows {
              None
            } else {
              Some(0)
            },
            if ordered_function {
              [{ column: 1, descending: false, nulls_first: true, }]
            } else {
              []
            },
            state.control,
            state.workspace,
            state.selected,
            state.identity_limits,
            state.numeric,
            state.numeric_step,
            state.numeric_occurrence,
          ),
        )
        Ok(None)
      }
    }
  } else {
    Err(InvalidRows)
  }
  match result {
    Err(_) => close_aggregate_evaluation(state)
    Ok(Some(_)) => state.closed = true
    Ok(None) => ()
  }
  result
}
