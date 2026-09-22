///|
/// One canonical index group. Sorted row indices retain logical input order
/// within an equal-key run, which is the only order observed by `first`.
priv struct PivotGroup {
  representative : Int?
  start : Int
  end : Int
}

///|
fn[T : IndexedRows] pivot_groups(
  input : T,
  indices : Array[Int],
  order : Array[ColumnOrder],
  max_groups : Int,
  control : ControlBudget,
  workspace : RowWorkspace,
) -> Result[Array[PivotGroup], RowIssue] {
  let groups : Array[PivotGroup] = []
  let add = fn(representative : Int?, start : Int, end : Int) -> Bool {
    if groups.length() >= max_groups ||
      !spend_control(control, 1) ||
      !reserve_slots(workspace, 1) {
      return false
    }
    groups.push({ representative, start, end, })
    true
  }
  if order.is_empty() {
    if !add(indices.get(0), 0, indices.length()) {
      return Err(RowLimit)
    }
    return Ok(groups)
  }
  if indices.is_empty() {
    return Ok(groups)
  }
  let mut start = 0
  for position = 1; position < indices.length(); position = position + 1 {
    if !spend_control(control, 1) {
      return Err(RowLimit)
    }
    let different = match
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
    if different {
      if !add(Some(indices[start]), start, position) {
        return Err(RowLimit)
      }
      start = position
    }
  }
  if !add(Some(indices[start]), start, indices.length()) {
    return Err(RowLimit)
  }
  Ok(groups)
}

///|
/// Empty pivot axes use first-occurrence index-group order rather than the
/// ordinary canonical key order. Sort only group coordinates, never rows.
fn first_occurrence_group_order(
  groups : Array[PivotGroup],
  control : ControlBudget,
  workspace : RowWorkspace,
) -> Result[Array[Int], RowIssue] {
  let count = groups.length()
  if !reserve_slots(workspace, count) || !spend_control(control, count) {
    return Err(RowLimit)
  }
  let mut source = Array::makei(count, i => i)
  if count < 2 {
    return Ok(source)
  }
  if !reserve_slots(workspace, count) || !spend_control(control, count) {
    return Err(RowLimit)
  }
  let mut target = Array::make(count, 0)
  let mut width = 1
  while width < count {
    let mut start = 0
    while start < count {
      let middle = start + Int::min(width, count - start)
      let end = middle + Int::min(width, count - middle)
      let mut left = start
      let mut right = middle
      for out = start; out < end; out = out + 1 {
        if !spend_control(control, 1) {
          return Err(RowLimit)
        }
        let choose_left = if left == middle {
          false
        } else if right == end {
          true
        } else {
          let a = groups[source[left]].representative.unwrap_or(-1)
          let b = groups[source[right]].representative.unwrap_or(-1)
          a <= b
        }
        if choose_left {
          target[out] = source[left]
          left += 1
        } else {
          target[out] = source[right]
          right += 1
        }
      }
      start = end
    }
    let previous = source
    source = target
    target = previous
    if width > count / 2 {
      break
    }
    width *= 2
  }
  Ok(source)
}

///|
fn pivot_fill_value(pivot : @lower.PreparedPivot) -> Value {
  match @lower.pivot_fill(pivot) {
    None | Some(@lower.Null) => Null
    Some(@lower.Value(value)) => capture(value.value)
  }
}

///|
fn pivot_requires_numeric_observation(pivot : @lower.PreparedPivot) -> Bool {
  @lower.pivot_axis_count(pivot) > 0 &&
  (
    @lower.pivot_function(pivot) is @relation.Sum ||
    @lower.pivot_function(pivot) is @relation.Avg
  ) &&
  @lower.pivot_result_contract(pivot).shape is @contract.Number
}

///|
pub fn pivot_execution_supported(pivot : @lower.PreparedPivot) -> Bool {
  pivot_execution_supported_with_profile(pivot, false)
}

///|
pub fn pivot_execution_supported_with_numeric(
  pivot : @lower.PreparedPivot,
) -> Bool {
  pivot_execution_supported_with_profile(pivot, true)
}

///|
fn pivot_execution_supported_with_profile(
  pivot : @lower.PreparedPivot,
  numeric : Bool,
) -> Bool {
  match @lower.pivot_function(pivot) {
    @relation.Count | @relation.Min | @relation.Max | @relation.First => true
    @relation.Sum =>
      @lower.pivot_result_contract(pivot).shape
      is @contract.Decimal(precision=38, ..) ||
      (
        (numeric || @lower.pivot_axis_count(pivot) == 0) &&
        @lower.pivot_result_contract(pivot).shape is @contract.Number
      )
    @relation.Avg =>
      (numeric || @lower.pivot_axis_count(pivot) == 0) &&
      @lower.pivot_result_contract(pivot).shape is @contract.Number
    _ => false
  }
}

///|
/// Deterministic pivot lane. Binary64 sum/avg use the attempt-owned selected
/// numeric executor. Exact Decimal sum retains its checked precision-38 path.
fn[T : RelationRows] evaluate_pivot_rows(
  kernel : @lower.PreparedKernel,
  input : T,
  output_id : String,
  max_rows : Int,
  control : ControlBudget,
  output : ValueBudget,
  workspace : RowWorkspace,
  numeric? : NumericAggregateExecution? = None,
  step? : Int = -1,
) -> Result[Table, RowIssue] {
  guard @lower.kernel_pivot(kernel) is Some(pivot) else {
    return Err(InvalidRows)
  }
  let function = @lower.pivot_function(pivot)
  let decimal_sum_scale = match function {
    @relation.Sum =>
      match @lower.pivot_result_contract(pivot).shape {
        @contract.Decimal(precision=38, scale~) => Some(scale)
        _ => None
      }
    _ => None
  }
  let numeric_required = pivot_requires_numeric_observation(pivot)
  if !pivot_execution_supported_with_profile(pivot, numeric is Some(_)) ||
    (numeric_required && (numeric is None || step < 0)) {
    return Err(InvalidRows)
  }
  if max_rows < 0 ||
    control.remaining < 0 ||
    control.max_frames < 0 ||
    workspace.limit < 0 ||
    workspace.live < 0 ||
    workspace.live > workspace.limit ||
    workspace.peak < workspace.live {
    return Err(InvalidRowLimits)
  }
  let names = input.field_names()
  let width = names.length()
  let ordinals : Map[String, Int] = Map([])
  for i = 0; i < width; i = i + 1 {
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
  let index_count = @lower.pivot_index_count(pivot)
  let axis_count = @lower.pivot_axis_count(pivot)
  if !reserve_slots(workspace, index_count) ||
    !reserve_slots(workspace, axis_count) ||
    !reserve_slots(workspace, axis_count) ||
    !spend_control(control, index_count + axis_count) {
    return Err(RowLimit)
  }
  let order : Array[ColumnOrder] = []
  let index_by_name : Map[String, Int] = Map([])
  for i = 0; i < index_count; i = i + 1 {
    let field = @lower.pivot_index_at(pivot, i).unwrap()
    let ordinal = match resolve(field) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    order.push({ column: ordinal, descending: false, nulls_first: true, })
    let name = @schema.reference_name(field)
    if !index_by_name.contains(name) {
      index_by_name[name] = ordinal
    }
  }
  let pivot_column = match resolve(@lower.pivot_column(pivot)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let value_column = match resolve(@lower.pivot_value(pivot)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let axis_by_name : Map[String, Int] = Map([])
  for i = 0; i < axis_count; i = i + 1 {
    let name = @lower.pivot_axis_at(pivot, i).unwrap()
    if !spend_control_text(control, name) {
      return Err(RowLimit)
    }
    if axis_by_name.contains(name) {
      return Err(InvalidRows)
    }
    axis_by_name[name] = i
  }
  let schema = @lower.pivot_output_schema(pivot)
  let output_width = @schema.field_count(schema)
  if !reserve_slots(workspace, output_width) ||
    !reserve_slots(workspace, output_width) {
    return Err(RowLimit)
  }
  let output_names : Array[String] = []
  // false selects an index column; true selects one authored pivot bucket.
  let projection : Array[(Bool, Int)] = []
  for i = 0; i < output_width; i = i + 1 {
    let name = @schema.reference_name(@schema.field_at(schema, i).unwrap().name)
    if !spend_control(control, 1) || !spend_control_text(control, name) {
      return Err(RowLimit)
    }
    output_names.push(name)
    match index_by_name.get(name) {
      Some(column) => projection.push((false, column))
      None =>
        match axis_by_name.get(name) {
          Some(axis) => projection.push((true, axis))
          None => return Err(InvalidRows)
        }
    }
  }
  let indices = match stable_order_indices(input, order, control, workspace) {
    Ok(value) => value
    Err(InvalidInput) => return Err(InvalidRows)
    Err(Limit) => return Err(RowLimit)
    Err(Scalar(issue)) => return Err(Comparison(issue))
  }
  let groups = match
    pivot_groups(input, indices, order, max_rows, control, workspace) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let group_order = if axis_count == 0 && !order.is_empty() {
    match first_occurrence_group_order(groups, control, workspace) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
  } else {
    if !reserve_slots(workspace, groups.length()) ||
      !spend_control(control, groups.length()) {
      return Err(RowLimit)
    }
    Array::makei(groups.length(), i => i)
  }
  let fill = pivot_fill_value(pivot)
  let result : Array[Array[Value]] = []
  for group_index in group_order {
    let group = groups[group_index]
    if result.length() >= max_rows ||
      !spend_control(control, 1) ||
      !reserve_slots(workspace, axis_count) ||
      !reserve_slots(workspace, axis_count) ||
      (
        (decimal_sum_scale is Some(_) || numeric_required) &&
        !reserve_slots(workspace, axis_count)
      ) ||
      !reserve_slots(workspace, output_width) {
      return Err(RowLimit)
    }
    let counts = Array::make(axis_count, 0)
    let selected : Array[Value?] = Array::make(axis_count, None)
    let sums : Array[String?] = Array::make(axis_count, None)
    let numeric_values : Array[Array[Double]] = if numeric_required {
      Array::makei(axis_count, _ => [])
    } else {
      []
    }
    for position = group.start; position < group.end; position = position + 1 {
      if !spend_control(control, 1) {
        return Err(RowLimit)
      }
      let source = indices[position]
      let axis = match IndexedRows::read_cell(input, source, pivot_column) {
        Text(name) => axis_by_name.get(name)
        Null => None
        _ => return Err(InvalidRows)
      }
      if axis is Some(axis) {
        let value = IndexedRows::read_cell(input, source, value_column)
        if !(value is Null) {
          counts[axis] += 1
          match function {
            @relation.Count => ()
            @relation.First =>
              if selected[axis] is None {
                selected[axis] = Some(value)
              }
            @relation.Min | @relation.Max =>
              match selected[axis] {
                None => selected[axis] = Some(value)
                Some(previous) => {
                  if !spend_control(control, 1) {
                    return Err(RowLimit)
                  }
                  match charge_comparison_pair(control, previous, value) {
                    Ok(_) => ()
                    Err(ComparisonChargeLimit) => return Err(RowLimit)
                    Err(ComparisonChargeInvalidOperand) =>
                      return Err(Comparison(InvalidOperand))
                  }
                  let comparison = match compare(value, previous) {
                    Ok(value) => value
                    Err(issue) => return Err(Comparison(issue))
                  }
                  if (function is @relation.Min && comparison < 0) ||
                    (function is @relation.Max && comparison > 0) {
                    selected[axis] = Some(value)
                  }
                }
              }
            @relation.Sum | @relation.Avg =>
              if numeric_required {
                guard value is Number(number) else { return Err(InvalidRows) }
                if !reserve_slots(workspace, 1) {
                  return Err(RowLimit)
                }
                numeric_values[axis].push(number)
              } else {
                guard value is Captured(@admitted.Decimal(decimal)) &&
                  decimal_sum_scale is Some(scale) &&
                  decimal.scale == scale else {
                  return Err(InvalidRows)
                }
                let previous = sums[axis].unwrap_or("0")
                sums[axis] = match
                  add_decimal_coefficients(
                    previous,
                    decimal.coefficient,
                    control,
                    workspace,
                  ) {
                  Ok(value) => Some(value)
                  Err(issue) => return Err(issue)
                }
              }
            _ => return Err(InvalidRows)
          }
        }
      }
    }
    let row : Array[Value] = []
    for (aggregate, index) in projection {
      if aggregate {
        row.push(
          match function {
            @relation.Count => Number(counts[index].to_double())
            @relation.Sum | @relation.Avg if numeric_required => {
              guard numeric is Some(execution) else { return Err(InvalidRows) }
              let values = numeric_values[index]
              let outcome = match
                run_numeric_aggregate(
                  execution,
                  step,
                  @lower.pivot_axis_at(pivot, index).unwrap(),
                  result.length(),
                  values,
                  values.length(),
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
              match @numeric.outcome_value(outcome) {
                None => fill
                Some(value) => Number(value)
              }
            }
            @relation.Sum =>
              match sums[index] {
                None => fill
                Some(coefficient) => {
                  guard decimal_sum_scale is Some(scale) else {
                    return Err(InvalidRows)
                  }
                  match
                    @admitted.decimal_from_coefficient(coefficient, 38, scale) {
                    Some(value) => Captured(value)
                    None => return Err(Aggregation(ArithmeticFailure))
                  }
                }
              }
            _ => selected[index].unwrap_or(fill)
          },
        )
      } else {
        guard group.representative is Some(source) else {
          return Err(InvalidRows)
        }
        row.push(IndexedRows::read_cell(input, source, index))
      }
    }
    if !retain_row(row, output_names, output) {
      return Err(RowLimit)
    }
    result.push(row)
  }
  if numeric_required {
    guard numeric is Some(execution) else { return Err(InvalidRows) }
    for index in 0..<axis_count {
      if !seal_numeric_aggregate(
          execution,
          step,
          @lower.pivot_axis_at(pivot, index).unwrap(),
          result.length(),
        ) {
        return Err(InvalidRows)
      }
    }
  }
  Ok({
    owner: RelationRows::checked_owner(input),
    id: output_id,
    names: output_names,
    rows: result,
  })
}
