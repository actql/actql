///|
priv struct AggregateGroupRange {
  representative : Int?
  start : Int
  end : Int
}

///|
/// A read-only group-member view. Sorting this view produces local member
/// coordinates while the original relation and group index remain immutable.
priv struct AggregateRangeRows[T] {
  input : T
  indices : Array[Int]
  start : Int
  end : Int
}

///|
priv enum AggregateInput {
  AggregateInputRows
  AggregateInputField(Int)
  AggregateInputExpression(@lower.Expression)
}

///|
/// Evaluated contributors retain their source rows so an aggregate-local
/// order can sort the values without evaluating a filtered argument again.
priv struct AggregateContributorRows[T] {
  input : T
  sources : Array[Int]
}

///|
impl[T : IndexedRows] IndexedRows for AggregateContributorRows[T] with fn row_count(
  self,
) {
  self.sources.length()
}

///|
impl[T : IndexedRows] IndexedRows for AggregateContributorRows[T] with fn column_count(
  self,
) {
  self.input.column_count()
}

///|
impl[T : IndexedRows] IndexedRows for AggregateContributorRows[T] with fn row_width(
  self,
  row,
) {
  self.input.row_width(self.sources[row])
}

///|
impl[T : IndexedRows] IndexedRows for AggregateContributorRows[T] with fn read_cell(
  self,
  row,
  column,
) {
  self.input.read_cell(self.sources[row], column)
}

///|
priv struct DynamicAggregateRows {
  values : Array[Value]
}

///|
impl IndexedRows for DynamicAggregateRows with fn row_count(self) {
  self.values.length()
}

///|
impl IndexedRows for DynamicAggregateRows with fn column_count(_self) {
  2
}

///|
impl IndexedRows for DynamicAggregateRows with fn row_width(_self, _row) {
  2
}

///|
impl IndexedRows for DynamicAggregateRows with fn read_cell(self, row, column) {
  if column == 0 {
    self.values[row]
  } else {
    Number(row.to_double())
  }
}

///|
impl[T : IndexedRows] IndexedRows for AggregateRangeRows[T] with fn row_count(
  self,
) {
  self.end - self.start
}

///|
impl[T : IndexedRows] IndexedRows for AggregateRangeRows[T] with fn column_count(
  self,
) {
  self.input.column_count()
}

///|
impl[T : IndexedRows] IndexedRows for AggregateRangeRows[T] with fn row_width(
  self,
  row,
) {
  self.input.row_width(self.indices[self.start + row])
}

///|
impl[T : IndexedRows] IndexedRows for AggregateRangeRows[T] with fn read_cell(
  self,
  row,
  column,
) {
  self.input.read_cell(self.indices[self.start + row], column)
}

///|
// Shared direct fold capability. Group supplies aggregate-local ordering;
// analytic supplies its completed frame ordering.
fn direct_aggregate_execution_supported(
  aggregate : @lower.PreparedAggregate,
  ordered : Bool,
  numeric? : Bool = false,
) -> Bool {
  if @lower.group_aggregate_requires_numeric_observation(aggregate) && !numeric {
    return false
  }
  let argument = @lower.group_aggregate_argument(aggregate)
  let has_argument = !(argument is @lower.AggregateRows)
  match (@lower.group_aggregate_function(aggregate), argument) {
    (@relation.Count, @lower.AggregateRows)
    | (@relation.Count, @lower.AggregateField(_))
    | (@relation.Count, @lower.AggregateExpression(_)) => ()
    (@relation.CountIf, _) => if !has_argument { return false }
    (@relation.Min, _) | (@relation.Max, _) => {
      if !has_argument {
        return false
      }
      let result = @lower.group_aggregate_result(aggregate)
      if !supported_comparison(result, result) {
        return false
      }
    }
    (@relation.Sum, _) =>
      if !has_argument ||
        (
          !numeric &&
          !(@lower.group_aggregate_result(aggregate).shape
          is @contract.Decimal(precision=38, ..))
        ) {
        return false
      }
    (@relation.Avg, _) => if !has_argument || !numeric { return false }
    (@relation.First, _) | (@relation.Last, _) =>
      if !has_argument || !ordered {
        return false
      }
    (@relation.ArrayAgg, _) => if !has_argument || !ordered { return false }
    (@relation.StringAgg, _) =>
      if !has_argument ||
        !ordered ||
        @lower.group_aggregate_delimiter(aggregate) is None {
        return false
      }
    (@relation.PercentileDisc, _) => {
      if !has_argument {
        return false
      }
      let result = @lower.group_aggregate_result(aggregate)
      if !supported_comparison(result, result) {
        return false
      }
    }
    (@relation.PercentileCont, _)
    | (@relation.VarPop, _)
    | (@relation.VarSamp, _)
    | (@relation.StddevPop, _)
    | (@relation.StddevSamp, _) =>
      if !has_argument ||
        !(@lower.group_aggregate_result(aggregate).shape is @contract.Number) {
        return false
      }
  }
  true
}

///|
/// Exact initial Local capability for complete group descriptors. A false
/// result is a candidate-selection decision, never permission to reinterpret
/// the checked aggregate through another physical law.
pub fn group_execution_supported(group : @lower.PreparedGroup) -> Bool {
  group_execution_supported_with_profile(group, false)
}

///|
/// Numeric capability changes only the pinned reduction lane. Every other
/// group requirement is checked by the same closed support predicate.
pub fn group_execution_supported_with_numeric(
  group : @lower.PreparedGroup,
) -> Bool {
  group_execution_supported_with_profile(group, true)
}

///|
fn group_execution_supported_with_profile(
  group : @lower.PreparedGroup,
  numeric : Bool,
) -> Bool {
  let input = @lower.group_input_schema(group)
  for i = 0; i < @lower.group_key_count(group); i = i + 1 {
    guard @schema.lookup(input, @lower.group_key_at(group, i).unwrap())
      is Some(contract) else {
      return false
    }
    if !supported_comparison(contract, contract) {
      return false
    }
  }
  for i = 0; i < @lower.group_aggregate_count(group); i = i + 1 {
    let aggregate = @lower.group_aggregate_at(group, i).unwrap()
    for j = 0; j < @lower.group_aggregate_order_count(aggregate); j = j + 1 {
      let (field, _, _) = @lower.group_aggregate_order_term_at(aggregate, j).unwrap()
      guard @schema.lookup(input, field) is Some(contract) else { return false }
      if !supported_comparison(contract, contract) {
        return false
      }
    }
    if !direct_aggregate_execution_supported(
        aggregate,
        @lower.group_aggregate_order_count(aggregate) > 0,
        numeric~,
      ) {
      return false
    }
  }
  true
}

///|
/// Hash one runtime value under the identity limits and the remaining
/// control budget, returning its CID and the encoded bytes to charge.
/// The hash work is bounded by the per-value identity limits.
fn runtime_value_identity_usage(
  value : Value,
  control : ControlBudget,
  workspace : RowWorkspace,
  limits : ValueLimits,
) -> Result[(String, Int), RowIssue] {
  if limits.max_nodes < 0 ||
    limits.max_text_bytes < 0 ||
    limits.max_work < 0 ||
    limits.max_depth < 0 ||
    !reserve_slots(workspace, limits.max_depth) {
    return Err(RowLimit)
  }
  let result : Result[(String, Int), RowIssue] = try {
    let writer = @encode.hashing_writer(
      Int::min(control.remaining, limits.max_work),
      Int::min(Int::min(control.remaining, limits.max_work), limits.max_nodes),
      limits.max_depth,
    )
    emit_runtime_value(value, writer)
    let (cid, bytes, _) = @encode.finish_hash_usage(writer)
    Ok((cid, bytes))
  } catch {
    _ => Err(RowLimit)
  }
  release_slots(workspace, limits.max_depth)
  result
}

///|
fn admitted_aggregate_item(
  value : Value,
  control : ControlBudget,
) -> Result[@admitted.Value?, RowIssue] {
  match value {
    Null => Ok(None)
    Boolean(value) => Ok(Some(@admitted.boolean_value(value)))
    Number(value) =>
      match @admitted.number_value(value) {
        Some(value) => Ok(Some(value))
        None => Err(InvalidRows)
      }
    Text(value) => {
      // Row Text is not an admitted type. Pay for the complete UTF-8 scan
      // before asking the admission layer to normalize or retain it.
      if !spend_control_text(control, value) {
        return Err(RowLimit)
      }
      match @admitted.text_value(value, 2147483647) {
        Some(value) => Ok(Some(value))
        None => Err(InvalidRows)
      }
    }
    Captured(value) => Ok(Some(value))
  }
}

///|
fn spend_control_bytes(control : ControlBudget, bytes : Int64) -> Bool {
  bytes >= 0L &&
  bytes <= control.remaining.to_int64() &&
  spend_control(control, bytes.to_int())
}

///|
fn finite_aggregate_number(value : Double) -> Result[Double, RowIssue] {
  if value.is_nan() || value.is_inf() {
    Err(Aggregation(ArithmeticFailure))
  } else {
    Ok(if value == 0.0 { 0.0 } else { value })
  }
}

///|
fn[T : IndexedRows] evaluate_direct_aggregate(
  aggregate : @lower.PreparedAggregate,
  input : T,
  indices : Array[Int],
  range : AggregateGroupRange,
  argument : Int?,
  order : Array[ColumnOrder],
  control : ControlBudget,
  workspace : RowWorkspace,
  selected : Array[SelectedAggregateOutput],
  identity_limits : ValueLimits,
  numeric? : NumericAggregateExecution? = None,
  numeric_step? : Int = -1,
  numeric_occurrence? : Int = -1,
) -> Result[Value, RowIssue] {
  let state = start_aggregate_direct(
    aggregate, input, indices, range, argument, order, control, workspace, selected,
    identity_limits, numeric, numeric_step, numeric_occurrence,
  )
  while true {
    match advance_aggregate_direct(state) {
      Ok(None) => ()
      Ok(Some(value)) => break Ok(value)
      Err(issue) => break Err(issue)
    }
  } nobreak {
    Err(InvalidRows)
  }
}

///|
fn[T : RelationRows] evaluate_group_into(
  group : @lower.PreparedGroup,
  input : T,
  max_rows : Int,
  control : ControlBudget,
  output : ValueBudget,
  workspace : RowWorkspace,
  scope : ExpressionRoots?,
  accept_row : (Array[Value], Int, Array[String], Array[Int]?) -> Result[
    Unit,
    RowIssue,
  ],
  aggregate_outputs : Array[SelectedAggregateOutput],
  identity_limits : ValueLimits,
  numeric : NumericAggregateExecution?,
  step~ : Int,
) -> Result[Array[String], RowIssue] {
  let state = start_bounded_group(
    group,
    input,
    max_rows,
    control,
    output,
    workspace,
    scope,
    accept_row,
    aggregate_outputs,
    identity_limits,
    numeric,
    step~,
  )
  while true {
    match advance_bounded_group(state) {
      Ok(None) => ()
      Ok(Some(names)) => break Ok(names)
      Err(issue) => break Err(issue)
    }
  } nobreak {
    Err(InvalidRows)
  }
}
