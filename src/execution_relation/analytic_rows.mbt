///|
priv struct AnalyticPartitionRange {
  start : Int
  end : Int
}

///|
priv enum AnalyticCountIndex {
  CountRows
  CountPrefix(Array[Int])
}

///|
pub fn analytic_execution_supported(analytic : @lower.PreparedAnalytic) -> Bool {
  analytic_execution_supported_with_profile(analytic, false)
}

///|
/// Numeric capability changes only frame aggregates with checked observation
/// slots. Ranking, navigation, ordering, and every other aggregate retain the
/// same closed support predicate.
pub fn analytic_execution_supported_with_numeric(
  analytic : @lower.PreparedAnalytic,
) -> Bool {
  analytic_execution_supported_with_profile(analytic, true)
}

///|
fn analytic_execution_supported_with_profile(
  analytic : @lower.PreparedAnalytic,
  numeric : Bool,
) -> Bool {
  let schema = @lower.analytic_input_schema(analytic)
  for i in 0..<@lower.analytic_partition_count(analytic) {
    guard @schema.lookup(
        schema,
        @lower.analytic_partition_at(analytic, i).unwrap(),
      )
      is Some(contract) else {
      return false
    }
    if !supported_comparison(contract, contract) {
      return false
    }
  }
  for i in 0..<@lower.analytic_position_term_count(analytic) {
    let (field, _, _) = @lower.analytic_position_term_at(analytic, i).unwrap()
    guard @schema.lookup(schema, field) is Some(contract) else { return false }
    if !supported_comparison(contract, contract) {
      return false
    }
  }
  for i in 0..<@lower.analytic_call_count(analytic) {
    let call = @lower.analytic_call_at(analytic, i).unwrap()
    match @lower.analytic_call_function(call) {
      PreparedRowNumber
      | PreparedRank
      | PreparedDenseRank
      | PreparedLag(_, _)
      | PreparedLead(_, _)
      | PreparedFirstValue(_)
      | PreparedLastValue(_) => ()
      PreparedFrameAggregate(aggregate) =>
        if @lower.analytic_frame(analytic) is None ||
          !direct_aggregate_execution_supported(
            aggregate,
            @lower.analytic_position_term_count(analytic) > 0,
            numeric~,
          ) {
          return false
        }
    }
  }
  true
}

///|
fn analytic_frame_range(
  frame : @lower.PreparedRowsFrame,
  position : Int,
  length : Int,
) -> (Int, Int)? {
  if position < 0 || position >= length || length <= 0 {
    return None
  }
  let current = Int64::from_int(position)
  let last = Int64::from_int(length - 1)
  let boundary = fn(value : @lower.PreparedFrameBoundary) -> Int64 {
    match value {
      PreparedUnboundedPreceding => 0L
      PreparedPreceding(distance) => current - distance
      PreparedCurrentRow => current
      PreparedFollowing(distance) => current + distance
      PreparedUnboundedFollowing => last
    }
  }
  let start = boundary(@lower.prepared_frame_start(frame))
  let end = boundary(@lower.prepared_frame_end(frame))
  // Intersect the logical interval with the partition. A start beyond the
  // partition or an end before it produces an empty frame; neither is clamped
  // onto an existing row.
  if start > last || end < 0L || start > end {
    return None
  }
  let first = if start < 0L { 0L } else { start }
  let last_member = if end > last { last } else { end }
  Some((first.to_int(), last_member.to_int() + 1))
}

///|
/// Drains the resumable `AnalyticEvaluation` with the same charges.
fn[T : RelationRows] evaluate_analytic_into(
  analytic : @lower.PreparedAnalytic,
  input : T,
  max_rows : Int,
  control : ControlBudget,
  output : ValueBudget,
  workspace : RowWorkspace,
  scope : ExpressionRoots?,
  aggregate_outputs : Array[SelectedAggregateOutput],
  envelope : SelectedAnalyticEnvelope?,
  identity_limits : ValueLimits,
  numeric : NumericAggregateExecution?,
  step~ : Int,
  accept_row : (Array[Value], Int, Array[String], Array[Int]?) -> Result[
    Unit,
    RowIssue,
  ],
) -> Result[Array[String], RowIssue] {
  let names : Ref[Array[String]] = Ref([])
  let state = start_analytic_evaluation(
    analytic,
    input,
    max_rows,
    control,
    output,
    workspace,
    scope,
    aggregate_outputs,
    envelope,
    identity_limits,
    numeric,
    step,
    (row, source) => accept_row(row, source, names.val, None),
  )
  while true {
    names.val = state.output_names
    match advance_analytic_evaluation(state) {
      Ok(None) => ()
      Ok(Some(output_names)) => break Ok(output_names)
      Err(issue) => break Err(issue)
    }
  } nobreak {
    Err(InvalidRows)
  }
}
