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
fn runtime_value_identity(
  value : Value,
  control : ControlBudget,
  workspace : RowWorkspace,
  limits : ValueLimits,
) -> Result[String, RowIssue] {
  if limits.max_nodes < 0 ||
    limits.max_text_bytes < 0 ||
    limits.max_work < 0 ||
    limits.max_depth < 0 ||
    !reserve_slots(workspace, limits.max_depth) {
    return Err(RowLimit)
  }
  let result : Result[String, RowIssue] = try {
    let writer = @encode.hashing_writer(
      Int::min(control.remaining, limits.max_work),
      Int::min(Int::min(control.remaining, limits.max_work), limits.max_nodes),
      limits.max_depth,
    )
    emit_runtime_value(value, writer)
    let (cid, bytes, _) = @encode.finish_hash_usage(writer)
    if !spend_control(control, bytes) {
      Err(RowLimit)
    } else {
      Ok(cid)
    }
  } catch {
    _ => Err(RowLimit)
  }
  release_slots(workspace, limits.max_depth)
  result
}

///|
fn distinct_aggregate_values(
  values : Array[Value],
  control : ControlBudget,
  workspace : RowWorkspace,
  identity_limits : ValueLimits,
) -> Result[Array[Value], RowIssue] {
  let buckets : Map[String, Array[Value]] = Map([])
  let output : Array[Value] = []
  for value in values {
    if !spend_control(control, 1) {
      return Err(RowLimit)
    }
    let cid = match
      runtime_value_identity(value, control, workspace, identity_limits) {
      Ok(cid) => cid
      Err(issue) => return Err(issue)
    }
    let bucket = match buckets.get(cid) {
      Some(bucket) => bucket
      None => {
        if !reserve_slots(workspace, 1) || !spend_control_text(control, cid) {
          return Err(RowLimit)
        }
        let bucket : Array[Value] = []
        buckets[cid] = bucket
        bucket
      }
    }
    let mut duplicate = false
    for previous in bucket {
      let comparison = match compare_complete_value(previous, value, control) {
        Ok(comparison) => comparison
        Err(InvalidInput) => return Err(InvalidRows)
        Err(Limit) => return Err(RowLimit)
        Err(Scalar(issue)) => return Err(Comparison(issue))
      }
      if comparison == 0 {
        duplicate = true
        break
      }
    }
    if !duplicate {
      if !reserve_slots(workspace, 2) {
        return Err(RowLimit)
      }
      bucket.push(value)
      output.push(value)
    }
  }
  Ok(output)
}

///|
fn admitted_aggregate_item(value : Value) -> @admitted.Value? {
  match value {
    Null => None
    Boolean(value) => Some(@admitted.boolean_value(value))
    Number(value) => @admitted.number_value(value)
    Text(value) => @admitted.text_value(value, 2147483647)
    Captured(value) => Some(value)
  }
}

///|
fn[T : IndexedRows] ordered_aggregate_values(
  input : T,
  indices : Array[Int],
  range : AggregateGroupRange,
  column : Int,
  order : Array[ColumnOrder],
  control : ControlBudget,
  workspace : RowWorkspace,
) -> Result[Array[Value], RowIssue] {
  let members : AggregateRangeRows[T] = {
    input,
    indices,
    start: range.start,
    end: range.end,
  }
  let ordered = match stable_order_indices(members, order, control, workspace) {
    Ok(ordered) => ordered
    Err(InvalidInput) => return Err(InvalidRows)
    Err(Limit) => return Err(RowLimit)
    Err(Scalar(issue)) => return Err(Comparison(issue))
  }
  let values : Array[Value] = []
  for position in ordered {
    if !spend_control(control, 1) {
      return Err(RowLimit)
    }
    let value = IndexedRows::read_cell(members, position, column)
    if !(value is Null) {
      if !reserve_slots(workspace, 1) {
        return Err(RowLimit)
      }
      values.push(value)
    }
  }
  Ok(values)
}

///|
fn spend_control_bytes(control : ControlBudget, bytes : Int64) -> Bool {
  bytes >= 0L &&
  bytes <= control.remaining.to_int64() &&
  spend_control(control, bytes.to_int())
}

///|
fn evaluate_array_aggregate(
  aggregate : @lower.PreparedAggregate,
  values : Array[Value],
  selected : Array[SelectedAggregateOutput],
  control : ControlBudget,
  workspace : RowWorkspace,
) -> Result[Value, RowIssue] {
  guard selected_aggregate_output_limit(selected, aggregate, ArrayItems)
    is Some(maximum) else {
    return Err(InvalidRows)
  }
  if values.length().to_int64() > maximum ||
    !spend_control(control, values.length()) ||
    !reserve_slots(workspace, values.length()) {
    return Err(RowLimit)
  }
  let admitted : Array[@admitted.Value] = []
  for value in values {
    guard admitted_aggregate_item(value) is Some(item) else {
      return Err(InvalidRows)
    }
    admitted.push(item)
  }
  Ok(Captured(@admitted.array_value(admitted)))
}

///|
fn evaluate_string_aggregate(
  aggregate : @lower.PreparedAggregate,
  values : Array[Value],
  selected : Array[SelectedAggregateOutput],
  control : ControlBudget,
  workspace : RowWorkspace,
) -> Result[Value, RowIssue] {
  if values.is_empty() {
    return Ok(Null)
  }
  guard selected_aggregate_output_limit(selected, aggregate, StringBytes)
    is Some(maximum) &&
    @lower.group_aggregate_delimiter(aggregate) is Some(delimiter) else {
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
  if !reserve_slots(workspace, values.length()) {
    return Err(RowLimit)
  }
  let strings : Array[String] = []
  let mut total = 0L
  for index, value in values {
    guard value is Text(text) else { return Err(InvalidRows) }
    let bytes = match @scalar.admit_utf8_length64(text, maximum) {
      Ok(bytes) => bytes
      Err(_) => return Err(RowLimit)
    }
    let separator = if index == 0 { 0L } else { delimiter_bytes }
    if separator > maximum - total ||
      bytes > maximum - total - separator ||
      !spend_control_bytes(control, separator) ||
      !spend_control_bytes(control, bytes) {
      return Err(RowLimit)
    }
    total += separator + bytes
    strings.push(text)
  }
  Ok(Text(strings.join(delimiter)))
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
fn sort_aggregate_values(
  values : Array[Value],
  control : ControlBudget,
  workspace : RowWorkspace,
) -> Result[Unit, RowIssue] {
  if !reserve_slots(workspace, values.length()) {
    return Err(RowLimit)
  }
  let mut issue : RowIssue? = None
  values.sort_by((left, right) => {
    if issue is Some(_) {
      return 0
    }
    match compare_complete_value(left, right, control) {
      Ok(comparison) => comparison
      Err(InvalidInput) => {
        issue = Some(InvalidRows)
        0
      }
      Err(Limit) => {
        issue = Some(RowLimit)
        0
      }
      Err(Scalar(value)) => {
        issue = Some(Comparison(value))
        0
      }
    }
  })
  release_slots(workspace, values.length())
  match issue {
    Some(issue) => Err(issue)
    None => Ok(())
  }
}

///|
fn evaluate_percentile_aggregate(
  aggregate : @lower.PreparedAggregate,
  values : Array[Value],
  control : ControlBudget,
  workspace : RowWorkspace,
) -> Result[Value, RowIssue] {
  if values.is_empty() {
    return Ok(Null)
  }
  guard @lower.group_aggregate_fraction(aggregate) is Some(fraction) else {
    return Err(InvalidRows)
  }
  match sort_aggregate_values(values, control, workspace) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let function = @lower.group_aggregate_function(aggregate)
  if function is @relation.PercentileDisc {
    if !spend_control(control, 2) {
      return Err(RowLimit)
    }
    let rank = Int::max(
      1,
      (fraction * values.length().to_double()).ceil().to_int(),
    )
    return Ok(values[rank - 1])
  }
  guard function is @relation.PercentileCont else { return Err(InvalidRows) }
  let numbers : Array[Double] = []
  if !reserve_slots(workspace, values.length()) {
    return Err(RowLimit)
  }
  for value in values {
    guard value is Number(number) && !number.is_nan() && !number.is_inf() else {
      return Err(InvalidRows)
    }
    numbers.push(number)
  }
  if !spend_control(control, 4) {
    return Err(RowLimit)
  }
  let h = match
    finite_aggregate_number((numbers.length() - 1).to_double() * fraction) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let index = h.floor().to_int()
  let remainder = match finite_aggregate_number(h - index.to_double()) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if remainder == 0.0 {
    return Ok(Number(numbers[index]))
  }
  if !spend_control(control, 3) {
    return Err(RowLimit)
  }
  let difference = match
    finite_aggregate_number(numbers[index + 1] - numbers[index]) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let weighted = match finite_aggregate_number(remainder * difference) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match finite_aggregate_number(numbers[index] + weighted) {
    Ok(value) => Ok(Number(value))
    Err(issue) => Err(issue)
  }
}

///|
fn canonical_numeric_values(
  values : Array[Value],
  control : ControlBudget,
  workspace : RowWorkspace,
  identity_limits : ValueLimits,
) -> Result[Array[Double], RowIssue] {
  let entries : Array[(String, Double)] = []
  if !reserve_slots(workspace, values.length()) ||
    !reserve_slots(workspace, values.length()) {
    return Err(RowLimit)
  }
  for value in values {
    guard value is Number(number) && !number.is_nan() && !number.is_inf() else {
      return Err(InvalidRows)
    }
    let cid = match
      runtime_value_identity(value, control, workspace, identity_limits) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    entries.push((cid, number))
  }
  let mut failed = false
  entries.sort_by((left, right) => {
    if failed ||
      !spend_control_text(control, left.0) ||
      !spend_control_text(control, right.0) {
      failed = true
      0
    } else {
      @canonical.compare_utf16(left.0, right.0)
    }
  })
  if failed {
    return Err(RowLimit)
  }
  Ok(entries.map(entry => entry.1))
}

///|
fn evaluate_statistical_aggregate(
  aggregate : @lower.PreparedAggregate,
  values : Array[Value],
  control : ControlBudget,
  workspace : RowWorkspace,
  identity_limits : ValueLimits,
) -> Result[Value, RowIssue] {
  let function = @lower.group_aggregate_function(aggregate)
  let sample = function is @relation.VarSamp || function is @relation.StddevSamp
  if values.is_empty() || (sample && values.length() < 2) {
    return Ok(Null)
  }
  let numbers = match
    canonical_numeric_values(values, control, workspace, identity_limits) {
    Ok(values) => values
    Err(issue) => return Err(issue)
  }
  let mut sum = 0.0
  for value in numbers {
    if !spend_control(control, 1) {
      return Err(RowLimit)
    }
    sum = match finite_aggregate_number(sum + value) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
  }
  if !spend_control(control, 1) {
    return Err(RowLimit)
  }
  let mean = match finite_aggregate_number(sum / numbers.length().to_double()) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let mut squares = 0.0
  for value in numbers {
    if !spend_control(control, 3) {
      return Err(RowLimit)
    }
    let difference = match finite_aggregate_number(value - mean) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let square = match finite_aggregate_number(difference * difference) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    squares = match finite_aggregate_number(squares + square) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
  }
  if !spend_control(control, 1) {
    return Err(RowLimit)
  }
  let divisor = if sample { numbers.length() - 1 } else { numbers.length() }
  let variance = match finite_aggregate_number(squares / divisor.to_double()) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if function is @relation.StddevPop || function is @relation.StddevSamp {
    if !spend_control(control, 1) {
      return Err(RowLimit)
    }
    match finite_aggregate_number(variance.sqrt()) {
      Ok(value) => Ok(Number(value))
      Err(issue) => Err(issue)
    }
  } else {
    Ok(Number(variance))
  }
}

///|
fn[T : IndexedRows] aggregate_group_ranges(
  input : T,
  indices : Array[Int],
  order : Array[ColumnOrder],
  max_groups : Int,
  control : ControlBudget,
  workspace : RowWorkspace,
) -> Result[Array[AggregateGroupRange], RowIssue] {
  let groups : Array[AggregateGroupRange] = []
  if indices.is_empty() {
    if order.is_empty() {
      if max_groups == 0 ||
        !spend_control(control, 1) ||
        !reserve_slots(workspace, 1) {
        return Err(RowLimit)
      }
      groups.push({ representative: None, start: 0, end: 0, })
    }
    return Ok(groups)
  }
  let mut start = 0
  for position = 1; position <= indices.length(); position = position + 1 {
    let boundary = if position == indices.length() {
      true
    } else {
      match
        compare_row_indices(
          input,
          indices[position - 1],
          indices[position],
          order,
          control,
        ) {
        Ok(comparison) => comparison != 0
        Err(InvalidInput) => return Err(InvalidRows)
        Err(Limit) => return Err(RowLimit)
        Err(Scalar(issue)) => return Err(Comparison(issue))
      }
    }
    if boundary {
      if groups.length() == max_groups ||
        !spend_control(control, 1) ||
        !reserve_slots(workspace, 1) {
        return Err(RowLimit)
      }
      groups.push({
        representative: Some(indices[start]),
        start,
        end: position,
      })
      start = position
    }
  }
  Ok(groups)
}

///|
fn[T : IndexedRows] aggregate_expression_value(
  expression : @lower.Expression,
  input : T,
  names : Array[String],
  row : Int,
  aggregate : Int,
  control : ControlBudget,
  workspace : RowWorkspace,
  scope : ExpressionRoots?,
) -> Result[Value, RowIssue] {
  let baseline = workspace.live
  let snapshot : Map[String, Value] = Map([])
  for column in 0..<names.length() {
    if !spend_control(control, 1) ||
      !spend_control_text(control, names[column]) ||
      !reserve_slots(workspace, 1) {
      release_slots(workspace, workspace.live - baseline)
      return Err(RowLimit)
    }
    snapshot[names[column]] = IndexedRows::read_cell(input, row, column)
  }
  guard scope is Some(value) else {
    release_slots(workspace, workspace.live - baseline)
    return Err(MissingOrderedResourceContext)
  }
  match charge_logical_work(value.budget, 1L) {
    Ok(_) => ()
    Err(issue) => {
      release_slots(workspace, workspace.live - baseline)
      return Err(LogicalRows(issue))
    }
  }
  let result = match
    evaluate_expression_with_workspace(
      expression,
      snapshot,
      [],
      control,
      workspace,
      logical_work=Some(value.budget),
    ) {
    Ok(value) => Ok(value)
    Err(issue) => Err(Evaluation(row, aggregate, issue))
  }
  release_slots(workspace, workspace.live - baseline)
  result
}

///|
fn[T : IndexedRows] evaluate_dynamic_aggregate(
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
  numeric? : NumericAggregateExecution? = None,
  numeric_step? : Int = -1,
  numeric_occurrence? : Int = -1,
) -> Result[Value, RowIssue] {
  let sources : Array[Int] = []
  let values : Array[Value] = []
  for position = range.start; position < range.end; position = position + 1 {
    if !spend_control(control, 1) {
      return Err(RowLimit)
    }
    let source = indices[position]
    if @lower.group_aggregate_filter(aggregate) is Some(filter) {
      let accepted = match
        aggregate_expression_value(
          filter, input, names, source, aggregate_index, control, workspace, scope,
        ) {
        Ok(Boolean(true)) => true
        Ok(Boolean(false) | Null) => false
        Ok(_) => return Err(InvalidRows)
        Err(issue) => return Err(issue)
      }
      if !accepted {
        continue
      }
    }
    let value = match argument {
      AggregateInputRows => Null
      AggregateInputField(column) =>
        IndexedRows::read_cell(input, source, column)
      AggregateInputExpression(expression) =>
        match
          aggregate_expression_value(
            expression, input, names, source, aggregate_index, control, workspace,
            scope,
          ) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
    }
    if !reserve_slots(workspace, 2) {
      return Err(RowLimit)
    }
    sources.push(source)
    values.push(value)
  }
  let contributors : AggregateContributorRows[T] = { input, sources, }
  let ordered = if order.is_empty() {
    if !reserve_slots(workspace, values.length()) ||
      !spend_control(control, values.length()) {
      return Err(RowLimit)
    }
    Array::makei(values.length(), i => i)
  } else {
    match stable_order_indices(contributors, order, control, workspace) {
      Ok(value) => value
      Err(InvalidInput) => return Err(InvalidRows)
      Err(Limit) => return Err(RowLimit)
      Err(Scalar(issue)) => return Err(Comparison(issue))
    }
  }
  if !reserve_slots(workspace, values.length()) {
    return Err(RowLimit)
  }
  let sorted = ordered.map(index => values[index])
  let rows : DynamicAggregateRows = { values: sorted, }
  let local_indices = Array::makei(rows.values.length(), i => i)
  if !reserve_slots(workspace, local_indices.length()) ||
    !spend_control(control, local_indices.length()) {
    return Err(RowLimit)
  }
  let ordered_function = match @lower.group_aggregate_function(aggregate) {
    @relation.First
    | @relation.Last
    | @relation.ArrayAgg
    | @relation.StringAgg => true
    _ => false
  }
  evaluate_direct_aggregate(
    aggregate,
    rows,
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
    if argument is AggregateInputRows {
      None
    } else {
      Some(0)
    },
    if ordered_function {
      [{ column: 1, descending: false, nulls_first: true, }]
    } else {
      []
    },
    control,
    workspace,
    selected,
    identity_limits,
    numeric~,
    numeric_step~,
    numeric_occurrence~,
  )
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
  let function = @lower.group_aggregate_function(aggregate)
  if function is @relation.ArrayAgg || function is @relation.StringAgg {
    guard argument is Some(column) && !order.is_empty() else {
      return Err(InvalidRows)
    }
    let ordered = match
      ordered_aggregate_values(
        input, indices, range, column, order, control, workspace,
      ) {
      Ok(values) => values
      Err(issue) => return Err(issue)
    }
    let values = if @lower.group_aggregate_distinct(aggregate) == Some(true) {
      match
        distinct_aggregate_values(ordered, control, workspace, identity_limits) {
        Ok(values) => values
        Err(issue) => return Err(issue)
      }
    } else {
      ordered
    }
    return if function is @relation.ArrayAgg {
      evaluate_array_aggregate(aggregate, values, selected, control, workspace)
    } else {
      evaluate_string_aggregate(aggregate, values, selected, control, workspace)
    }
  }
  if function is @relation.First || function is @relation.Last {
    guard argument is Some(column) && !order.is_empty() else {
      return Err(InvalidRows)
    }
    let members : AggregateRangeRows[T] = {
      input,
      indices,
      start: range.start,
      end: range.end,
    }
    let ordered = match
      stable_order_indices(members, order, control, workspace) {
      Ok(ordered) => ordered
      Err(InvalidInput) => return Err(InvalidRows)
      Err(Limit) => return Err(RowLimit)
      Err(Scalar(issue)) => return Err(Comparison(issue))
    }
    for offset = 0; offset < ordered.length(); offset = offset + 1 {
      if !spend_control(control, 1) {
        return Err(RowLimit)
      }
      let position = if function is @relation.First {
        offset
      } else {
        ordered.length() - offset - 1
      }
      let value = IndexedRows::read_cell(members, ordered[position], column)
      if !(value is Null) {
        return Ok(value)
      }
    }
    return Ok(Null)
  }
  let values : Array[Value] = []
  let mut count = 0
  for position = range.start; position < range.end; position = position + 1 {
    if !spend_control(control, 1) {
      return Err(RowLimit)
    }
    let value = match argument {
      None => Null
      Some(column) => IndexedRows::read_cell(input, indices[position], column)
    }
    match function {
      @relation.Count =>
        if argument is None {
          count += 1
        } else if !(value is Null) {
          if !reserve_slots(workspace, 1) {
            return Err(RowLimit)
          }
          values.push(value)
        }
      @relation.CountIf =>
        match value {
          Boolean(true) => count += 1
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
          if !reserve_slots(workspace, 1) {
            return Err(RowLimit)
          }
          values.push(value)
        }
      _ => return Err(InvalidRows)
    }
  }
  let values = if @lower.group_aggregate_distinct(aggregate) == Some(true) {
    match
      distinct_aggregate_values(values, control, workspace, identity_limits) {
      Ok(values) => values
      Err(issue) => return Err(issue)
    }
  } else {
    values
  }
  if @lower.group_aggregate_requires_numeric_observation(aggregate) {
    guard numeric is Some(execution) &&
      numeric_step >= 0 &&
      numeric_occurrence >= 0 else {
      return Err(InvalidRows)
    }
    if !reserve_slots(workspace, values.length()) {
      return Err(RowLimit)
    }
    let contributors : Array[Double] = []
    for value in values {
      guard value is Number(number) else { return Err(InvalidRows) }
      contributors.push(number)
    }
    let name = @lower.group_aggregate_name(aggregate)
    let outcome = match
      run_numeric_aggregate(
        execution,
        numeric_step,
        name,
        numeric_occurrence,
        contributors,
        contributors.length(),
        control.remaining,
      ) {
      None => return Err(InvalidRows)
      Some(Err(InvalidLimits | ContributorLimit | WorkLimit)) =>
        return Err(RowLimit)
      Some(Err(NonfiniteContributor(_) | NonfiniteIntermediate)) =>
        return Err(Aggregation(ArithmeticFailure))
      Some(Ok(value)) => value
    }
    if !spend_control(control, @numeric.outcome_work(outcome)) {
      return Err(RowLimit)
    }
    return Ok(
      match @numeric.outcome_value(outcome) {
        None => Null
        Some(value) => Number(value)
      },
    )
  }
  match function {
    @relation.Count => {
      let total = if argument is None { count } else { values.length() }
      Ok(Number(total.to_double()))
    }
    @relation.CountIf => Ok(Number(count.to_double()))
    @relation.Min | @relation.Max => {
      if values.is_empty() {
        return Ok(Null)
      }
      let mut selected = values[0]
      for i = 1; i < values.length(); i = i + 1 {
        let comparison = match
          compare_complete_value(values[i], selected, control) {
          Ok(comparison) => comparison
          Err(InvalidInput) => return Err(InvalidRows)
          Err(Limit) => return Err(RowLimit)
          Err(Scalar(issue)) => return Err(Comparison(issue))
        }
        if (function is @relation.Min && comparison < 0) ||
          (function is @relation.Max && comparison > 0) {
          selected = values[i]
        }
      }
      Ok(selected)
    }
    @relation.Sum => {
      if values.is_empty() {
        return Ok(Null)
      }
      guard @lower.group_aggregate_result(aggregate).shape
        is @contract.Decimal(precision~, scale~) else {
        return Err(InvalidRows)
      }
      let mut coefficient = "0"
      for value in values {
        guard value is Captured(@admitted.Decimal(decimal)) &&
          decimal.scale == scale else {
          return Err(InvalidRows)
        }
        coefficient = match
          add_decimal_coefficients(
            coefficient,
            decimal.coefficient,
            control,
            workspace,
          ) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
      }
      match @admitted.decimal_from_coefficient(coefficient, precision, scale) {
        Some(value) => Ok(Captured(value))
        None => Err(Aggregation(ArithmeticFailure))
      }
    }
    @relation.PercentileDisc | @relation.PercentileCont =>
      evaluate_percentile_aggregate(aggregate, values, control, workspace)
    @relation.VarPop
    | @relation.VarSamp
    | @relation.StddevPop
    | @relation.StddevSamp =>
      evaluate_statistical_aggregate(
        aggregate, values, control, workspace, identity_limits,
      )
    _ => Err(InvalidRows)
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
  if !group_execution_supported_with_profile(group, numeric is Some(_)) {
    return Err(InvalidRows)
  }
  let names = input.field_names()
  let ordinals : Map[String, Int] = Map([])
  for i in 0..<names.length() {
    if !spend_control(control, 1) ||
      !spend_control_text(control, names[i]) ||
      !reserve_slots(workspace, 1) {
      return Err(RowLimit)
    }
    if ordinals.contains(names[i]) {
      return Err(InvalidRows)
    }
    ordinals[names[i]] = i
  }
  let resolve = fn(field : @schema.FieldName) -> Result[Int, RowIssue] {
    let name = @schema.reference_name(field)
    if !spend_control(control, 1) || !spend_control_text(control, name) {
      return Err(RowLimit)
    }
    match ordinals.get(name) {
      Some(index) => Ok(index)
      None => Err(InvalidRows)
    }
  }
  let key_count = @lower.group_key_count(group)
  let aggregate_count = @lower.group_aggregate_count(group)
  if !reserve_slots(workspace, key_count) ||
    !reserve_slots(workspace, aggregate_count) ||
    !reserve_slots(workspace, aggregate_count) ||
    !reserve_slots(workspace, aggregate_count) {
    return Err(RowLimit)
  }
  let order : Array[ColumnOrder] = []
  let key_by_name : Map[String, Int] = Map([])
  for i in 0..<key_count {
    let field = @lower.group_key_at(group, i).unwrap()
    let column = match resolve(field) {
      Ok(column) => column
      Err(issue) => return Err(issue)
    }
    order.push({ column, descending: false, nulls_first: true, })
    let name = @schema.reference_name(field)
    if !key_by_name.contains(name) {
      key_by_name[name] = column
    }
  }
  let aggregate_by_name : Map[String, Int] = Map([])
  let arguments : Array[AggregateInput] = []
  let aggregate_orders : Array[Array[ColumnOrder]] = []
  for i in 0..<aggregate_count {
    let aggregate = @lower.group_aggregate_at(group, i).unwrap()
    let name = @lower.group_aggregate_name(aggregate)
    if !spend_control(control, 1) || !spend_control_text(control, name) {
      return Err(RowLimit)
    }
    aggregate_by_name[name] = i
    arguments.push(
      match @lower.group_aggregate_argument(aggregate) {
        @lower.AggregateRows => AggregateInputRows
        @lower.AggregateField(field) =>
          match resolve(field) {
            Ok(column) => AggregateInputField(column)
            Err(issue) => return Err(issue)
          }
        @lower.AggregateExpression(expression) =>
          AggregateInputExpression(expression)
      },
    )
    let term_count = @lower.group_aggregate_order_count(aggregate)
    if !reserve_slots(workspace, term_count) {
      return Err(RowLimit)
    }
    let aggregate_order : Array[ColumnOrder] = []
    for j in 0..<term_count {
      let (field, descending, nulls_first) = @lower.group_aggregate_order_term_at(
        aggregate, j,
      ).unwrap()
      let column = match resolve(field) {
        Ok(column) => column
        Err(issue) => return Err(issue)
      }
      aggregate_order.push({ column, descending, nulls_first, })
    }
    aggregate_orders.push(aggregate_order)
  }
  let schema = @lower.group_output_schema(group)
  let width = @schema.field_count(schema)
  if !reserve_slots(workspace, width) || !reserve_slots(workspace, width) {
    return Err(RowLimit)
  }
  let output_names : Array[String] = []
  let projection : Array[(Bool, Int)] = []
  for i in 0..<width {
    let name = @schema.reference_name(@schema.field_at(schema, i).unwrap().name)
    if !spend_control(control, 1) || !spend_control_text(control, name) {
      return Err(RowLimit)
    }
    output_names.push(name)
    match aggregate_by_name.get(name) {
      Some(index) => projection.push((true, index))
      None =>
        match key_by_name.get(name) {
          Some(column) => projection.push((false, column))
          None => return Err(InvalidRows)
        }
    }
  }
  let indices = match stable_order_indices(input, order, control, workspace) {
    Ok(indices) => indices
    Err(InvalidInput) => return Err(InvalidRows)
    Err(Limit) => return Err(RowLimit)
    Err(Scalar(issue)) => return Err(Comparison(issue))
  }
  let groups = match
    aggregate_group_ranges(input, indices, order, max_rows, control, workspace) {
    Ok(groups) => groups
    Err(issue) => return Err(issue)
  }
  for group_index, range in groups {
    if !spend_control(control, 1) ||
      !reserve_slots(workspace, aggregate_count) ||
      !reserve_slots(workspace, 1) ||
      !reserve_slots(workspace, width) {
      return Err(RowLimit)
    }
    let aggregate_values : Array[Value] = []
    for i in 0..<aggregate_count {
      let baseline = workspace.live
      let aggregate = @lower.group_aggregate_at(group, i).unwrap()
      let dynamic = @lower.group_aggregate_filter(aggregate) is Some(_) ||
        arguments[i] is AggregateInputExpression(_)
      let evaluated = if dynamic {
        evaluate_dynamic_aggregate(
          aggregate,
          input,
          names,
          indices,
          range,
          arguments[i],
          aggregate_orders[i],
          i,
          control,
          workspace,
          aggregate_outputs,
          identity_limits,
          scope,
          numeric~,
          numeric_step=step,
          numeric_occurrence=group_index,
        )
      } else {
        evaluate_direct_aggregate(
          aggregate,
          input,
          indices,
          range,
          match arguments[i] {
            AggregateInputRows => None
            AggregateInputField(column) => Some(column)
            AggregateInputExpression(_) => None
          },
          aggregate_orders[i],
          control,
          workspace,
          aggregate_outputs,
          identity_limits,
          numeric~,
          numeric_step=step,
          numeric_occurrence=group_index,
        )
      }
      let value = match evaluated {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      release_slots(workspace, workspace.live - baseline)
      aggregate_values.push(value)
    }
    let row : Array[Value] = []
    for (aggregate, index) in projection {
      if aggregate {
        row.push(aggregate_values[index])
      } else {
        guard range.representative is Some(source) else {
          return Err(InvalidRows)
        }
        row.push(IndexedRows::read_cell(input, source, index))
      }
    }
    if !retain_row(row, output_names, output) {
      return Err(RowLimit)
    }
    match
      accept_row(row, range.representative.unwrap_or(-1), output_names, None) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    release_slots(workspace, aggregate_count)
  }
  if numeric is Some(execution) {
    for i in 0..<aggregate_count {
      let aggregate = @lower.group_aggregate_at(group, i).unwrap()
      if @lower.group_aggregate_requires_numeric_observation(aggregate) &&
        !seal_numeric_aggregate(
          execution,
          step,
          @lower.group_aggregate_name(aggregate),
          groups.length(),
        ) {
        return Err(InvalidRows)
      }
    }
  }
  Ok(output_names)
}
